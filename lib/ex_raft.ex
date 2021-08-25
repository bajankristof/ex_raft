defmodule ExRaft do
  @moduledoc """
  `ExRaft` provides an Elixir implementation and an easy to use API
  for the raft consensus protocol.
  """
  @moduledoc since: "0.1.0"

  @typedoc """
  Reference to a peer.

  Used internally by `ExRaft` servers to communicate with each other.
  """
  @typedoc since: "0.1.0"
  @type peer() :: {atom(), node()}

  @typedoc """
  Reference to a server.

  Used to make calls to `ExRaft` servers.
  """
  @typedoc since: "0.1.0"
  @type server() :: atom() | peer()

  @typedoc """
  Option values used by the `start_server` functions.

  See `start_server/3` for more information.
  """
  @typedoc since: "0.1.0"
  @type option() ::
          {:debug, boolean()}
          | {:dirty_read, boolean()}
          | {:initial_config, [peer()]}
          | {:min_majority, nil | non_neg_integer()}
          | {:min_election_timeout, pos_integer()}
          | {:max_election_timeout, pos_integer()}
          | {:heartbeat_timeout, pos_integer()}
          | {:batch_size, pos_integer()}

  @typedoc """
  Options used by the `start_server` functions.

  See `start_server/3` for more information.
  """
  @typedoc since: "0.1.0"
  @type options() :: [option()]

  @doc """
  Same as `start_server/3` but sets `[]` as `init_arg`.
  """
  @doc since: "0.1.0"
  @spec start_server(module :: module(), options :: options()) :: Supervisor.on_start()
  def start_server(module, options),
    do: start_server(module, [], options)

  @doc """
  Starts a server process linked to the current process.

  Once the server is started, the `init/1` function (see `ExRaft.StateMachine`)
  of the given module is called with `init_arg` as its argument to initialize the server.

  ## Options

    * `:name` - used for name registration as described in the
      "Name Registration" section of the `GenServer` documentation.
      Note that only local names (atoms) are accepted.
      By design `ExRaft` will create an additional atom for
      the server supervisor under `:"Elixir.ExRaft.Supervisor.\#{name}"`.

      ***This is the only option required to ensure internal server communication.***

    * `:debug` - can be set to `true` to enable verbose server logs. Defaults to `false`.

    * `:dirty_read` - can be set to `false` to disable reading "dirty"
      (maybe out of date) state from followers. Defaults to `true`.

    * `:initial_config` - used to start the server with a known set of peers. Defaults to `[]`.

    * `:min_majority` - used to set a minimum expected majority.
      When set, servers will decide on achieving majority in elections and log replication
      based on the active configuration and this value (the greater value will be used).
      As an example, with a value of 2 in a 2 member cluster, the required majority will be 2,
      with the same value in a 5 member cluster, the required majority will be 3.
      Defaults to `nil`.

    * `:min_election_timeout` - used to tune the minimum amount of time in milliseconds,
      that must pass before a follower times out. Note that the actual timeout
      will be picked randomly between `:min_election_timeout` and `:max_election_timeout`.
      Defaults to `1_000`.

    * `:max_election_timeout` - used to tune the maximum amount of time in milliseconds,
      that must pass before a follower times out. Note that the actual timeout
      will be picked randomly between `:min_election_timeout` and `:max_election_timeout`.
      Defaults to `10_000`.

    * `:heartbeat_timeout` - used to set the heartbeat timeout (aka.: the time that
      will pass between leader heartbeats in log replication) in milliseconds.
      Defaults to `100`.

    * `:batch_size` - used to set the number of entries sent by leaders to followers
      in heartbeat RPCs. Defaults to `100`.

  """
  @doc since: "0.1.0"
  @spec start_server(module :: module(), init_arg :: any(), options :: options()) ::
          Supervisor.on_start()
  def start_server(module, init_arg, options),
    do: ExRaft.Supervisor.start_link(module, init_arg, options)

  @doc """
  Synchronously stops the server with the given `reason`.

  `server` will call the `terminate/2` function of the underlying state machine
  before exiting (see `ExRaft.StateMachine`).

  This function keeps OTP semantics regarding error reporting.
  If the reason is any other than `:normal`, `:shutdown` or `{:shutdown, _}`,
  an error report is logged.
  """
  @doc since: "0.1.0"
  @spec stop_server(server :: server(), reason :: atom(), timeout :: timeout()) :: :ok
  def stop_server(server, reason \\ :normal, timeout \\ :infinity),
    do: ExRaft.Supervisor.stop(server, reason, timeout)

  @doc """
  Makes a synchronous call to `server` and waits until
  `server` learns of; or becomes the cluster leader.

  Returns the elected cluster leader.
  """
  @doc since: "0.1.0"
  @spec await_leader(server :: server(), timeout :: timeout()) :: peer()
  def await_leader(server, timeout \\ 60_000),
    do: ExRaft.Server.call(server, :await_leader, timeout)

  @doc """
  Makes a synchronous call to `server` to start a new election.

  `server` replies with `:ok` immediately and becomes candidate
  to start a new election unless `server` is already a candidate
  in which case the reply will still be `:ok` but nothing happens.
  """
  @doc since: "0.1.0"
  @spec trigger_election(server :: server(), timeout :: timeout()) :: :ok
  def trigger_election(server, timeout \\ 1_000),
    do: ExRaft.Server.call(server, :trigger_election, timeout)

  @doc """
  Makes a synchronous call to `server` to add a new server to the configuration.

  ## Return values

  If all checks pass, returns `:ok` once the majority of the new configuration
  (including `new_server`) knows of `new_server` being a member of the cluster.
  (Returns `:ok` immediately if `new_server` is already a member of the cluster.)

  Otherwise returns `{:error, reason}`, where `reason` is one of the following:

    * `:no_commit` - `server` has yet to commit an entry in it's term as leader.
    * `:unstable_config` - another configuration change is pending.
    * can also return any of the error reasons specified at `write/3`

  """
  @doc since: "0.1.0"
  @spec add_server(server :: server(), new_server :: peer(), timeout :: timeout()) ::
          :ok | {:error, reason :: any()}
  def add_server(server, {name, node} = new_server, timeout \\ 60_000)
      when is_atom(name) and is_atom(node),
      do: ExRaft.Server.call(server, {:add_server, new_server}, timeout)

  @doc """
  Makes a synchronous call to `server` to remove a server from the configuration.

  ## Return values

  If all checks pass, returns `:ok` once the majority of the new configuration
  (without `server_to_remove`) knows of `server_to_remove` not being a member of the cluster.
  (Returns `:ok` immediately if `server_to_remove` is not a member of the cluster.)

  Otherwise returns `{:error, reason}`, where `reason` is one of the following:

    * `:last_server` - `server_to_remove` is the last server in the configuration.
    * `:no_commit` - `server` has yet to commit an entry in it's term as leader.
    * `:unstable_config` - another configuration change is pending.
    * can also return any of the error reasons specified at `write/3`

  """
  @doc since: "0.1.0"
  @spec remove_server(server :: server(), server_to_remove :: peer(), timeout :: timeout()) ::
          :ok | any()
  def remove_server(server, {name, node} = server_to_remove, timeout \\ 60_000)
      when is_atom(name) and is_atom(node),
      do: ExRaft.Server.call(server, {:remove_server, server_to_remove}, timeout)

  @doc """
  Makes a synchronous call to `server` to apply `command` to the state
  and waits for its reply.

  ## Return values

  If `server` is leader, it appends `command` to its log, and once the
  majority of the cluster replicates `command`, it applies `command` to the state
  by calling the `handle_write/2` function of the underlying state machine
  (see `ExRaft.StateMachine`). It then returns `reply` from the `handle_write/2` call.

  Otherwise if `server` is not leader, it returns `{:error, reason}`
  where `reason` is one of the following:

    * `:no_leader` - `server` does not know the leader of the cluster.
    * `{:redirect, leader}` - where `leader` is the leader of the cluster.

  """
  @doc since: "0.1.0"
  @spec write(server :: server(), command :: any(), timeout :: timeout()) :: any()
  def write(server, command, timeout \\ 60_000),
    do: ExRaft.Server.call(server, {:write, command}, timeout)

  @doc """
  Makes a synchronous call to `server` to read `query` from the state
  and waits for its reply.

  ## Return values

  If `server` is leader, it returns the result of calling the `handle_read/2`
  function of the underlying state machine (see `ExRaft.StateMachine`).

  Otherwise if `server` is not leader, it returns the same error as `write/3`.
  """
  @doc since: "0.1.0"
  @spec read(server :: server(), query :: any(), timeout :: timeout()) :: any()
  def read(server, query, timeout \\ 60_000),
    do: ExRaft.Server.call(server, {:read, query}, timeout)

  @doc """
  Same as `read/3`, but if `:dirty_read` is set to `true` (see `start_server/3`),
  followers are also allowed to execute the query.

  If `:dirty_read` was set to `false`, `server` never replies.
  """
  @doc since: "0.1.0"
  @spec read_dirty(server :: server(), query :: any(), timeout :: timeout()) :: any()
  def read_dirty(server, query, timeout \\ 60_000),
    do: ExRaft.Server.call(server, {:read_dirty, query}, timeout)

  @doc """
  Makes a synchronous call to `server` to retrieve its known leader
  and waits for its reply.
  """
  @doc since: "0.1.0"
  @spec leader(server :: server(), timeout :: timeout()) :: peer() | nil
  def leader(server, timeout \\ 1_000),
    do: ExRaft.Server.call(server, :leader, timeout)

  @doc false
  @doc since: "0.1.0"
  @spec ping(server :: server(), timeout :: timeout()) :: :pong
  def ping(server, timeout \\ 1_000),
    do: ExRaft.Server.call(server, :ping, timeout)
end
