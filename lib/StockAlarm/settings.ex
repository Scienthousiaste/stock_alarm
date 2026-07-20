defmodule StockAlarm.Settings do
  @moduledoc false
  use Agent

  def start_link(opts) do
    Agent.start_link(fn -> %{silent: Keyword.get(opts, :silent, false)} end, name: __MODULE__)
  end

  def silent?, do: Agent.get(__MODULE__, & &1.silent)

  def toggle_silent do
    Agent.get_and_update(__MODULE__, fn state ->
      state = %{state | silent: not state.silent}
      {state.silent, state}
    end)
  end
end
