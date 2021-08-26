defmodule ExRaft.Server do
  @moduledoc false

  use GenStateMachine, callback_mode: [:handle_event_function, :state_enter]
  require ExRaft.Server.Context
  alias ExRaft.{Log, StateMachine}
  alias ExRaft.Server.{Context, Logger}

  @syntax_colors [number: :yellow, atom: :cyan, string: :green, boolean: :magenta, nil: :magenta]

  defmacro state_handler(state) do
    quote do
      case unquote(state) do
        :follower -> ExRaft.State.Follower
        :candidate -> ExRaft.State.Candidate
        :leader -> ExRaft.State.Leader
      end
    end
  end

  defmacro async_each(enum, fun) do
    quote do
      Enum.each(unquote(enum), fn elem -> spawn(fn -> unquote(fun).(elem) end) end)
    end
  end

  def start_link(%{options: options} = init_state) do
    gen_state_machine_options = Keyword.take(options, [:name])
    GenStateMachine.start_link(__MODULE__, init_state, gen_state_machine_options)
  end

  def call(server, request, timeout \\ 60_000),
    do: GenStateMachine.call(server, request, timeout)

  def cast(server, request),
    do: GenStateMachine.cast(server, request)

  def apply(ctx) do
    Log.select_range(ctx.log, Context.commitable_range(ctx))
    |> Enum.reduce(ctx, fn entry, acc -> apply_entry(acc, entry) end)
  end

  @impl true
  def init(%{module: module, init_arg: init_arg} = init_ctx) do
    case StateMachine.init(module, init_arg) do
      {:ok, state_machine} ->
        init_ctx
        |> Map.put(:state_machine, state_machine)
        |> Context.new()
        |> apply()
        |> do_init()

      {:stop, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def terminate(reason, _, %Context{} = ctx) do
    Logger.debug("terminated due to #{inspect(reason)}", ctx)
    StateMachine.terminate(ctx.state_machine, reason)
  end

  def terminate(_, _, _),
    do: :ok

  @impl true
  def handle_event(:enter, state, state, ctx) do
    module = state_handler(state)
    module.enter(state, ctx)
  end

  def handle_event(:enter, prev_state, state, ctx) do
    module = state_handler(prev_state)
    ctx = module.exit(state, ctx)
    module = state_handler(state)
    module.enter(prev_state, ctx)
  end

  def handle_event({:call, from}, :state, state, _) do
    GenStateMachine.reply(from, state)
    :keep_state_and_data
  end

  def handle_event({:call, from}, request, state, ctx) do
    module = state_handler(state)
    module.call(request, from, ctx)
  end

  def handle_event(:cast, {:inspect, :context}, _, ctx) do
    IO.inspect(ctx, pretty: true, syntax_colors: @syntax_colors)
    :keep_state_and_data
  end

  def handle_event(:cast, {:inspect, :log}, _, ctx) do
    Log.select_all(ctx.log)
    |> IO.inspect(pretty: true, syntax_colors: @syntax_colors)

    :keep_state_and_data
  end

  def handle_event(:cast, request, state, ctx) do
    module = state_handler(state)
    module.cast(request, ctx)
  end

  def handle_event(:info, info, state, ctx) do
    module = state_handler(state)
    module.info(info, ctx)
  end

  def handle_event(_, _, _, _),
    do: :keep_state_and_data

  defp do_init(ctx) do
    cond do
      Context.is_single_server(ctx) -> {:ok, :leader, ctx}
      Context.is_leader(ctx) -> {:ok, :leader, ctx}
      true -> {:ok, :follower, ctx}
    end
  end

  defp apply_entry(ctx, entry) do
    {reply, state_machine, side_effects} =
      if entry.type in [:config],
        do: StateMachine.handle_system_write(ctx.state_machine, entry.type, entry.command),
        else: StateMachine.handle_write(ctx.state_machine, entry.command)

    Context.leader_exec(ctx, fn ->
      Enum.each(side_effects, &apply_side_effect/1)

      if is_tuple(entry.ref),
        do: GenStateMachine.reply(entry.ref, reply)
    end)

    %{ctx | state_machine: state_machine}
    |> apply_context_change(entry)
    |> Context.set_last_applied(entry.index)
  end

  defp apply_context_change(ctx, %{type: :config, command: config}),
    do: %{ctx | config_change: nil, step_down: !Enum.member?(config, ctx.self)}

  defp apply_context_change(ctx, _),
    do: ctx

  defp apply_side_effect({:mfa, {module, function, args}}),
    do: apply(module, function, args)
end
