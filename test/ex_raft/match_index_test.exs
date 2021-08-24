defmodule ExRaft.MatchIndexTest do
  use ExUnit.Case
  alias ExRaft.MatchIndex

  test "set/3" do
    match_index = MatchIndex.new() |> MatchIndex.set(:foo, 2)
    assert match_index.tree.foo === 2
    match_index = MatchIndex.set(match_index, :foo, 1)
    assert match_index.tree.foo === 1
  end

  test "incr/3" do
    match_index = MatchIndex.new() |> MatchIndex.incr(:foo, 2)
    assert match_index.tree.foo === 2
    match_index = MatchIndex.incr(match_index, :foo, 1)
    assert match_index.tree.foo === 2
    match_index = MatchIndex.incr(match_index, :foo, 3)
    assert match_index.tree.foo === 3
  end

  test "count_gte/2" do
    match_index =
      MatchIndex.new()
      |> MatchIndex.set(:foo, 6)
      |> MatchIndex.set(:bar, 1)
      |> MatchIndex.set(:baz, 5)
      |> MatchIndex.set(:fizz, 2)
      |> MatchIndex.set(:buzz, 10)

    assert MatchIndex.count_gte(match_index, 20) === 0
    assert MatchIndex.count_gte(match_index, 10) === 1
    assert MatchIndex.count_gte(match_index, 5) === 3
    assert MatchIndex.count_gte(match_index, 2) === 4
  end
end
