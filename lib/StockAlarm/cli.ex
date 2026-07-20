defmodule StockAlarm.CLI do
  @moduledoc false
  # mix escript.build && ./stock_alarm [--silent]

  def base_dir do
    :escript.script_name()
    |> List.to_string()
    |> Path.expand()
    |> Path.dirname()
  rescue
    _ -> File.cwd!()
  end

  defp alarm_file_path, do: Path.join(base_dir(), "saved_alarms/alarms.json")

  defp to_float_or_nil(nil), do: nil
  defp to_float_or_nil(price) when is_number(price), do: price * 1.0

  defp to_float_or_nil(price) do
    case Float.parse(price) do
      {value, _} -> value
      :error -> nil
    end
  end

  def main(args \\ []) do
    {opts, _argv, _errors} = OptionParser.parse(args, strict: [silent: :boolean], aliases: [s: :silent])

    read_file_and_parse()
    |> run(opts)
  end

  def read_file_and_parse do
    path = alarm_file_path()

    case File.read(path) do
      {:ok, binary} ->
        binary
        |> Jason.decode!()
        |> parse_alarms()

      {:error, error} ->
        {:error, "could not read #{path}: #{error}"}
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

  def run({:error, error}, _opts) do
    IO.puts("The following error occured: #{error}")
  end

  def run(nil, _opts) do
    IO.puts("Could not parse the alarms.")
  end

  def run(alarms, opts) do
    silent? = Keyword.get(opts, :silent, false)

    workers =
      Enum.map(alarms, fn alarm ->
        Supervisor.child_spec({StockAlarm.AlarmWorker, alarm}, id: {StockAlarm.AlarmWorker, alarm.ticker})
      end)

    # Crashed workers always restart, backing off 30s more after each
    # consecutive crash (see AlarmWorker/RestartTracker) — never give up.
    {:ok, _sup} =
      Supervisor.start_link(
        [{StockAlarm.Settings, silent: silent?}, StockAlarm.RestartTracker | workers],
        strategy: :one_for_one,
        max_restarts: 1_000_000_000,
        max_seconds: 1
      )

    IO.puts("Silent mode #{on_off(silent?)} - press 's' + Enter to toggle, 'q' + Enter to quit.")
    listen_for_commands()
  end

  defp listen_for_commands do
    case IO.gets("") do
      line when is_binary(line) ->
        line |> String.trim() |> handle_command()
        listen_for_commands()

      _eof_or_error ->
        # stdin is closed (e.g. running in the background): keep the alarms alive.
        Process.sleep(:infinity)
    end
  end

  defp handle_command("s") do
    silent? = StockAlarm.Settings.toggle_silent()
    IO.puts("#{StockAlarm.AlarmWorker.timestamp()} - Silent mode #{on_off(silent?)}")
  end

  defp handle_command("q"), do: System.halt(0)
  defp handle_command(""), do: :ok
  defp handle_command(_), do: IO.puts("Commands: s = toggle silent mode, q = quit")

  defp on_off(true), do: "ON"
  defp on_off(false), do: "OFF"
end
