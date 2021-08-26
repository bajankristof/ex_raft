defmodule ExRaft.State.Leader do
  @moduledoc false

  use ExRaft.State
  require ExRaft.RPC
  require ExRaft.Server.Context
  import ExRaft.Server, only: [async_each: 2]
  alias ExRaft.{Log, MatchIndex, NextIndex, RPC, Server, StateMachine}
  alias ExRaft.Server.{Context, Logger}

  def enter(_, ctx) do
    ctx = Context.enter_leader(ctx)
    Logger.debug("entered leader state for term #{ctx.term}", ctx)
    StateMachine.transition(ctx.state_machine, :leader)
    Enum.each(ctx.await_leader_queue, &GenStateMachine.reply(&1, ctx.self))
    entry = Log.insert_new(ctx.log, ctx.term, :config, ctx.config)
    handle_log_change(%{ctx | await_leader_queue: [], config_change: :leader, last_entry: entry})
  end

  def exit(_, ctx) do
    Context.unset_leader(ctx)
  end

  # ========
  # | info |
  # ========

  def info(:heartbeat_timeout, ctx)
      when ctx.peers !== [] do
    async_each(ctx.peers, fn peer ->
      next_index = NextIndex.get(ctx.next_index, peer, ctx.last_entry.index + 1)
      last_index = next_index + ctx.batch_size
      prev_index = next_index - 1
      prev_entry = Log.select_at(ctx.log, prev_index)
      entries = Log.select_range(ctx.log, next_index..last_index)

      RPC.async_call(ctx.rpc, peer, %RPC.AppendRequest{
        term: ctx.term,
        commit_index: ctx.commit_index,
        prev_entry: prev_entry,
        prev_index: prev_index,
        config: ctx.config,
        entries: entries
      })
    end)

    {:keep_state, Context.reset_heartbeat_timeout(ctx)}
  end

  def info(_, _),
    do: :keep_state_and_data

  # ========
  # | cast |
  # ========

  def cast(%RPC.AppendResponse{} = response, ctx)
      when ctx.term < response.term do
    Logger.debug("received higher term, stepping down", ctx)
    {:next_state, :follower, Context.set_term(ctx, response.term)}
  end

  def cast(%RPC.AppendResponse{from: peer, index: index} = response, ctx)
      when response.success === false do
    next_index = NextIndex.decr(ctx.next_index, peer, index)
    {:keep_state, %{ctx | next_index: next_index}}
  end

  def cast(%RPC.AppendResponse{from: peer, index: index} = response, ctx)
      when response.index <= ctx.commit_index do
    match_index = MatchIndex.incr(ctx.match_index, peer, index)
    next_index = NextIndex.set(ctx.next_index, peer, index + 1)
    {:keep_state, %{ctx | match_index: match_index, next_index: next_index}}
  end

  def cast(%RPC.AppendResponse{from: peer, index: index}, ctx) do
    match_index = MatchIndex.incr(ctx.match_index, peer, index)
    next_index = NextIndex.set(ctx.next_index, peer, index + 1)
    ctx = %{ctx | match_index: match_index, next_index: next_index}

    if Context.majority_replicates?(ctx, index) do
      ctx = Context.set_commit_index(ctx, index)
      Logger.debug("committed entries up to ##{index}", ctx)
      ctx = Server.apply(ctx)

      if ctx.step_down do
        follower = MatchIndex.best_node(ctx.match_index)
        spawn(fn -> Server.call(follower, :trigger_election) end)
        {:next_state, :follower, ctx}
      else
        {:keep_state, ctx}
      end
    else
      {:keep_state, ctx}
    end
  end

  def cast(_, _),
    do: :keep_state_and_data

  # ========
  # | call |
  # ========

  def call(request, from, ctx)
      when RPC.is_request(request) and ctx.term < request.term do
    Logger.debug("received higher term, stepping down", ctx)

    {:next_state, :follower, Context.set_term(ctx, request.term),
     [{:next_event, {:call, from}, request}]}
  end

  def call(:ping, from, _) do
    GenStateMachine.reply(from, :pong)
    :keep_state_and_data
  end

  def call(:await_leader, from, ctx) do
    GenStateMachine.reply(from, ctx.self)
    :keep_state_and_data
  end

  def call(:trigger_election, from, ctx) do
    GenStateMachine.reply(from, :ok)
    {:next_state, :candidate, ctx}
  end

  def call({:remove_server, server}, from, ctx)
      when ctx.config === [server] do
    GenStateMachine.reply(from, {:error, :last_server})
    :keep_state_and_data
  end

  def call({command, _}, from, ctx)
      when command in [:add_server, :remove_server] and
             ctx.config_change === :leader do
    GenStateMachine.reply(from, {:error, :unstable_leader})
    :keep_state_and_data
  end

  def call({command, _}, from, ctx)
      when command in [:add_server, :remove_server] and
             not is_nil(ctx.config_change) do
    GenStateMachine.reply(from, {:error, :unstable_config})
    :keep_state_and_data
  end

  def call({:add_server, server}, from, ctx) do
    if Enum.member?(ctx.config, server) do
      GenStateMachine.reply(from, :ok)
      :keep_state_and_data
    else
      :lists.usort([server | ctx.config])
      |> handle_config_change(from, ctx)
    end
  end

  def call({:remove_server, server}, from, ctx) do
    if !Enum.member?(ctx.config, server) do
      GenStateMachine.reply(from, :ok)
      :keep_state_and_data
    else
      List.delete(ctx.config, server)
      |> handle_config_change(from, ctx)
    end
  end

  def call({:write, command}, from, ctx) do
    if StateMachine.command?(ctx.state_machine, command) do
      entry = Log.insert_new(ctx.log, ctx.term, :write, command, from)
      handle_log_change(%{ctx | last_entry: entry})
    else
      :keep_state_and_data
    end
  end

  def call({:read_dirty, _}, _, ctx)
      when ctx.dirty_read !== true do
    :keep_state_and_data
  end

  def call({command, query}, from, ctx)
      when command in [:read, :read_dirty] do
    case StateMachine.handle_read(ctx.state_machine, query) do
      {:reply, reply} ->
        GenStateMachine.reply(from, reply)
        :keep_state_and_data

      :noreply ->
        :keep_state_and_data
    end
  end

  def call(:leader, from, ctx) do
    GenStateMachine.reply(from, ctx.self)
    :keep_state_and_data
  end

  def call(_, _, _),
    do: :keep_state_and_data

  # ===========
  # | private |
  # ===========

  defp handle_log_change(ctx)
       when Context.is_single_server(ctx) do
    {:keep_state,
     Context.set_commit_index(ctx, ctx.last_entry.index)
     |> Server.apply()}
  end

  defp handle_log_change(ctx) do
    {:keep_state, Context.reset_heartbeat_timeout(ctx, 0)}
  end

  defp handle_config_change(config, from, ctx) do
    entry = Log.insert_new(ctx.log, ctx.term, :config, config, from)

    %{ctx | config_change: entry, last_entry: entry}
    |> Context.set_config(config)
    |> handle_log_change()
  end
end
