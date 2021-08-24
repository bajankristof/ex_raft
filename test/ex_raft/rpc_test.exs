defmodule ExRaft.RPCTest do
  use ExUnit.Case
  require ExRaft.RPC
  alias ExRaft.RPC

  test "is_request/1" do
    assert RPC.is_request(%RPC.VoteRequest{})
    assert RPC.is_request(%RPC.AppendRequest{})
    assert !RPC.is_request(%RPC.VoteResponse{})
    assert !RPC.is_request(%RPC.AppendResponse{})
    assert !RPC.is_request(DateTime.utc_now())
  end

  test "is_response/1" do
    assert RPC.is_response(%RPC.VoteResponse{})
    assert RPC.is_response(%RPC.AppendResponse{})
    assert !RPC.is_response(%RPC.VoteRequest{})
    assert !RPC.is_response(%RPC.AppendRequest{})
    assert !RPC.is_response(DateTime.utc_now())
  end

  test "async_call/3" do
    :meck.new(ExRaft.Server)
    :meck.expect(ExRaft.Server, :call, fn :bar, %{from: :foo}, 100 -> %RPC.VoteResponse{} end)
    :meck.expect(ExRaft.Server, :cast, fn :foo, %{from: :bar} -> :ok end)
    conn = %RPC.Conn{server: :foo, timeout: 100}
    assert RPC.async_call(conn, :bar, %RPC.VoteRequest{}) === :ok
  end
end
