defmodule ExRaft.Server.Context do
  @moduledoc false

  alias ExRaft.{KeyValueStore, Log, MatchIndex, NextIndex, RPC}

  defstruct self: nil,
            await_leader_queue: [],
            batch_size: 100,
            config: [],
            config_proposal: nil,
            commit_index: 0,
            debug: false,
            dirty_read: false,
            heartbeat_timeout: 100,
            key_value_store: nil,
            last_applied: 0,
            last_entry: nil,
            leader: nil,
            log: nil,
            match_index: 0,
            max_election_timeout: 10_000,
            min_election_timeout: 1_000,
            min_majority: nil,
            next_index: 0,
            peers: [],
            rpc: nil,
            state_machine: nil,
            step_down: false,
            term: 0,
            timer: nil,
            votes: nil,
            voted_for: nil

  defguard is_single_server(ctx)
           when ctx.config === [ctx.self] and ctx.min_majority <= 1

  defguard is_leader(ctx)
           when ctx.leader === ctx.self

  def new(%{
        key_value_store: key_value_store,
        log: log,
        options: options,
        state_machine: state_machine
      }) do
    self = {Keyword.fetch!(options, :name), node()}
    min_election_timeout = Keyword.get(options, :min_election_timeout, 1_000)
    initial_config = [self | Keyword.get(options, :initial_config, [])]
    last_config_entry = Log.select_last(log, :config)
    config = (last_config_entry && last_config_entry.command) || initial_config

    %__MODULE__{
      self: self,
      batch_size: Keyword.get(options, :batch_size, 100),
      commit_index: KeyValueStore.get(key_value_store, :commit_index, 0),
      config: :lists.usort(config),
      # debug: Keyword.get(options, :debug, false),
      debug: Keyword.get(options, :debug, true),
      dirty_read: Keyword.get(options, :dirty_read, true),
      heartbeat_timeout: Keyword.get(options, :heartbeat_timeout, 100),
      key_value_store: key_value_store,
      last_entry: Log.select_last(log),
      leader: KeyValueStore.get(key_value_store, :leader),
      log: log,
      max_election_timeout: Keyword.get(options, :max_election_timeout, 10_000),
      min_election_timeout: min_election_timeout,
      min_majority: Keyword.get(options, :min_majority, 0),
      peers: Enum.reject(config, &(&1 === self)),
      rpc: %RPC.Conn{server: self, timeout: min_election_timeout},
      state_machine: state_machine,
      term: KeyValueStore.get(key_value_store, :term, 0),
      voted_for: KeyValueStore.get(key_value_store, :voted_for)
    }
  end

  def enter_follower(%__MODULE__{} = ctx) do
    %{ctx | match_index: nil, next_index: nil}
  end

  def enter_candidate(
        %__MODULE__{
          self: self,
          key_value_store: key_value_store,
          term: term
        } = ctx
      ) do
    term = term + 1
    votes = MapSet.new([self])
    KeyValueStore.delete(key_value_store, :leader)
    KeyValueStore.put(key_value_store, :term, term)
    KeyValueStore.put(key_value_store, :voted_for, self)
    %{ctx | leader: nil, term: term, votes: votes, voted_for: self}
  end

  def enter_leader(%__MODULE__{self: self, key_value_store: key_value_store} = ctx) do
    KeyValueStore.put(key_value_store, :leader, self)
    KeyValueStore.put(key_value_store, :voted_for, self)

    %{
      ctx
      | leader: self,
        match_index: MatchIndex.new(),
        next_index: NextIndex.new(),
        voted_for: self
    }
  end

  def reset_timer(%__MODULE__{} = ctx, message, 0) do
    Process.send(self(), message, [:noconnect, :nosuspend])
    ctx
  end

  def reset_timer(%__MODULE__{timer: timer} = ctx, message, timeout) do
    if timer, do: Process.cancel_timer(timer)
    timer = Process.send_after(self(), message, timeout)
    %{ctx | timer: timer}
  end

  def reset_election_timeout(%__MODULE__{} = ctx, timeout \\ nil),
    do: reset_timer(ctx, :election_timeout, timeout || election_timeout(ctx))

  def election_timeout(%__MODULE__{
        max_election_timeout: max_election_timeout,
        min_election_timeout: min_election_timeout
      }) do
    :rand.uniform(max_election_timeout - min_election_timeout) + min_election_timeout
  end

  def reset_heartbeat_timeout(%__MODULE__{} = ctx, timeout \\ nil),
    do: reset_timer(ctx, :heartbeat_timeout, timeout || heartbeat_timeout(ctx))

  def heartbeat_timeout(%__MODULE__{
        heartbeat_timeout: heartbeat_timeout
      }) do
    heartbeat_timeout
  end

  def required_majority(%__MODULE__{config: config, min_majority: min_majority}) do
    max(ceil(length(config) / 2), min_majority)
  end

  def set_term(%__MODULE__{key_value_store: key_value_store} = ctx, term) do
    KeyValueStore.put(key_value_store, :term, term)
    %{ctx | term: term}
  end

  def grant_vote(%__MODULE__{key_value_store: key_value_store} = ctx, server) do
    KeyValueStore.put(key_value_store, :voted_for, server)
    %{ctx | voted_for: server}
  end

  def revoke_vote(%__MODULE__{key_value_store: key_value_store} = ctx) do
    KeyValueStore.delete(key_value_store, :voted_for)
    %{ctx | voted_for: nil}
  end

  def set_leader(%__MODULE__{key_value_store: key_value_store} = ctx, server) do
    KeyValueStore.put(key_value_store, :leader, server)
    KeyValueStore.put(key_value_store, :voted_for, server)
    %{ctx | leader: server, voted_for: server}
  end

  def unset_leader(%__MODULE__{key_value_store: key_value_store} = ctx) do
    KeyValueStore.delete(key_value_store, :leader)
    KeyValueStore.delete(key_value_store, :voted_for)
    %{ctx | leader: nil, voted_for: nil}
  end

  def set_commit_index(%__MODULE__{key_value_store: key_value_store} = ctx, index) do
    KeyValueStore.put(key_value_store, :commit_index, index)
    %{ctx | commit_index: index}
  end

  def set_last_applied(%__MODULE__{} = ctx, index) do
    %{ctx | last_applied: max(ctx.last_applied, index)}
  end

  def set_config(%__MODULE__{self: self} = ctx, config) do
    %{ctx | config: config, peers: Enum.reject(config, &(&1 === self))}
  end

  def majority_obeys?(%__MODULE__{votes: votes} = ctx) do
    required_majority(ctx) <= MapSet.size(votes)
  end

  def majority_replicates?(%__MODULE__{match_index: match_index} = ctx, index) do
    required_majority(ctx) - 1 <= MatchIndex.count_gte(match_index, index)
  end

  def commitable_range(%__MODULE__{last_applied: last_applied, commit_index: commit_index}) do
    (last_applied + 1)..commit_index
  end

  def leader_exec(%__MODULE__{self: self, leader: self}, fun), do: fun.()
  def leader_exec(_, _), do: :ignore

  def has_leader_commit?(%__MODULE__{commit_index: commit_index, log: log, term: term}) do
    entry = Log.select_at(log, commit_index)
    entry && entry.term === term
  end

  def has_unstable_config?(%__MODULE__{commit_index: commit_index, log: log}) do
    entry = Log.select_last(log, :config)
    entry && entry.index < commit_index
  end
end
