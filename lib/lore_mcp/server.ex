defmodule LoreMcp.Server do
  @moduledoc "Lore — AI-native engineering wiki, exposed as an MCP server."

  def name, do: "lore"
  def version, do: "0.5.0"

  def tools do
    [
      LoreMcp.Tools.Search,
      LoreMcp.Tools.Read,
      LoreMcp.Tools.Write,
      LoreMcp.Tools.LinkFiles,
      LoreMcp.Tools.Validate,
      LoreMcp.Tools.DetectRepo
    ]
  end

  @doc """
  Resources are read-only assets the server exposes (e.g. skill personas).
  Each entry is `{uri, name, description, mime_type, content_fn/0}`.
  """
  def resources do
    [
      %{
        uri: "lore://skills/validator.md",
        name: "Lore Validator skill",
        description:
          "Persona for the background validator sub-agent. Compares a code diff against the Lore wiki and files findings via lore.validate.",
        mime_type: "text/markdown",
        content: &LoreMcp.Resources.validator_skill/0
      }
    ]
  end
end
