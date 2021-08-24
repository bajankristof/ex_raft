defmodule ExRaft do
  @type option() ::
          {:debug, boolean()}
          | {:dirty_read, boolean()}
          | {:initial_config, Keyword.t()}
          | {:min_majority, non_neg_integer()}
          | {:min_election_timeout, pos_integer()}
          | {:max_election_timeout, pos_integer()}
          | {:heartbeat_timeout, pos_integer()}
          | {:batch_size, pos_integer()}

  @type options() :: [option()]
  @type peer() :: {atom(), node()}
  @type server() :: atom() | peer()

  @spec start_server(module :: module(), options :: options()) :: Supervisor.on_start()
  def start_server(module, options),
    do: start_server(module, [], options)

  @spec start_server(module :: module(), init_arg :: any(), options :: options()) ::
          Supervisor.on_start()
  def start_server(module, init_arg, options),
    do: ExRaft.Supervisor.start_link(module, init_arg, options)

  @spec stop_server(server :: server(), reason :: atom(), timeout :: timeout()) :: :ok
  def stop_server(server, reason \\ :normal, timeout \\ :infinity),
    do: ExRaft.Supervisor.stop(server, reason, timeout)

  @spec await_leader(server :: server(), timeout :: timeout()) :: peer()
  def await_leader(server, timeout \\ 60_000),
    do: ExRaft.Server.call(server, :await_leader, timeout)

  @spec trigger_election(server :: server(), timeout :: timeout()) :: :ok
  def trigger_election(server, timeout \\ 1_000),
    do: ExRaft.Server.call(server, :trigger_election, timeout)

  @spec add_server(server :: server(), new_server :: peer(), timeout :: timeout()) ::
          :ok | any()
  def add_server(server, {name, node} = new_server, timeout \\ 60_000)
      when is_atom(name) and is_atom(node),
      do: ExRaft.Server.call(server, {:add_server, new_server}, timeout)

  @spec remove_server(server :: server(), server_to_remove :: peer(), timeout :: timeout()) ::
          :ok | any()
  def remove_server(server, {name, node} = server_to_remove, timeout \\ 60_000)
      when is_atom(name) and is_atom(node),
      do: ExRaft.Server.call(server, {:remove_server, server_to_remove}, timeout)

  @spec write(server :: server(), command :: any(), timeout :: timeout()) :: any()
  def write(server, command, timeout \\ 60_000),
    do: ExRaft.Server.call(server, {:write, command}, timeout)

  @spec read(server :: server(), query :: any(), timeout :: timeout()) :: any()
  def read(server, query, timeout \\ 60_000),
    do: ExRaft.Server.call(server, {:read, query}, timeout)

  @spec read_dirty(server :: server(), query :: any(), timeout :: timeout()) :: any()
  def read_dirty(server, query, timeout \\ 60_000),
    do: ExRaft.Server.call(server, {:read_dirty, query}, timeout)

  @spec leader(server :: server(), timeout :: timeout()) :: peer() | nil
  def leader(server, timeout \\ 1_000),
    do: ExRaft.Server.call(server, :leader, timeout)

  @spec ping(server :: server(), timeout :: timeout()) :: :pong
  def ping(server, timeout \\ 1_000),
    do: ExRaft.Server.call(server, :ping, timeout)
end
