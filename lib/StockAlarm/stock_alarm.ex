defmodule StockAlarm do
  @moduledoc """
  Documentation for `StockAlarm`.
  """
  @quote_url "https://finance.yahoo.com/quote/"


  def current_price(ticker) do
    HTTPoison.get!(@quote_url <> ticker)
    |> extract_price_from_body
  end

  defp find_market_price?(keywords) do
    Enum.find(keywords, fn {k, v} ->
      case k do
        "data-field" -> v === "regularMarketPrice"
        _ -> false
      end
    end)
  end

  defp extract_price_from_body(%HTTPoison.Response{status_code: 200, body: body}) do
    body
    |> Floki.parse_document!()
    |> Floki.find("#quote-header-info fin-streamer")
    |> Enum.find_value(fn fin_streamer ->
      case fin_streamer do
        {"fin-streamer", keyword_list, [value]} ->
          if find_market_price?(keyword_list), do: value |> String.replace(",", "") |> String.to_float(), else: false

        _ -> false
      end
    end)
  end
  defp extract_price_from_body(_), do: nil
end
