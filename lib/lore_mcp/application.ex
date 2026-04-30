defmodule LoreMcp.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    # Critical: stdout is reserved for MCP JSON-RPC traffic.
    # Send all logger output to stderr so we don't corrupt the protocol stream.
    :logger.update_handler_config(:default, :config, %{type: :standard_error})

    children = [
      {LoreMcp.Stdio, [server: LoreMcp.Server]}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: LoreMcp.Supervisor)
  end
end
