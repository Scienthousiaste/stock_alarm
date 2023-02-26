defmodule StockAlarm.CLI do
  @moduledoc false

  # mix escript.build && ./stock_alarm

  @file_path "saved_alarms/alarms.json"

  def main(_args \\ []) do
    parse_alarms()
    |> run()
  end

  def parse_alarms do
    "saved_alarms/alarms.json"
  end
end
