defmodule ExRaft.KeyValueStore do
  @moduledoc false

  def new(),
    do: :ets.new(__MODULE__, [:set, :public])

  def put(storage, key, value),
    do: :ets.insert(storage, {key, value})

  def put_new(storage, key, value),
    do: :ets.insert_new(storage, {key, value})

  def get(storage, key, value \\ nil) do
    case :ets.lookup(storage, key) do
      [{^key, value}] -> value
      _ -> value
    end
  end

  def delete(storage, key),
    do: :ets.delete(storage, key)
end
