defmodule ExRaft.State.Follower do
  @moduledoc false

  use ExRaft.State
  require ExRaft.RPC
  require ExRaft.Log.Entry
  alias ExRaft.{Log, RPC, Server, StateMachine}
  alias ExRaft.Server.{Context, Logger}

  def enter(_, ctx) do
    ctx = Context.enter_follower(ctx)
    Logger.debug("entered follower state", ctx)
    StateMachine.transition(ctx.state_machine, :follower)

    if ctx.config !== [ctx.self] or ctx.min_majority <= 1,
      do: {:keep_state, Context.reset_election_timeout(ctx)},
      else: {:keep_state, ctx}
  end

  def info(:election_timeout, ctx)
      when ctx.step_down !== true do
    Logger.debug("received election timeout for term #{ctx.term}", ctx)
    {:next_state, :candidate, ctx}
  end

  def info(_, _),
    do: :keep_state_and_data

  def call(request, from, ctx)
      when RPC.is_request(request) and ctx.term < request.term do
    {:next_state, :follower,
     Context.set_term(ctx, request.term)
     |> Context.revoke_vote(), [{:next_event, {:call, from}, request}]}
  end

  def call(%RPC.VoteRequest{} = request, from, ctx)
      when request.term < ctx.term do
    GenStateMachine.reply(from, %RPC.VoteResponse{
      success: false,
      term: ctx.term,
      message: "LOW_TERM"
    })

    :keep_state_and_data
  end

  def call(%RPC.VoteRequest{} = request, from, ctx)
      when not is_nil(ctx.voted_for) and ctx.voted_for !== request.from do
    GenStateMachine.reply(from, %RPC.VoteResponse{
      success: false,
      term: ctx.term,
      message: "VOTE_CAST"
    })

    :keep_state_and_data
  end

  def call(%RPC.VoteRequest{} = request, from, ctx)
      when Log.Entry.is_older(request.last_entry, ctx.last_entry) do
    GenStateMachine.reply(from, %RPC.VoteResponse{
      success: false,
      term: request.term,
      message: "OLD_LOG"
    })

    :keep_state_and_data
  end

  def call(%RPC.VoteRequest{} = request, from, ctx) do
    GenStateMachine.reply(from, %RPC.VoteResponse{
      success: true,
      term: request.term,
      message: "OK"
    })

    {:next_state, :follower,
     Context.grant_vote(ctx, request.from)
     |> Context.reset_election_timeout()}
  end

  def call(%RPC.AppendRequest{} = request, from, ctx)
      when request.term < ctx.term do
    GenStateMachine.reply(from, %RPC.AppendResponse{
      success: false,
      term: ctx.term,
      message: "LOW_TERM"
    })

    :keep_state_and_data
  end

  def call(%RPC.AppendRequest{} = request, from, ctx) do
    ctx = Context.set_leader(ctx, request.from)

    Enum.each(ctx.await_leader_queue, &GenStateMachine.reply(&1, ctx.leader))
    ctx = %{ctx | await_leader_queue: []}

    if Log.match?(ctx.log, request.prev_entry) do
      Log.insert(ctx.log, request.entries)

      ctx =
        %{ctx | last_entry: Log.select_last(ctx.log)}
        |> Context.set_config(request.config)
        |> Context.set_commit_index(request.commit_index)

      GenStateMachine.reply(from, %RPC.AppendResponse{
        success: true,
        term: ctx.term,
        index: ctx.last_entry.index,
        message: "OK"
      })

      {:next_state, :follower,
       Server.apply(ctx)
       |> Context.reset_election_timeout()}
    else
      GenStateMachine.reply(from, %RPC.AppendResponse{
        success: false,
        term: ctx.term,
        index: Log.delete_after(ctx.log, request.prev_index - 1),
        message: "LOG_MISMATCH"
      })

      {:next_state, :follower, Context.reset_election_timeout(ctx)}
    end
  end

  def call(:ping, from, _) do
    GenStateMachine.reply(from, :pong)
    :keep_state_and_data
  end

  def call(:await_leader, from, ctx)
      when not is_nil(ctx.leader) do
    GenStateMachine.reply(from, ctx.leader)
    :keep_state_and_data
  end

  def call(:await_leader, from, ctx) do
    await_leader_queue = [from | ctx.await_leader_queue]
    {:keep_state, %{ctx | await_leader_queue: await_leader_queue}}
  end

  def call(:trigger_election, from, ctx) do
    GenStateMachine.reply(from, :ok)
    {:next_state, :candidate, ctx}
  end

  def call(:leader, from, ctx) do
    GenStateMachine.reply(from, ctx.leader)
    :keep_state_and_data
  end

  def call({:read_dirty, query}, from, ctx)
      when ctx.dirty_read === true do
    case StateMachine.handle_read(ctx.state_machine, query) do
      {:reply, reply} ->
        GenStateMachine.reply(from, reply)
        :keep_state_and_data

      :noreply ->
        :keep_state_and_data
    end
  end

  def call({command, _}, from, ctx)
      when command in [:add_server, :remove_server, :write, :read] do
    if ctx.leader,
      do: GenStateMachine.reply(from, {:error, {:redirect, ctx.leader}}),
      else: GenStateMachine.reply(from, {:error, :no_leader})

    :keep_state_and_data
  end

  def call(_, _, _),
    do: :keep_state_and_data
end
