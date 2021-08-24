defmodule ExRaft.NextIndex do
  @moduledoc false

  defstruct tree: %{}

  def new(), do: %__MODULE__{}

  def get(%__MODULE__{tree: tree}, server, default \\ nil),
    do: Map.get(tree, server, default)

  def set(%__MODULE__{tree: tree} = t, server, index),
    do: %{t | tree: Map.put(tree, server, index)}

  def decr(%__MODULE__{} = t, server, index) do
    current_index = get(t, server, index)
    set(t, server, min(current_index, index))
  end
end
