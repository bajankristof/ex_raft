defmodule ExRaft.StateMachine do
  @type state() :: any()
  @type side_effect() :: {:mfa, mfa()}

  @callback init(init_arg :: any()) :: {:ok, state()} | {:stop, any()}
  @callback command?(command :: any(), state :: state()) :: boolean()
  @callback handle_write(command :: any(), state :: state()) ::
              {any(), state()} | {any(), state(), [side_effect()]}
  @callback handle_read(query :: any(), state :: state()) :: any()
  @callback handle_system_write(:config, state :: state()) ::
              {:ok, state()} | {:ok, state(), [side_effect()]}
  @callback transition(to_state :: :follower | :candidate | :leader, state :: state()) :: any()
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
