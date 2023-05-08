defmodule StockAlarm.CLI do
  @moduledoc false
  # mix escript.build && ./stock_alarm

  @alarm_file_path "saved_alarms/alarms.json"
  @min_time 30_000
  @max_time 90_000

  defp to_float_or_nil(nil), do: nil
  defp to_float_or_nil(price), do: String.to_float(price)

  def main(_args \\ []) do
    read_file_and_parse()
    |> run()
  end

  def read_file_and_parse do
    case File.read(@alarm_file_path) do
      {:ok, binary} ->
        binary
        |> Jason.decode!()
        |> parse_alarms()

      {:error, error} ->
        {:error, error}
    end
  end

  def parse_alarms(%{"alarms" => alarms}) do
    alarms
    |> Enum.map(&parse_alarm/1)
    |> Enum.reject(&invalid_alarms/1)
  end

  def parse_alarms(_) do
    {:error, "The alarms.json file doesn't contain alarms"}
  end

  @spec parse_alarm(map) :: %{down_price: nil | float, ticker: any, up_price: nil | float}
  def parse_alarm(alarm) do
    %{
      ticker: Map.get(alarm, "ticker"),
      up_price: Map.get(alarm, "up_price") |> to_float_or_nil,
      down_price: Map.get(alarm, "down_price") |> to_float_or_nil,
      change_step: Map.get(alarm, "change_step") |> to_float_or_nil
    }
  end

  def invalid_alarms(%{ticker: ticker, up_price: up_price, down_price: down_price}) do
    cond do
      is_nil(ticker) -> true
      is_nil(up_price) and is_nil(down_price) -> true
      true -> false
    end
  end

  def maybe_modify_alarm(%{up_price: up_price, change_step: change_step} = alarm, :up) when not is_nil(change_step) do
    Map.put(alarm, :up_price, up_price + change_step)
  end

  def maybe_modify_alarm(%{down_price: down_price, change_step: change_step} = alarm, :down) when not is_nil(change_step) do
    Map.put(alarm, :down_price, down_price - change_step)
  end

  def maybe_modify_alarm(alarm, _), do: alarm

  def launch_alarm(%{down_price: down_price, up_price: up_price, ticker: ticker} = alarm) do
    current_price = StockAlarm.current_price(ticker)

    {alert_down?, alert_up?} =
      {!is_nil(down_price) && current_price < down_price,
       !is_nil(up_price) && current_price > up_price}

    sound_alarm_if(current_price, alert_down?, alert_up?, alarm)
  end

  def play_sound(:down_sound), do: do_play_sound("down")
  def play_sound(:up_sound), do: do_play_sound("up")

  def do_play_sound(sound) do
    path =
      __ENV__.file
      |> Path.dirname()
      |> Path.dirname()
      |> Path.dirname()
      |> Path.join("/sounds/#{sound}.mp3")

    System.cmd("afplay", [path])
  end

  def sound_alarm_if(current_price, true = _alert_down?, _alert_up?, alarm) do
    IO.puts("#{alarm.ticker} is worth #{current_price}, which is under #{alarm.down_price}")
    play_sound(:down_sound)

    alarm
    |> maybe_modify_alarm(:down)
    |> wait_before_next_alarm
  end

  def sound_alarm_if(current_price, false = _alert_down?, true = _alert_up?, alarm) do
    IO.puts("#{alarm.ticker} is worth #{current_price}, which is OVER #{alarm.up_price}")
    play_sound(:up_sound)

    alarm
    |> maybe_modify_alarm(:up)
    |> wait_before_next_alarm
  end

  def sound_alarm_if(current_price, false = _alert_down?, false = _alert_up?, alarm) do
    IO.puts("#{alarm.ticker} is worth #{current_price}")
    wait_before_next_alarm(alarm)
  end

  def wait_before_next_alarm(alarm) do
    Enum.random(@min_time..@max_time)
    |> Process.sleep()

    launch_alarm(alarm)
  end

  def run({:error, error}) do
    IO.puts("The following error occured: #{error}")
  end

  def run(nil) do
    IO.puts("Could not parse the alarms.")
  end

  def run(alarms) do
    Enum.each(alarms, fn alarm ->
      Kernel.spawn(StockAlarm.CLI, :launch_alarm, [alarm])
    end)
  end
end
