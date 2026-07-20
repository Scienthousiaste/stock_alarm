defmodule StockAlarm.RestartTracker do
  @moduledoc false
  # Counts consecutive crashes per ticker, so a restarted worker can back off
  # (30s, then 1min, then 1min30...) instead of resuming right away. Streaks
  # live here rather than in the workers because a crash wipes worker state.
  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  # Called by a worker on start: monitors it and returns its current crash streak.
  def register(ticker), do: GenServer.call(__MODULE__, {:register, ticker, self()})

  def reset(ticker), do: GenServer.cast(__MODULE__, {:reset, ticker})

  @impl true
  def init(:ok), do: {:ok, %{streaks: %{}, monitored: %{}}}

  @impl true
  def handle_call({:register, ticker, pid}, _from, state) do
    ref = Process.monitor(pid)
    state = put_in(state.monitored[ref], ticker)
    {:reply, Map.get(state.streaks, ticker, 0), state}
  end

  @impl true
  def handle_cast({:reset, ticker}, state) do
    {:noreply, put_in(state.streaks[ticker], 0)}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    {ticker, state} = pop_in(state.monitored[ref])

    if is_nil(ticker) or clean_exit?(reason) do
      {:noreply, state}
    else
      {:noreply, update_in(state.streaks[ticker], &((&1 || 0) + 1))}
    end
  end

  defp clean_exit?(:normal), do: true
  defp clean_exit?(:shutdown), do: true
  defp clean_exit?({:shutdown, _}), do: true
  defp clean_exit?(_), do: false
end
