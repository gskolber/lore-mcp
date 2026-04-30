defmodule LoreMcp.Tools.Read do
  @behaviour LoreMcp.Tool

  alias LoreMcp.ApiClient

  @impl true
  def name, do: "lore.read"

  @impl true
  def description,
    do:
      "Read a Lore article by slug. Returns the full markdown body plus linked files. " <>
        "If files have changed since the last verification, the response surfaces a warning so you re-read those files before trusting the doc."

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "slug" => %{
          "type" => "string",
          "description" => "Slug of the article (kebab-case)."
        }
      },
      "required" => ["slug"]
    }
  end

  @impl true
  def execute(%{"slug" => slug}) do
    case ApiClient.get("/api/articles/" <> slug) do
      {:ok, %{"article" => a}} ->
        {:ok, format(a)}

      {:error, {:http_error, 404, _}} ->
        {:error, "Article '#{slug}' not found."}

      {:error, reason} ->
        {:error, "Read failed: #{inspect(reason)}"}
    end
  end

  def execute(_), do: {:error, "Missing required parameter: slug"}

  defp format(a) do
    files = a["linked_files"] || []
    stale = Enum.filter(files, &(&1["status"] != "fresh"))

    warning =
      if stale != [] do
        paths = Enum.map_join(stale, ", ", & &1["path"])

        """
        ⚠️  This article may be out of date. The following linked files have
        changed since the last verification: #{paths}.
        Re-read those files before relying on what the article says.

        """
      else
        ""
      end

    files_str =
      if files == [],
        do: "(no linked files)",
        else:
          Enum.map_join(files, "\n", fn f ->
            "  - #{f["path"]} [#{f["status"]}] pinned @ #{f["pinned_commit"]}"
          end)

    """
    #{warning}# #{a["title"]}

    Slug: #{a["slug"]}
    Freshness: #{a["freshness"]}#{if a["verified_commit"], do: " · verified at " <> a["verified_commit"], else: ""}
    Tags: #{Enum.join(a["tags"] || [], ", ")}

    Linked files:
    #{files_str}

    ---

    #{a["content"]}
    """
  end
end
