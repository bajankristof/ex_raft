defmodule ExRaft.Supervisor do
  @moduledoc false

  use Supervisor
  alias ExRaft.{KeyValueStore, Log, Server}

  defmacro sup_ref(name) do
    quote do: :"#{unquote(__MODULE__)}.#{unquote(name)}"
  end

  def start_link(module, init_arg, options) do
    sup_ref = Keyword.fetch!(options, :name) |> sup_ref()
    init_ctx = %{module: module, init_arg: init_arg, options: options}
    Supervisor.start_link(__MODULE__, init_ctx, name: sup_ref)
  end

  def stop(server, reason \\ :normal, timeout \\ :infinity)

  def stop({server, node}, reason, timeout)
      when is_atom(server) and is_atom(node),
      do: Supervisor.stop({sup_ref(server), node}, reason, timeout)

  def stop(server, reason, timeout)
      when is_atom(server),
      do: Supervisor.stop(sup_ref(server), reason, timeout)

  def init(init_ctx) do
    init_ctx = Map.merge(init_ctx, %{key_value_store: KeyValueStore.new(), log: Log.new()})
    Supervisor.init([Server.child_spec(init_ctx)], strategy: :one_for_one)
  end
end
