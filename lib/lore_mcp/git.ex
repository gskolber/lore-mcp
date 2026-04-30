defmodule LoreMcp.Git do
  @moduledoc """
  Local git inspection. Used to identify which repo + branch + commit
  the validator/user is currently working in, and to fetch per-file
  commit hashes for `lore.link_files`.

  Honors `CLAUDE_PROJECT_DIR` (set by Claude Code) before falling back
  to the OS cwd. All commands run with `stderr_to_stdout` so failures
  don't pollute the JSON-RPC stdout stream.
  """

  @doc """
  Returns the working directory the validator should treat as the project root.
  Priority: CLAUDE_PROJECT_DIR env → toplevel of git repo containing cwd → cwd.
  """
  def project_dir do
    case System.get_env("CLAUDE_PROJECT_DIR") do
      dir when is_binary(dir) and dir != "" ->
        dir

      _ ->
        case run("git rev-parse --show-toplevel") do
          {:ok, top} -> top
          _ -> File.cwd!()
        end
    end
  end

  @doc """
  Best-effort context for the current repo. Returns:

      {:ok, %{
        full_name: "owner/repo",
        owner: "owner",
        repo: "repo",
        remote_url: "https://github.com/owner/repo",
        branch: "main",
        head: "<sha>"
      }}

  or `{:error, reason}` if not a git repo or remote can't be parsed.
  """
  def repo_context(cwd \\ project_dir()) do
    with {:ok, remote} <- run("git remote get-url origin", cwd),
         {:ok, {owner, repo}} <- parse_remote(remote),
         {:ok, branch} <- run("git rev-parse --abbrev-ref HEAD", cwd),
         {:ok, head} <- run("git rev-parse HEAD", cwd) do
      {:ok,
       %{
         full_name: "#{owner}/#{repo}",
         owner: owner,
         repo: repo,
         remote_url: "https://github.com/#{owner}/#{repo}",
         branch: branch,
         head: head
       }}
    end
  end

  @doc "Returns the SHA of the most recent commit that touched `path`."
  def file_commit(path, cwd \\ project_dir()) do
    run("git log -1 --format=%H -- " <> shell_quote(path), cwd)
  end

  @doc "True if cwd is inside a git working tree."
  def repo?(cwd \\ project_dir()) do
    case run("git rev-parse --is-inside-work-tree", cwd) do
      {:ok, "true"} -> true
      _ -> false
    end
  end

  @doc """
  Returns a github.com URL pointing to a file at a specific commit, or
  `nil` if the remote isn't a GitHub remote.
  """
  def github_blob_url(remote_url, commit, path)
      when is_binary(remote_url) and is_binary(commit) and is_binary(path) do
    case parse_remote(remote_url) do
      {:ok, {owner, repo}} -> "https://github.com/#{owner}/#{repo}/blob/#{commit}/#{path}"
      _ -> nil
    end
  end

  def github_blob_url(_, _, _), do: nil

  # === Internals ===

  defp run(cmd, cwd \\ nil) do
    opts = [stderr_to_stdout: true]
    opts = if cwd, do: Keyword.put(opts, :cd, cwd), else: opts

    case System.cmd("sh", ["-c", cmd], opts) do
      {out, 0} -> {:ok, String.trim(out)}
      {_out, _} -> {:error, :git_failed}
    end
  rescue
    _ -> {:error, :git_unavailable}
  end

  # Parse SSH and HTTPS GitHub remotes:
  #   git@github.com:owner/repo.git
  #   https://github.com/owner/repo.git
  #   https://github.com/owner/repo
  defp parse_remote(url) when is_binary(url) do
    cleaned = String.trim(url)

    case Regex.run(~r/github\.com[:\/]([^\/]+)\/(.+?)(?:\.git)?\/?$/, cleaned) do
      [_, owner, repo] -> {:ok, {owner, repo}}
      _ -> {:error, :unsupported_remote}
    end
  end

  defp parse_remote(_), do: {:error, :no_remote}

  defp shell_quote(s), do: "'" <> String.replace(s, "'", ~S(\')) <> "'"
end
