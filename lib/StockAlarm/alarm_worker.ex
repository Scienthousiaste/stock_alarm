defmodule StockAlarm.AlarmWorker do
  @moduledoc false
  use GenServer

  @startup_delay 5_000
  # After a crash, wait streak * 30s before resuming: 30s, 1min, 1min30...
  @backoff_step 30_000
  @min_time 30_000
  @max_time 90_000

  def start_link(alarm) do
    GenServer.start_link(__MODULE__, alarm)
  end

  @impl true
  def init(alarm) do
    case StockAlarm.RestartTracker.register(alarm.ticker) do
      0 ->
        Process.send_after(self(), :check, @startup_delay)

      streak ->
        delay = streak * @backoff_step
        IO.puts("#{timestamp()} - #{alarm.ticker} alarm crashed, waiting #{div(delay, 1000)}s before resuming")
        Process.send_after(self(), :check, delay)
    end

    {:ok, alarm}
  end

  @impl true
  def handle_info(:check, alarm) do
    alarm = check_price(alarm)
    StockAlarm.RestartTracker.reset(alarm.ticker)
    Process.send_after(self(), :check, Enum.random(@min_time..@max_time))
    {:noreply, alarm}
  end

  def check_price(%{down_price: down_price, up_price: up_price, ticker: ticker} = alarm) do
    case StockAlarm.current_quote(ticker) do
      nil ->
        IO.puts("#{timestamp()} - Could not fetch the price of #{ticker}, will retry")
        alarm

      %{price: current_price} = stock_quote ->
        {alert_down?, alert_up?} =
          {!is_nil(down_price) && current_price < down_price,
           !is_nil(up_price) && current_price > up_price}

        sound_alarm_if(stock_quote, alert_down?, alert_up?, alarm)
    end
  end

  def sound_alarm_if(stock_quote, true = _alert_down?, _alert_up?, alarm) do
    IO.puts("#{format_quote(alarm.ticker, stock_quote)}, which is under #{alarm.down_price}")
    play_sound(:down_sound)
    maybe_modify_alarm(alarm, :down)
  end

  def sound_alarm_if(stock_quote, false = _alert_down?, true = _alert_up?, alarm) do
    IO.puts("#{format_quote(alarm.ticker, stock_quote)}, which is OVER #{alarm.up_price}")
    play_sound(:up_sound)
    maybe_modify_alarm(alarm, :up)
  end

  def sound_alarm_if(stock_quote, false = _alert_down?, false = _alert_up?, alarm) do
    IO.puts(format_quote(alarm.ticker, stock_quote))
    alarm
  end

  def maybe_modify_alarm(%{up_price: up_price, change_step: change_step} = alarm, :up) when not is_nil(change_step) do
    Map.put(alarm, :up_price, up_price + change_step)
  end

  def maybe_modify_alarm(%{down_price: down_price, change_step: change_step} = alarm, :down) when not is_nil(change_step) do
    Map.put(alarm, :down_price, down_price - change_step)
  end

  def maybe_modify_alarm(alarm, _), do: alarm

  def play_sound(:down_sound), do: do_play_sound("down")
  def play_sound(:up_sound), do: do_play_sound("up")

  def do_play_sound(sound) do
    unless StockAlarm.Settings.silent?() do
      path = Path.join(StockAlarm.CLI.base_dir(), "sounds/#{sound}.mp3")

      System.cmd("afplay", [path])
    end
  end

  # "14:32 - AAPL is worth 212.43 (+0.63%)", price green on gain, red on loss.
  defp format_quote(ticker, %{price: price, change_percent: percent}) do
    "#{timestamp()} - #{ticker} is worth #{colorize(price, percent)}#{percent_suffix(percent)}"
  end

  defp colorize(price, nil), do: "#{price}"

  defp colorize(price, percent) do
    color = if percent < 0, do: IO.ANSI.red(), else: IO.ANSI.green()
    "#{color}#{price}#{IO.ANSI.reset()}"
  end

  defp percent_suffix(nil), do: ""

  defp percent_suffix(percent) do
    sign = if percent < 0, do: "", else: "+"
    " (#{sign}#{:erlang.float_to_binary(percent, decimals: 2)}%)"
  end

  def timestamp do
    "Europe/Paris"
    |> DateTime.now!(Tz.TimeZoneDatabase)
    |> Calendar.strftime("%H:%M")
  end
end
