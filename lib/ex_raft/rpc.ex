defmodule ExRaft.RPC do
  @moduledoc false

  require Logger

  defmodule Conn do
    @moduledoc false
    defstruct [:server, :timeout]
  end

  defmodule VoteRequest do
    @moduledoc false
    defstruct [:from, :term, :last_entry]
  end

  defmodule VoteResponse do
    @moduledoc false
    defstruct [:from, :term, :success, :message]
  end

  defmodule AppendRequest do
    @moduledoc false
    defstruct [:from, :term, :commit_index, :prev_entry, :prev_index, :entries, :config]
  end

  defmodule AppendResponse do
    @moduledoc false
    defstruct [:from, :term, :index, :success, :message]
  end

  defguard is_request(struct)
           when is_struct(struct) and
                  struct.__struct__ in [VoteRequest, AppendRequest]

  defguard is_response(struct)
           when is_struct(struct) and
                  struct.__struct__ in [VoteResponse, AppendResponse]

  def async_call(%Conn{server: server, timeout: timeout}, peer, request) do
    request = %{request | from: server}
    response = ExRaft.Server.call(peer, request, timeout)
    if !is_response(response), do: exit(:shutdown)
    response = %{response | from: peer}
    # Logger.debug("raft: RPC response was #{inspect(response)} for #{inspect(request)}")
    ExRaft.Server.cast(server, response)
  end
end
