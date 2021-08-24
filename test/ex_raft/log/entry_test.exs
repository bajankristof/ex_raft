defmodule ExRaft.Log.EntryTest do
  use ExUnit.Case
  require ExRaft.Log.Entry
  alias ExRaft.Log.Entry

  test "is_newer/2" do
    # TODO: uncomment on release of https://github.com/elixir-lang/elixir/issues/10485
    # assert Entry.is_newer(%Entry{}, nil)
    assert Entry.is_newer(%Entry{term: 2}, %Entry{term: 1})
    assert Entry.is_newer(%Entry{index: 2}, %Entry{index: 1})
    # TODO: uncomment on release of https://github.com/elixir-lang/elixir/issues/10485
    # assert !Entry.is_newer(nil, nil)
    # assert !Entry.is_newer(nil, %Entry{})
    assert !Entry.is_newer(%Entry{term: 1}, %Entry{term: 1})
    assert !Entry.is_newer(%Entry{index: 1}, %Entry{index: 1})
    assert !Entry.is_newer(%Entry{term: 1}, %Entry{term: 2})
    assert !Entry.is_newer(%Entry{index: 1}, %Entry{index: 2})
  end

  test "is_older/2" do
    # TODO: uncomment on release of https://github.com/elixir-lang/elixir/issues/10485
    # assert !Entry.is_older(nil, nil)
    # assert !Entry.is_older(%Entry{index: 1, term: 2}, nil)
    assert Entry.is_older(%Entry{index: 10, term: 1}, %Entry{index: 1, term: 2})
    assert Entry.is_older(%Entry{index: 1, term: 2}, %Entry{index: 10, term: 2})
    assert !Entry.is_older(%Entry{index: 1, term: 2}, %Entry{index: 1, term: 2})
    assert !Entry.is_older(%Entry{index: 1, term: 2}, %Entry{index: 10, term: 1})
    assert !Entry.is_older(%Entry{index: 10, term: 1}, %Entry{index: 1, term: 1})
    # TODO: uncomment on release of https://github.com/elixir-lang/elixir/issues/10485
    # assert Entry.is_older(nil, %Entry{index: 1, term: 1})
  end

  test "query/1" do
    assert match?({:_, :_, :_, :_, :_, :_}, Entry.query())
    assert match?({1, :_, :_, :_, :_, :_}, Entry.query(index: 1))
    assert match?({:_, 1, :_, :_, :_, :_}, Entry.query(term: 1))
    assert match?({:_, :_, :foo, :_, :_, :_}, Entry.query(type: :foo))
    assert match?({:_, :_, :_, :foo, :_, :_}, Entry.query(command: :foo))
    query = Entry.query(index: 1, term: 2, type: :foo, command: :bar)
    assert match?({1, 2, :foo, :bar, :_, :_}, query)
  end

  test "new/0" do
    entry = Entry.new()
    assert entry.index === nil
    assert entry.term === nil
    assert entry.type === nil
    assert entry.command === nil
    assert entry.ref === nil
    assert is_struct(entry.date, DateTime)
  end

  test "new/1" do
    entry = Entry.new(index: 1, term: 2, type: :foo, command: :bar, ref: :baz)
    assert entry.index === 1
    assert entry.term === 2
    assert entry.type === :foo
    assert entry.command === :bar
    assert entry.ref === :baz
    assert is_struct(entry.date, DateTime)
  end

  test "to_tuple/1" do
    entry = Entry.new(index: 1, term: 2, type: :foo, command: :bar, ref: :baz)
    assert match?({1, 2, :foo, :bar, :baz, %DateTime{}}, Entry.to_tuple(entry))
  end

  test "from_tuple/1" do
    now = DateTime.utc_now()
    entry = Entry.from_tuple({1, 2, :foo, :bar, :baz, now})
    assert entry.index === 1
    assert entry.term === 2
    assert entry.type === :foo
    assert entry.command === :bar
    assert entry.ref === :baz
    assert entry.date === now
  end

  test "match?/2" do
    assert Entry.match?(nil, nil)
    assert Entry.match?(%Entry{index: 1, term: 2}, %Entry{index: 1, term: 2})
    assert !Entry.match?(nil, %Entry{index: 1, term: 2})
    assert !Entry.match?(%Entry{index: 1, term: 2}, nil)
    assert !Entry.match?(%Entry{index: 1, term: 2}, %Entry{index: 2, term: 1})
  end
end
