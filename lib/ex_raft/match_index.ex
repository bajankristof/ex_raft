defmodule ExRaft.MatchIndex do
  @moduledoc false

  defstruct tree: %{}

  def new(), do: %__MODULE__{}

  def get(%__MODULE__{tree: tree}, server, default \\ nil),
    do: Map.get(tree, server, default)

  def set(%__MODULE__{tree: tree} = t, server, index),
    do: %{t | tree: Map.put(tree, server, index)}

  def incr(%__MODULE__{} = t, server, index) do
    current_index = get(t, server, index)
    set(t, server, max(current_index, index))
  end

  def count_gte(%__MODULE__{tree: tree}, index),
    do: Enum.count(tree, &(index <= elem(&1, 1)))

  def best_node(%__MODULE__{tree: tree})
      when map_size(tree) === 0,
      do: nil

  def best_node(%__MODULE__{tree: tree}),
    do: Enum.max(tree) |> elem(0)
end
