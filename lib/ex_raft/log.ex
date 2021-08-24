defmodule ExRaft.Log do
  @moduledoc false

  require ExRaft.Log.Entry
  alias ExRaft.Log.Entry

  def new() do
    :ets.new(__MODULE__, [:ordered_set, :public])
  end

  def insert_new(log, term, type, command, ref \\ nil)
      when is_integer(term) do
    index = last_index(log) + 1
    entry = Entry.new(index: index, term: term, type: type, command: command, ref: ref)
    true = :ets.insert_new(log, Entry.to_tuple(entry))
    entry
  end

  def insert(log, %Entry{} = entry)
      when is_integer(entry.index) and is_integer(entry.term) do
    true = :ets.insert(log, Entry.to_tuple(entry))
    entry
  end

  def insert(log, entries)
      when is_list(entries) do
    true = :ets.insert(log, Enum.map(entries, &Entry.to_tuple/1))
    List.last(entries)
  end

  def delete_after(log, index) do
    query = Entry.query(index: :"$1")
    :ets.select_delete(log, [{query, [{:>, :"$1", index}], [true]}])
    index
  end

  def select_last(log, type \\ nil) do
    query =
      if type,
        do: Entry.query(type: type),
        else: :_

    :ets.select_reverse(log, [{query, [], [:"$_"]}], 1)
    |> extract_matches()
    |> List.first()
  end

  def select_at(log, index) do
    :ets.lookup(log, index)
    |> extract_matches()
    |> List.first()
  end

  def select_range(log, first..last) do
    query = Entry.query(index: :"$1")
    guards = [{:andalso, {:>=, :"$1", first}, {:"=<", :"$1", last}}]

    :ets.select(log, [{query, guards, [:"$_"]}])
    |> extract_matches()
  end

  def select_matching(_, nil),
    do: nil

  def select_matching(log, %Entry{index: index}),
    do: select_at(log, index)

  def match?(log, entry) do
    select_matching(log, entry)
    |> Entry.match?(entry)
  end

  defp extract_matches(matches) when is_list(matches),
    do: Enum.map(matches, &Entry.from_tuple/1)

  defp extract_matches({matches, _}) when is_list(matches),
    do: extract_matches(matches)

  defp extract_matches(:"$end_of_table"),
    do: []

  defp last_index(log) do
    last_entry = select_last(log)
    (last_entry && last_entry.index) || 0
  end
end
