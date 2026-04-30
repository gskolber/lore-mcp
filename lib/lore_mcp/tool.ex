defmodule LoreMcp.Tool do
  @moduledoc """
  Behaviour for an MCP tool. Each implementation must provide:
  - `name/0` — string used by the LLM to invoke
  - `description/0` — short prose
  - `input_schema/0` — JSON-schema describing arguments
  - `execute/1` — runs the tool with the parsed arguments map
  """

  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback input_schema() :: map()
  @callback execute(map()) :: {:ok, String.t()} | {:error, String.t()}
end
