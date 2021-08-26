defmodule ExRaft.StateMachine do
  @moduledoc """
  A behaviour module for implementing consistently replicated state machines.

  ## Example

  To start things off, let's see a code example implementing a simple
  key value store in `ExRaft` style:

      defmodule KeyValueStore do
        @behaviour ExRaft.StateMachine

        @impl true
        def init(init_state) do
          {:ok, init_state}
        end

        @impl true
        def command?({:put, _, _}, _), do: true
        def command?(_, _), do: false

        @impl true
        def handle_write({:put, key, value}, state) do
          new_state = Map.put(state, key, value)
          reply = {:ok, "I GOT IT BOSS"}
          {reply, new_state}
        end

        @impl true
        def handle_read(key, state) do
          {:reply, Map.get(state, key)}
        end
      end

      initial_config = [foo: node(), bar: node(), baz: node()]
      init_state = %{}
      {:ok, _} = ExRaft.start_server(KeyValueStore, init_state, name: :foo, initial_config: initial_config)
      {:ok, _} = ExRaft.start_server(KeyValueStore, init_state, name: :bar, initial_config: initial_config)
      {:ok, _} = ExRaft.start_server(KeyValueStore, init_state, name: :baz, initial_config: initial_config)

      leader = ExRaft.await_leader(:foo)
      # leader is now one of [{:foo, node()}, {:bar, node()}, {:baz, node()}]

      ExRaft.read(leader, :some_key)
      # nil

      ExRaft.write(KeyValueStore, {:put, :some_key, :some_value})
      # {:ok, "I GOT IT BOSS"}

      ExRaft.read(leader, :some_key)
      # :some_value

  We start a member of our `KeyValueStore` cluster by calling `ExRaft.start_server/3`,
  passing the module with the state machine implementation and its initial state
  (in this example this is just an empty map).

  In the example above we start a 3 server cluster with the names `:foo`, `:bar` and `:baz`.
  Any of these servers may become the cluster leader at startup or when the old leader fails,
  that is why we first wait for a leader to be elected by calling `ExRaft.await_leader/2`.

  After a leader was elected we can write to- and read from our replicated key value store
  by calling `ExRaft.write/3` and `ExRaft.read/3` respectively.

  Once the `ExRaft.write/3` call returns with our state machine reply
  (`{:ok, "I GOT IT BOSS"}`) we know that the majority of our cluster (2 servers in
  this example) knows that `:some_key` is in fact `:some_value`.
  This means that if the leader crashes or a network split happens between
  the leader and the rest of the cluster, the remaining 2 servers will still
  be able to elect a new leader and this new leader will still know of
  `:some_key` being `:some_value`.

  In fact if we were to issue an `ExRaft.read_dirty/3` call on the followers
  after writing `:some_key` to the state at least one, if not both of them
  would reply with `:some_value`.

  ## Improvements

  In the above example we interacted with the key value store using the `ExRaft`
  module. This is not ideal since we don't want our users to necessarily know
  how to use `ExRaft`.

  Also we started the servers by calling `ExRaft.start_server/3` directly.
  It would be better if we started them as part of a supervision tree.

  So let's fix these issues:

      defmodule KeyValueStore do
        use ExRaft.StateMachine

        @init_state %{}

        def start_link(opts),
          do: ExRaft.start_server(__MODULE__, @init_state, opts)

        def put(server, key, value),
          do: ExRaft.write(server, {:put, key, value})

        def get(server, key),
          do: ExRaft.read(server, key)

        @impl true
        def init(init_state) do
          {:ok, init_state}
        end

        @impl true
        def command?({:put, _, _}, _), do: true
        def command?(_, _), do: false

        @impl true
        def handle_write({:put, key, value}, state) do
          new_state = Map.put(state, key, value)
          reply = {:ok, "I GOT IT BOSS"}
          {reply, new_state}
        end

        @impl true
        def handle_read(key, state) do
          {:reply, Map.get(state, key)}
        end
      end

  Now we can simply call `KeyValueStore.put/3` and `KeyValueStore.get/3`
  to write to- and read from our replicated key value store.

  ### Supervision

  When we invoke `use ExRaft.StateMachine`, two things happen:

  It defines that the current module implements the `ExRaft.StateMachine`
  behaviour (`@behaviour ExRaft.StateMachine`).

  It also defines an overridable `child_spec/1` function, that allows
  us to start the `KeyValueStore` directly under a supervisor.

      children = [
        {KeyValueStore, name: :foo, initial_config: [...]}
      ]

      Supervisor.start_link(children, strategy: :one_for_one)

  This will invoke `KeyValueStore.start_link/1`, lucky for us
  we already defined this function in the improved implementation.

  ## Note

  Be aware that all callbacks (except for `c:init/1` and `c:terminate/2`)
  block the server until they return, so it is recommended to try and keep
  any heavy lifting outside of them or adjusting the `:min_election_timeout`
  and `:max_election_timeout` options of the server (see `ExRaft.start_server/3`).

  Also note that setting a high election timeout range may cause
  the cluster to stay without leader and thus become unresponsive
  for a longer period of time.

  """
  @moduledoc since: "0.1.0"

  @typedoc "The state machine state."
  @typedoc since: "0.1.0"
  @type state() :: any()

  @typedoc "Side effect values."
  @typedoc since: "0.1.0"
  @type side_effect() :: {:mfa, mfa()}

  @typedoc "Side effects executed only by the leader."
  @typedoc since: "0.1.1"
  @type side_effects() :: [side_effect()]

  @typedoc "The state machine reply."
  @typedoc since: "0.1.1"
  @type reply() :: any()

  @doc """
  Invoked when the server is started.

  `ExRaft.start_server/3` and `ExRaft.start_server/2` will block until it returns.

  `init_arg` is the second argument passed to `ExRaft.start_server/3`
  or `[]` when calling `ExRaft.start_server/2`.

  Returning `{:ok, state}` will cause `start_link/3` to return
  `{:ok, pid}` and the process to enter its loop.

  Returning `{:stop, reason}` will cause `start_link/3` to return
  `{:error, reason}` and the process to exit with reason `reason` without
  entering the loop or calling `c:terminate/2`.

  This callback is optional. If one is not implemented, `init_arg` will
  be passed along as `state`.
  """
  @doc since: "0.1.0"
  @callback init(init_arg :: any()) :: {:ok, state()} | {:stop, any()}

  @doc """
  Invoked to check commands upon `ExRaft.write/3` calls.

  Returning `true` will cause the server to continue with log replication
  and eventually apply `command` to the `state`.

  Returning `false` will make the server ignore the command,
  causing the client to eventually time out.

  This callback is optional. If one is not implemented, all commands
  will be replicated and eventually applied to the `state`.
  """
  @doc since: "0.1.0"
  @callback command?(command :: any(), state :: state()) :: boolean()

  @doc """
  Invoked to handle commands from `ExRaft.write/3` calls.

  Called when `command` is replicated to the majority of servers
  and can be safely applied to the state.

  Returning `{reply, new_state}` sends the response `reply` to the caller
  and continues the loop with new state `new_state`.

  Returning `{reply, new_state, side_effects}` is similar to `{reply, new_state}`
  except it causes the leader to execute `side_effects` (see `t:side_effects/0`).
  """
  @doc since: "0.1.0"
  @callback handle_write(command :: any(), state :: state()) ::
              {reply(), state()} | {reply(), state(), side_effects()}

  @doc """
  Invoked to handle queries from `ExRaft.read/3` and when enabled `ExRaft.read_dirty/3` calls.

  Returning `{:reply, reply}` sends the response `reply` to the caller and continues the loop.

  Returning `:noreply` does not send a response to the caller and continues the loop.
  """
  @doc since: "0.1.0"
  @callback handle_read(query :: any(), state :: state()) ::
              {:reply, reply()} | :noreply

  @doc """
  Invoked to handle configuration changes.
  Other internal command types may be added in future releases.

  Returning `{:ok, new_state}` sends the response `:ok` to the caller
  and continues the loop with new state `new_state`.

  Returning `{:ok, new_state, side_effects}` is similar to `{:ok, new_state}`
  except it causes the leader to execute `side_effects` (see `t:side_effects/0`).
  """
  @doc since: "0.1.0"
  @callback handle_system_write(type :: :config, state :: state()) ::
              {:ok, state()} | {:ok, state(), side_effects()}

  @doc """
  Invoked when the server transitions to a new raft state.

  The return value is ignored.

  This callback is optional.
  """
  @doc since: "0.1.0"
  @callback transition(to_state :: :follower | :candidate | :leader, state :: state()) :: any()

  @doc """
  Invoked when the server is about to exit. It should do any cleanup required.

  `reason` is exit reason and `state` is the current state of the state machine.
  The return value is ignored.

  `c:terminate/2` is called if the state machine traps exits (using `Process.flag/2`)
  *and* the parent process sends an exit signal.

  If `reason` is neither `:normal`, `:shutdown`, nor `{:shutdown, term}` an error is
  logged.

  For a more in-depth explanation, please read the "Shutdown values (:shutdown)"
  section in the `Supervisor` module and the `c:GenServer.terminate/2`
  callback documentation.

  This callback is optional.
  """
  @doc since: "0.1.0"
  @callback terminate(reason :: any(), state :: state()) :: :ok

  @optional_callbacks init: 1, command?: 2, handle_system_write: 2, transition: 2, terminate: 2

  defstruct [:module, :state]

  defmacro __using__(_) do
    quote do
      @behaviour unquote(__MODULE__)

      def child_spec(init_arg),
        do: %{id: __MODULE__, start: {__MODULE__, :start_link, [init_arg]}}

      defoverridable child_spec: 1
    end
  end

  @doc false
  def init(module, init_arg) do
    if function_exported?(module, :init, 1) do
      case module.init(init_arg) do
        {:ok, state} ->
          {:ok, %__MODULE__{module: module, state: state}}

        {:stop, reason} ->
          {:stop, reason}
      end
    else
      {:ok, %__MODULE__{module: module, state: init_arg}}
    end
  end

  @doc false
  def command?(%__MODULE__{module: module} = state_machine, command) do
    if function_exported?(module, :command?, 2),
      do: module.command?(command, state_machine.state),
      else: true
  end

  @doc false
  def handle_write(%__MODULE__{module: module} = state_machine, command) do
    case module.handle_write(command, state_machine.state) do
      {reply, state, side_effects} ->
        {reply, %{state_machine | state: state}, side_effects}

      {reply, state} ->
        {reply, %{state_machine | state: state}, []}
    end
  end

  @doc false
  def handle_read(%__MODULE__{module: module} = state_machine, query),
    do: module.handle_read(query, state_machine.state)

  @doc false
  def handle_system_write(%__MODULE__{module: module} = state_machine, type, content) do
    if function_exported?(module, :handle_system_write, 3) do
      case module.handle_system_write(type, content, state_machine.state) do
        {:ok, state, side_effects} ->
          {:ok, %{state_machine | state: state}, side_effects}

        {:ok, state} ->
          {:ok, %{state_machine | state: state}, []}
      end
    else
      {:ok, state_machine, []}
    end
  end

  @doc false
  def transition(%__MODULE__{module: module} = state_machine, to_state) do
    if function_exported?(module, :transition, 2),
      do: module.transition(to_state, state_machine.state),
      else: :ok
  end

  @doc false
  def terminate(%__MODULE__{module: module} = state_machine, reason) do
    if function_exported?(module, :terminate, 2),
      do: module.terminate(reason, state_machine.state),
      else: :ok
  end
end
