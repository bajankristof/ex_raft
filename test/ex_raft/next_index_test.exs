defmodule ExRaft.NextIndexTest do
  use ExUnit.Case
  alias ExRaft.NextIndex

  test "set/3" do
    next_index = NextIndex.new() |> NextIndex.set(:foo, 2)
    assert next_index.tree.foo === 2
    next_index = NextIndex.set(next_index, :foo, 1)
    assert next_index.tree.foo === 1
  end

  test "decr/3" do
    next_index = NextIndex.new() |> NextIndex.decr(:foo, 2)
    assert next_index.tree.foo === 2
    next_index = NextIndex.decr(next_index, :foo, 1)
    assert next_index.tree.foo === 1
    next_index = NextIndex.decr(next_index, :foo, 3)
    assert next_index.tree.foo === 1
  end
end
