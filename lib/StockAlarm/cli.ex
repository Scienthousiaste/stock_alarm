defmodule StockAlarm.CLI do
  @moduledoc false
  # mix escript.build && ./stock_alarm

  @alarm_file_path "saved_alarms/alarms.json"
  @min_time 30_000
  @max_time 90_000

  def main(_args \\ []) do
    read_file_and_parse()
    |> decouple_up_down_and_parse_prices()
    |> run()
  end

  def decouple_up_down_and_parse_prices(alarms) do
    alarms
    |> Enum.reduce([], fn alarm, acc ->
      case alarm do
        %{ticker: t, down_price: down, up_price: up} when not is_nil(down) and not is_nil(up) ->
          acc ++
            [
              %{ticker: t, down_price: String.to_float(down)},
              %{ticker: t, up_price: String.to_float(up)}
            ]

        %{ticker: t, down_price: down, up_price: up} when is_nil(down) and not is_nil(up) ->
          [%{ticker: t, up_price: String.to_float(up)} | acc]

        %{ticker: t, down_price: down, up_price: up} when is_nil(up) and not is_nil(down) ->
          [%{ticker: t, down_price: String.to_float(down)} | acc]

        _ ->
          acc
      end
    end)
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

  def parse_alarm(alarm) do
    %{
      ticker: Map.get(alarm, "ticker"),
      up_price: Map.get(alarm, "up_price"),
      down_price: Map.get(alarm, "down_price")
    }
  end

  def invalid_alarms(%{ticker: ticker, up_price: up_price, down_price: down_price}) do
    cond do
      is_nil(ticker) -> true
      is_nil(up_price) and is_nil(down_price) -> true
      true -> false
    end
  end

  def launch_alarm(%{down_price: target_price, ticker: ticker} = alarm) do
    current_price = StockAlarm.current_price(ticker)
    sound_alarm_if(current_price, current_price < target_price, alarm)
  end

  def launch_alarm(%{up_price: target_price, ticker: ticker} = alarm) do
    current_price = StockAlarm.current_price(ticker)
    sound_alarm_if(current_price, current_price > target_price, alarm)
  end

  def sound_alarm_if(current_price, should_alert?, alarm) do
    if should_alert? do
      if Map.get(alarm, :down_price) do
        IO.puts("#{alarm.ticker} is worth #{current_price}, which is under #{alarm.down_price}")
      else
        IO.puts("#{alarm.ticker} is worth #{current_price}, which is OVER #{alarm.up_price}")
      end

      path =
        __ENV__.file
        |> Path.dirname()
        |> Path.dirname()
        |> Path.dirname()
        |> Path.join("/sounds/alert.mp3")

      System.cmd("afplay", [path])
    else
      IO.puts("#{alarm.ticker} is worth #{current_price}")
    end

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
