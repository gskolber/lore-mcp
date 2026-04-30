defmodule LoreMcp.Tools.DetectRepo do
  @behaviour LoreMcp.Tool

  alias LoreMcp.Git

  @impl true
  def name, do: "lore.detect_repo"

  @impl true
  def description do
    """
    Inspect the local git repo to identify which project the user is working in.
    Returns the GitHub owner/repo, current branch, HEAD commit, and a few
    sample file commits so you can confirm what context Lore will use when
    you call `lore.write` or `lore.link_files`.

    Call this once at the start of a task if you're not sure where you are,
    or any time you want to surface the repo to the user.
    """
  end

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "cwd" => %{
          "type" => "string",
          "description" =>
            "Optional working directory to inspect. Defaults to CLAUDE_PROJECT_DIR or the OS cwd."
        }
      }
    }
  end

  @impl true
  def execute(args) do
    cwd = args["cwd"] || Git.project_dir()

    case Git.repo_context(cwd) do
      {:ok, ctx} ->
        text = """
        Project root: #{cwd}

        Repository:  #{ctx.full_name}
        Remote:      #{ctx.remote_url}
        Branch:      #{ctx.branch}
        HEAD commit: #{ctx.head}

        When you call lore.write or lore.link_files, Lore will associate
        the article with this repository automatically. To link files,
        pass relative paths — Lore.link_files will resolve commit hashes
        from `git log` if you don't supply them.
        """

        {:ok, text}

      {:error, reason} ->
        {:error,
         "Could not detect repo at #{cwd} (#{inspect(reason)}). " <>
           "Make sure the directory is a git working tree with a GitHub remote (origin)."}
    end
  end
end
