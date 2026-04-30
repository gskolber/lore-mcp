defmodule LoreMcp.Tools.Validate do
  @behaviour LoreMcp.Tool

  alias LoreMcp.ApiClient

  @impl true
  def name, do: "lore.validate"

  @impl true
  def description do
    """
    File a validation finding to the Lore inbox. Use this when you (as a
    background validator sub-agent) detect a discrepancy between code and
    docs, a knowledge gap, or undocumented architectural drift.

    Be conservative — only file findings you are at least 80% confident
    about. Silence is preferable to noise. The threshold for high-stakes
    findings (severity warn/error) should be 90%+.

    Three finding types:
    - knowledge_gap: a concept was introduced/touched but no Lore article
      covers it. Routes to PM for review.
    - contradiction: an existing article disagrees with what the code now
      does. Routes to dev — they decide whether code or doc is wrong.
    - drift: an architectural decision was made (often subtle) that the
      docs don't capture. Routes to team for an ADR/article decision.

    Keep messages short (~3 sentences). Do NOT include the proposed doc
    rewrite — that's a separate workflow.
    """
  end

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "finding_type" => %{
          "type" => "string",
          "enum" => ["knowledge_gap", "contradiction", "drift"],
          "description" => "Classification of the finding."
        },
        "severity" => %{
          "type" => "string",
          "enum" => ["info", "warn", "error"],
          "description" => "Default 'info'. Use 'warn' for contradictions, 'error' rarely (only for clear-cut bugs the doc explicitly contradicts)."
        },
        "file_path" => %{
          "type" => "string",
          "description" => "Path of the file under review (relative to repo root)."
        },
        "diff_summary" => %{
          "type" => "string",
          "description" => "Optional: 1-3 lines summarizing the relevant change."
        },
        "message" => %{
          "type" => "string",
          "description" => "The finding itself, in human prose. ~3 sentences. State the gap/contradiction directly. Do not propose a doc rewrite."
        },
        "suggested_fix" => %{
          "type" => "string",
          "description" => "For 'contradiction' only: 1 sentence indicating which side (code or doc) appears correct, and why. Omit for other finding types."
        },
        "confidence" => %{
          "type" => "number",
          "description" => "0.0–1.0. Be honest — don't inflate."
        },
        "context_keywords" => %{
          "type" => "string",
          "description" => "Comma-separated topical keywords (used for search/grouping)."
        },
        "article_slug" => %{
          "type" => "string",
          "description" => "Slug of the related article, if the finding is tied to an existing one."
        }
      },
      "required" => ["finding_type", "message", "confidence"]
    }
  end

  @impl true
  def execute(params) do
    payload = Map.put(params, "reporter", "claude")

    case ApiClient.post("/api/validations", payload) do
      {:ok, %{"validation" => v}} ->
        {:ok,
         "Filed #{v["finding_type"]} (#{round((v["confidence"] || 0) * 100)}% confidence) for #{v["file_path"] || "(no file)"}. View at #{ApiClient.base_url()}/inbox"}

      {:error, {:http_error, 422, body}} ->
        {:error, "Validation rejected: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Filing failed: #{inspect(reason)}"}
    end
  end
end
