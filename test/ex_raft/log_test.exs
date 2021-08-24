defmodule ExRaft.LogTest do
  use ExUnit.Case
  alias ExRaft.Log

  test "new/0" do
    log = Log.new()
    assert is_reference(log)
  end

  test "insert_new/4" do
    log = Log.new()
    entry = Log.insert_new(log, 9, __MODULE__, nil)
    assert match?(%Log.Entry{index: 1, term: 9, type: __MODULE__}, entry)
    entry = Log.insert_new(log, 8, __MODULE__, nil)
    assert match?(%Log.Entry{index: 2, term: 8, type: __MODULE__}, entry)
  end

  test "insert/2 (single entry)" do
    log = Log.new()
    entry = Log.Entry.new(index: 9, term: 9, type: __MODULE__)
    assert Log.insert(log, entry) === entry
    matches = List.flatten(:ets.match(log, :"$1"))
    assert elem(List.first(matches), 0) === 9
  end

  test "insert/2 (multiple entries)" do
    log = Log.new()

    entry =
      Log.insert(log, [
        Log.Entry.new(index: 1),
        Log.Entry.new(index: 2),
        Log.Entry.new(index: 3)
      ])

    assert entry.index === 3
    matches = List.flatten(:ets.match(log, :"$1"))
    assert length(matches) === 3
    assert elem(List.first(matches), 0) === 1
  end

  test "select_last/1" do
    log = Log.new()
    Log.insert_new(log, 0, __MODULE__, nil)
    Log.insert_new(log, 1, __MODULE__, nil)
    Log.insert_new(log, 1, __MODULE__, nil)
    Log.insert_new(log, 2, __MODULE__, nil)
    assert match?(%Log.Entry{term: 2}, Log.select_last(log))
  end

  test "select_range/2" do
    log = Log.new()
    Enum.each(1..100, &Log.insert_new(log, &1, __MODULE__, nil))

    entries = Log.select_range(log, 1..10)
    assert length(entries) === 10
    assert match?(%Log.Entry{index: 1, term: 1}, List.first(entries))
    assert match?(%Log.Entry{index: 10, term: 10}, List.last(entries))

    entries = Log.select_range(log, 98..1_000)
    assert length(entries) === 3
    assert match?(%Log.Entry{index: 98, term: 98}, List.first(entries))
    assert match?(%Log.Entry{index: 100, term: 100}, List.last(entries))
  end

  test "select_matching/2" do
    log = Log.new()
    Log.insert_new(log, 0, __MODULE__, nil)
    Log.insert_new(log, 1, __MODULE__, nil)
    Log.insert_new(log, 2, __MODULE__, nil)

    match = Log.select_matching(log, Log.Entry.new(index: 2))
    assert match?(%Log.Entry{index: 2, term: 1}, match)
    assert is_nil(Log.select_matching(log, nil))
  end
end
