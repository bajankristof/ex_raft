defmodule ExRaft.Server.Logger do
  @moduledoc false

  alias ExRaft.Server.Context

  require Logger

  defmacrop fmt(message, ctx) do
    quote do: "raft: #{inspect(unquote(ctx).self)} #{unquote(message)}"
  end

  def debug(message, %Context{debug: true} = ctx),
    do: Logger.debug(fmt("#{message} with #{inspect(ctx)}", ctx))

  def debug(_, _), do: :ok

  def info(message, %Context{} = ctx),
    do: Logger.info(fmt(message, ctx))

  def notice(message, %Context{} = ctx),
    do: Logger.notice(fmt(message, ctx))

  def warning(message, %Context{} = ctx),
    do: Logger.warning(fmt(message, ctx))
end
