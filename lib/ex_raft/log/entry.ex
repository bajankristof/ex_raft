defmodule ExRaft.Log.Entry do
  @moduledoc false

  @fields [:index, :term, :type, :command, :ref, :date]
  defstruct @fields

  defguard is_newer(entry, than)
           when (not is_nil(entry) and is_nil(than)) or
                  (not is_nil(entry) and not is_nil(than) and
                     (than.term < entry.term or
                        (than.term === entry.term and than.index < entry.index)))

  defguard is_older(entry, than)
           when entry !== than and not is_newer(entry, than)

  defmacro query(overrides \\ []) do
    default_query = Enum.map(@fields, &{&1, :_})
    query = Keyword.merge(default_query, overrides)
    # HACK: maybe there is a better way to generate this AST
    query_ast = {:{}, [], query |> new() |> to_tuple() |> Tuple.to_list()}
    quote do: unquote(query_ast)
  end

  def new(values \\ []),
    do: struct(__MODULE__, [{:date, DateTime.utc_now()} | values])

  def to_tuple(%__MODULE__{} = entry),
    do: {entry.index, entry.term, entry.type, entry.command, entry.ref, entry.date}

  def from_tuple({index, term, type, command, ref, date}),
    do: %__MODULE__{index: index, term: term, type: type, command: command, ref: ref, date: date}

  def match?(nil, nil), do: true

  def match?(%__MODULE__{} = this, %__MODULE__{} = that),
    do: this.term === that.term and this.index === that.index

  def match?(_, _), do: false
end
