defmodule StockAlarm do
  @moduledoc """
  Documentation for `StockAlarm`.
  """
  @quote_url "https://finance.yahoo.com/quote/"
  # Yahoo Finance replies 429 Too Many Requests to non-browser user agents.
  @headers [
    {"User-Agent",
     "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"}
  ]

  def current_quote(ticker) do
    url = @quote_url <> URI.encode(ticker, &URI.char_unreserved?/1) <> "/"

    case HTTPoison.get(url, @headers, follow_redirect: true) do
      {:ok, response} -> extract_quote_from_body(response)
      {:error, _} -> nil
    end
  end

  defp extract_quote_from_body(%HTTPoison.Response{status_code: 200, body: body, headers: headers}) do
    document =
      body
      |> maybe_gunzip(headers)
      |> Floki.parse_document!()

    case document |> Floki.find("[data-testid=qsp-price]") |> Floki.text() |> parse_price() do
      nil -> nil
      price -> %{price: price, change_percent: extract_change_percent(document)}
    end
  end

  defp extract_quote_from_body(_), do: nil

  # The percent next to the price, e.g. "(+0.63%)" or "(-1.20%)".
  defp extract_change_percent(document) do
    document
    |> Floki.find("[data-testid=qsp-price-change-percent]")
    |> Floki.text()
    |> String.replace(["(", ")", "%", "+"], "")
    |> parse_price()
  end

  # Yahoo gzips the body even when the client didn't send Accept-Encoding.
  defp maybe_gunzip(body, headers) do
    gzipped? =
      Enum.any?(headers, fn {name, value} ->
        String.downcase(name) == "content-encoding" and value =~ "gzip"
      end)

    if gzipped?, do: :zlib.gunzip(body), else: body
  end

  defp parse_price(text) do
    case text |> String.replace(",", "") |> String.trim() |> Float.parse() do
      {price, _} -> price
      :error -> nil
    end
  end
end
