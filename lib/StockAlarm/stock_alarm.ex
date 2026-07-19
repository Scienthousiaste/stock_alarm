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

  def current_price(ticker) do
    url = @quote_url <> URI.encode(ticker, &URI.char_unreserved?/1) <> "/"

    case HTTPoison.get(url, @headers, follow_redirect: true) do
      {:ok, response} -> extract_price_from_body(response)
      {:error, _} -> nil
    end
  end

  defp extract_price_from_body(%HTTPoison.Response{status_code: 200, body: body, headers: headers}) do
    body
    |> maybe_gunzip(headers)
    |> Floki.parse_document!()
    |> Floki.find("[data-testid=qsp-price]")
    |> Floki.text()
    |> parse_price()
  end

  defp extract_price_from_body(_), do: nil

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
