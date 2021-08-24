defmodule ExRaft.State do
  @moduledoc false

  alias ExRaft.Server.Context

  @callback enter(prev_state :: atom(), ctx :: Context.t()) ::
              :gen_statem.state_enter_result()

  @callback info(info :: any(), ctx :: Context.t()) ::
              :gen_statem.state_callback_result()

  @callback cast(request :: any(), ctx :: Context.t()) ::
              :gen_statem.state_callback_result()

  @callback call(request :: any(), from :: :gen_statem.from(), ctx :: Context.t()) ::
              :gen_statem.state_callback_result()

  @callback exit(new_state :: atom(), ctx :: Context.t()) ::
              Context.t()

  defmacro __using__(_) do
    quote do
      @behaviour unquote(__MODULE__)

      def cast(_, _), do: :keep_state_and_data
      def exit(_, ctx), do: ctx

      defoverridable cast: 2, exit: 2
    end
  end
end
