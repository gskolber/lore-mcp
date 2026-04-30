defmodule LoreMcp.ApiClient do
  @moduledoc "HTTP wrapper around the Lore Phoenix API."

  def base_url, do: System.get_env("LORE_URL") || "http://localhost:4000"

  def token do
    case System.get_env("LORE_TOKEN") do
      nil -> raise "LORE_TOKEN env var is required"
      "" -> raise "LORE_TOKEN env var is required"
      tok -> tok
    end
  end

  def get(path) do
    request(:get, path, nil)
  end

  def post(path, body) do
    request(:post, path, body)
  end

  def put(path, body) do
    request(:put, path, body)
  end

  defp request(method, path, body) do
    opts = [
      url: base_url() <> path,
      headers: [
        {"authorization", "Bearer " <> token()},
        {"content-type", "application/json"}
      ]
    ]

    opts = if body, do: Keyword.put(opts, :json, body), else: opts

    case apply(Req, method, [Req.new(opts)]) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
