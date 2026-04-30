defmodule LoreMcp.Tools.LinkFiles do
  @behaviour LoreMcp.Tool

  alias LoreMcp.{ApiClient, Git}

  @impl true
  def name, do: "lore.link_files"

  @impl true
  def description do
    """
    Pin a Lore article to one or more repo files for freshness tracking.
    Pass relative paths only — the server resolves the current commit hash
    for each path via `git log -1 --format=%H -- <path>`. You can override
    the auto-detected hash by supplying `pinned_commit` explicitly per file.

    When new commits later touch any of those files, Lore flags the article
    as potentially stale.

    Call this right after `lore.write` so the article has its sources of
    truth wired up.
    """
  end

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "slug" => %{
          "type" => "string",
          "description" => "Slug of the article to pin files to."
        },
        "files" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "path" => %{
                "type" => "string",
                "description" => "Repo-relative path."
              },
              "pinned_commit" => %{
                "type" => "string",
                "description" =>
                  "Optional. Defaults to the most recent commit that touched the file."
              }
            },
            "required" => ["path"]
          }
        }
      },
      "required" => ["slug", "files"]
    }
  end

  @impl true
  def execute(%{"slug" => slug, "files" => files}) when is_list(files) do
    repo_payload =
      case Git.repo_context() do
        {:ok, ctx} ->
          %{
            "name" => ctx.full_name,
            "remote_url" => ctx.remote_url,
            "branch" => ctx.branch
          }

        {:error, _} ->
          nil
      end

    enriched =
      Enum.map(files, fn f ->
        path = f["path"]

        sha =
          f["pinned_commit"] ||
            case Git.file_commit(path) do
              {:ok, sha} when sha != "" -> sha
              _ -> nil
            end

        f
        |> Map.put("path", path)
        |> Map.put("pinned_commit", sha)
        |> Map.put("latest_commit", f["latest_commit"] || sha)
      end)

    body =
      %{"files" => enriched}
      |> maybe_put("repository", repo_payload)

    case ApiClient.post("/api/articles/" <> slug <> "/link_files", body) do
      {:ok, %{"linked" => linked}} ->
        ok_count = Enum.count(linked, & &1["ok"])
        paths = Enum.map_join(linked, ", ", & &1["path"])
        repo_note = if repo_payload, do: " (#{repo_payload["name"]})", else: ""
        {:ok, "Linked #{ok_count} of #{length(linked)} files#{repo_note}: #{paths}"}

      {:error, {:http_error, 403, %{"error" => "repository_not_linked"} = body}} ->
        {:error,
         "Lore is not connected to '#{body["repository"]}'. Visit #{body["connect_url"]} to link it first."}

      {:error, reason} ->
        {:error, "Link failed: #{inspect(reason)}"}
    end
  end

  def execute(_), do: {:error, "Missing required parameters: slug, files"}

  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)
end
