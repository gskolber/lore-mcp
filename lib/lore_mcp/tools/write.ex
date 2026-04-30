defmodule LoreMcp.Tools.Write do
  @behaviour LoreMcp.Tool

  alias LoreMcp.{ApiClient, Git}

  @impl true
  def name, do: "lore.write"

  @impl true
  def description do
    """
    Create or update a Lore article. The change is recorded in the article's
    history attributed to Claude (this MCP server). Use this when the user
    asks you to document something about the codebase, when you read a doc
    that's stale and want to refresh it, or when you learn something during
    debugging that future-you would want to know.

    If the slug already exists, this updates it (a new version is appended to
    the timeline). Otherwise it creates a new article.
    """
  end

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "slug" => %{
          "type" => "string",
          "description" => "Slug — kebab-case identifier."
        },
        "title" => %{
          "type" => "string",
          "description" => "Title (required when creating a new article)."
        },
        "content" => %{
          "type" => "string",
          "description" => "Markdown body of the article."
        },
        "snippet" => %{
          "type" => "string",
          "description" => "1–2 sentence summary used in cards and search."
        },
        "tags" => %{"type" => "string", "description" => "Comma-separated tags."},
        "path" => %{"type" => "string", "description" => "Logical path/folder."},
        "edit_title" => %{
          "type" => "string",
          "description" => "Short summary of the change (shown in history)."
        },
        "ai_note" => %{
          "type" => "string",
          "description" => "Optional longer explanation visible in the article timeline."
        }
      },
      "required" => ["slug", "content"]
    }
  end

  @impl true
  def execute(%{"slug" => slug} = params) do
    payload =
      params
      |> Map.put("author", "claude")
      |> attach_repo_context()

    result =
      case ApiClient.get("/api/articles/" <> slug) do
        {:ok, %{"article" => _}} ->
          ApiClient.put("/api/articles/" <> slug, payload)

        {:error, {:http_error, 404, _}} ->
          ApiClient.post("/api/articles", payload)

        {:error, reason} ->
          {:error, reason}
      end

    case result do
      {:ok, %{"article" => a}} ->
        url = ApiClient.base_url() <> "/articles/" <> a["slug"]

        repo_note =
          case payload["repository"] do
            %{"name" => name} -> " · attached to #{name}"
            _ -> ""
          end

        {:ok,
         "Saved '#{a["title"]}' (slug: #{a["slug"]})#{repo_note}. View it at #{url}"}

      {:error, {:http_error, 403, %{"error" => "repository_not_linked"} = body}} ->
        {:error,
         """
         Lore is not connected to '#{body["repository"]}'. Tell the user:

           "I tried to save this article to Lore, but '#{body["repository"]}' isn't
            connected yet. Open #{body["connect_url"]} to link it,
            then I'll retry."

         Do not retry automatically — the user must explicitly connect the repo first.
         """}

      {:error, reason} ->
        {:error, "Write failed: #{inspect(reason)}"}
    end
  end

  defp attach_repo_context(payload) do
    case Git.repo_context() do
      {:ok, ctx} ->
        Map.put(payload, "repository", %{
          "name" => ctx.full_name,
          "remote_url" => ctx.remote_url,
          "branch" => ctx.branch
        })

      {:error, _} ->
        payload
    end
  end

  def execute(_), do: {:error, "Missing required parameters: slug, content"}
end
