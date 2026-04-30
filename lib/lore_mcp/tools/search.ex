defmodule LoreMcp.Tools.Search do
  @behaviour LoreMcp.Tool

  alias LoreMcp.ApiClient

  @impl true
  def name, do: "lore.search"

  @impl true
  def description,
    do:
      "Search the Lore wiki for articles matching a query. Returns ranked results with title, slug, freshness and snippet."

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "q" => %{"type" => "string", "description" => "Search query."}
      },
      "required" => ["q"]
    }
  end

  @impl true
  def execute(%{"q" => q}) do
    case ApiClient.get("/api/search?q=" <> URI.encode(q)) do
      {:ok, %{"results" => results}} ->
        {:ok, format(results)}

      {:error, reason} ->
        {:error, "Search failed: #{inspect(reason)}"}
    end
  end

  def execute(_), do: {:error, "Missing required parameter: q"}

  defp format([]), do: "No articles match that query."

  defp format(results) do
    results
    |> Enum.map(fn r ->
      """
      ## #{r["title"]}
      slug: #{r["slug"]}
      freshness: #{r["freshness"]}#{if r["verified_commit"], do: " (verified at " <> r["verified_commit"] <> ")", else: ""}
      tags: #{Enum.join(r["tags"] || [], ", ")}

      #{r["snippet"]}
      """
    end)
    |> Enum.join("\n---\n\n")
  end
end
