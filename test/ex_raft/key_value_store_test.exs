defmodule ExRaft.KeyValueStoreTest do
  use ExUnit.Case
  alias ExRaft.KeyValueStore

  test "put/3" do
    key_value_store = KeyValueStore.new()
    assert KeyValueStore.put(key_value_store, :test, 1)
  end

  test "put_new/3" do
    key_value_store = KeyValueStore.new()
    assert KeyValueStore.put_new(key_value_store, :test, 1)
    assert !KeyValueStore.put_new(key_value_store, :test, 2)
  end

  test "get/3" do
    key_value_store = KeyValueStore.new()
    assert KeyValueStore.put(key_value_store, :test, 1)
    assert KeyValueStore.get(key_value_store, :test) === 1
    assert KeyValueStore.get(key_value_store, :notest) === nil
    assert KeyValueStore.get(key_value_store, :notest, 1) === 1
  end

  test "delete/2" do
    key_value_store = KeyValueStore.new()
    assert KeyValueStore.put_new(key_value_store, :test, 1)
    assert KeyValueStore.get(key_value_store, :test) === 1
    assert KeyValueStore.delete(key_value_store, :test)
    assert KeyValueStore.get(key_value_store, :test) === nil
    assert KeyValueStore.put_new(key_value_store, :test, 2)
    assert KeyValueStore.get(key_value_store, :test) === 2
  end
end
