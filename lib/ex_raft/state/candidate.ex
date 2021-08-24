defmodule ExRaft.State.Candidate do
  @moduledoc false

  use ExRaft.State
  require ExRaft.Server.Context
  import ExRaft.Server, only: [async_each: 2]
  alias ExRaft.{RPC, StateMachine}
  alias ExRaft.Server.{Context, Logger}
  alias ExRaft.State.Follower

  def enter(_, ctx) do
    ctx = Context.enter_candidate(ctx)
    Logger.debug("entered candidate state for term #{ctx.term}", ctx)
    StateMachine.transition(ctx.state_machine, :candidate)

    async_each(ctx.peers, fn peer ->
      RPC.async_call(ctx.rpc, peer, %RPC.VoteRequest{
        term: ctx.term,
        last_entry: ctx.last_entry
      })
    end)

    if Context.is_single_server(ctx),
      do: {:keep_state, Context.reset_election_timeout(ctx, 0)},
      else: {:keep_state, Context.reset_election_timeout(ctx)}
  end

  def info(:election_timeout, ctx)
      when Context.is_single_server(ctx) do
    {:next_state, :leader, ctx}
  end

  def info(:election_timeout, ctx) do
    Logger.debug("received election timeout for term #{ctx.term}", ctx)
    enter(:candidate, ctx)
  end

  def info(_, _),
    do: :keep_state_and_data

  def cast(%RPC.VoteResponse{} = response, ctx)
      when ctx.term < response.term do
    Logger.debug("received higher term, stepping down", ctx)
    {:next_state, :follower, Context.set_term(ctx, response.term)}
  end

  def cast(%RPC.VoteResponse{from: peer} = response, ctx)
      when response.success === true do
    Logger.debug("received vote from #{inspect(peer)}", ctx)
    ctx = %{ctx | votes: MapSet.put(ctx.votes, peer)}

    if Context.majority_obeys?(ctx),
      do: {:next_state, :leader, ctx},
      else: {:keep_state, ctx}
  end

  def cast(_, _),
    do: :keep_state_and_data

  def call(request, from, ctx),
    do: Follower.call(request, from, ctx)
end
