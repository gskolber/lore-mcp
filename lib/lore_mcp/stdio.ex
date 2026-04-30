defmodule LoreMcp.Stdio do
  @moduledoc """
  Minimal MCP stdio transport. Reads newline-delimited JSON-RPC 2.0 from
  stdin, dispatches `initialize`, `tools/list`, and `tools/call`, writes
  responses to stdout. All logging must be on stderr.
  """
  use GenServer
  require Logger

  @protocol_version "2025-06-18"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    server = Keyword.fetch!(opts, :server)
    me = self()

    spawn_link(fn -> read_loop(me) end)

    {:ok, %{server: server, initialized: false}}
  end

  defp read_loop(parent) do
    case IO.read(:stdio, :line) do
      :eof ->
        send(parent, :stdin_closed)

      {:error, _} = err ->
        send(parent, {:stdin_error, err})

      "" ->
        read_loop(parent)

      line when is_binary(line) ->
        line = String.trim(line)

        if line != "" do
          send(parent, {:line, line})
        end

        read_loop(parent)
    end
  end

  @impl true
  def handle_info({:line, line}, state) do
    case Jason.decode(line) do
      {:ok, msg} ->
        handle_message(msg, state)

      {:error, reason} ->
        Logger.error("JSON decode failed: #{inspect(reason)} for line: #{line}")
        {:noreply, state}
    end
  end

  def handle_info(:stdin_closed, state) do
    Logger.info("stdin closed; shutting down")
    System.halt(0)
    {:noreply, state}
  end

  def handle_info({:stdin_error, err}, state) do
    Logger.error("stdin error: #{inspect(err)}")
    System.halt(1)
    {:noreply, state}
  end

  defp handle_message(%{"method" => "initialize", "id" => id}, state) do
    server = state.server

    capabilities =
      %{"tools" => %{"listChanged" => false}}
      |> maybe_add_resources(server)

    info = %{
      "protocolVersion" => @protocol_version,
      "serverInfo" => %{"name" => server.name(), "version" => server.version()},
      "capabilities" => capabilities
    }

    send_response(id, info)
    {:noreply, state}
  end

  defp maybe_add_resources(caps, server) do
    Code.ensure_loaded(server)

    if function_exported?(server, :resources, 0) and server.resources() != [] do
      Map.put(caps, "resources", %{"listChanged" => false, "subscribe" => false})
    else
      caps
    end
  end

  defp handle_message(%{"method" => "notifications/initialized"}, state) do
    {:noreply, %{state | initialized: true}}
  end

  defp handle_message(%{"method" => "tools/list", "id" => id}, state) do
    tools =
      state.server.tools()
      |> Enum.map(fn module ->
        %{
          "name" => module.name(),
          "description" => module.description(),
          "inputSchema" => module.input_schema()
        }
      end)

    send_response(id, %{"tools" => tools})
    {:noreply, state}
  end

  defp handle_message(%{"method" => "resources/list", "id" => id}, state) do
    resources =
      state.server.resources()
      |> Enum.map(fn r ->
        %{
          "uri" => r.uri,
          "name" => r.name,
          "description" => r.description,
          "mimeType" => r.mime_type
        }
      end)

    send_response(id, %{"resources" => resources})
    {:noreply, state}
  end

  defp handle_message(%{"method" => "resources/read", "id" => id, "params" => %{"uri" => uri}}, state) do
    case Enum.find(state.server.resources(), &(&1.uri == uri)) do
      nil ->
        send_error(id, -32_002, "Resource not found: #{uri}")

      r ->
        send_response(id, %{
          "contents" => [
            %{
              "uri" => r.uri,
              "mimeType" => r.mime_type,
              "text" => r.content.()
            }
          ]
        })
    end

    {:noreply, state}
  end

  defp handle_message(%{"method" => "tools/call", "id" => id, "params" => params}, state) do
    tool_name = params["name"]
    args = params["arguments"] || %{}

    tool =
      Enum.find(state.server.tools(), fn m ->
        m.name() == tool_name
      end)

    if tool do
      result =
        try do
          tool.execute(args)
        rescue
          e ->
            Logger.error("Tool #{tool_name} crashed: #{Exception.format(:error, e, __STACKTRACE__)}")
            {:error, "Tool crashed: #{Exception.message(e)}"}
        end

      case result do
        {:ok, text} when is_binary(text) ->
          send_response(id, %{
            "content" => [%{"type" => "text", "text" => text}],
            "isError" => false
          })

        {:error, message} when is_binary(message) ->
          send_response(id, %{
            "content" => [%{"type" => "text", "text" => message}],
            "isError" => true
          })
      end
    else
      send_error(id, -32_601, "Tool not found: #{tool_name}")
    end

    {:noreply, state}
  end

  defp handle_message(%{"method" => method, "id" => id}, state) do
    Logger.warning("Unknown method: #{method}")
    send_error(id, -32_601, "Method not found: #{method}")
    {:noreply, state}
  end

  defp handle_message(%{"method" => method}, state) do
    Logger.debug("Notification ignored: #{method}")
    {:noreply, state}
  end

  defp handle_message(other, state) do
    Logger.warning("Unhandled MCP message: #{inspect(other)}")
    {:noreply, state}
  end

  defp send_response(id, result) do
    IO.puts(Jason.encode!(%{"jsonrpc" => "2.0", "id" => id, "result" => result}))
  end

  defp send_error(id, code, message) do
    IO.puts(
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "id" => id,
        "error" => %{"code" => code, "message" => message}
      })
    )
  end
end
