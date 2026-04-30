# Lore MCP Server

A small Elixir MCP (Model Context Protocol) server that exposes the
[Lore](https://github.com/gskolber/lore) wiki to Claude Code, Cursor, Zed,
and any other MCP-aware client. Speaks JSON-RPC 2.0 over stdio and proxies
tool calls to a running Lore Phoenix backend over HTTPS.

## What this gives Claude

| Tool              | What it does |
|-------------------|--------------|
| `lore.search`     | Full-text search across articles in your workspace |
| `lore.read`       | Read an article by slug. Surfaces a warning when linked files have changed since the last verification |
| `lore.write`      | Create or update an article. The change is recorded in the article history attributed to Claude |
| `lore.link_files` | Pin an article to repo files for freshness tracking. Auto-fills commit hashes from local `git log` |
| `lore.validate`   | File a finding (knowledge gap / contradiction / drift) to the Lore Inbox |
| `lore.detect_repo`| Inspect the local working directory and report the GitHub owner/repo, branch, HEAD |

Plus a single MCP resource:

| URI                          | What |
|------------------------------|------|
| `lore://skills/validator.md` | The persona for the background-validator sub-agent. Pulled centrally so updates to the validator behavior propagate to every install |

## Prerequisites

- Elixir 1.15+ / OTP 26+ on your machine
- A running Lore deployment (self-hosted; see [gskolber/lore](https://github.com/gskolber/lore))
- An API token from `/settings/mcp` on your Lore instance

## Install

```bash
git clone https://github.com/gskolber/lore-mcp.git
cd lore-mcp
mix deps.get
mix compile
```

That's it. `bin/lore-mcp` is a tiny shell launcher that runs `mix run --no-halt`
from the project root.

## Connect to Claude Code

```bash
claude mcp add lore -s user \
  -e LORE_TOKEN=lore_pat_... \
  -e LORE_URL=https://lore.your-company.com \
  -- "$(pwd)/bin/lore-mcp"
```

Verify with:

```bash
claude mcp list
```

You should see `lore: ... ✓ Connected`. Restart Claude Code and the tools
appear automatically in any project.

## Connect to Cursor / Zed

Same shape, different config file:

- **Cursor**: `~/.cursor/mcp.json`
- **Zed**: `~/.config/zed/settings.json` under `context_servers`

```json
{
  "mcpServers": {
    "lore": {
      "command": "/absolute/path/to/lore-mcp/bin/lore-mcp",
      "env": {
        "LORE_TOKEN": "lore_pat_...",
        "LORE_URL": "https://lore.your-company.com"
      }
    }
  }
}
```

## Try it

Once connected, ask Claude in your IDE:

> "Use Lore to look up how we handle webhook signing, then add a Common Pitfalls section based on what you learn from `lib/acme/billing/verify_signature.ex`."

The flow Claude will run:
1. `lore.detect_repo` — figures out which GitHub repo it's in
2. `lore.search` — looks up existing webhook articles
3. `lore.read` — reads the most relevant one
4. Reads `verify_signature.ex` from the local file system
5. `lore.write` — appends the new section, attributed to Claude
6. `lore.link_files` — pins the file's current commit hash for freshness tracking

## Background validator

If you also want Claude to silently audit your changes against the wiki
(without you prompting), copy the `lore-validator` skill into the project
and add a Stop hook. The skill content lives at the
`lore://skills/validator.md` resource and is also bundled offline at
`priv/lore-validator.md`.

Run from the root of the project you want to audit:

```bash
export LORE_TOKEN=lore_pat_...
export LORE_URL=https://lore.your-company.com

/path/to/lore-mcp/install/install-validator.sh
```

This drops:

- `.claude/skills/lore-validator.md` — the validator persona
- `.claude/hooks/lore-validate.sh` — Stop-hook that captures recent diff and
  spawns a background `claude` sub-agent
- `.claude/settings.local.json` — registers the Stop hook

The validator only files findings with confidence ≥ 80%. Silence is the
preferred output. See
[`priv/lore-validator.md`](priv/lore-validator.md) for the exact prompt.

## Architecture

```
┌──────────────┐  stdio JSON-RPC  ┌──────────────┐  HTTPS+Bearer  ┌──────────────┐
│ Claude Code  │ ──────────────── │  lore-mcp    │ ────────────── │  Lore        │
│ Cursor / Zed │ ◀─────────────── │  (Elixir)    │ ◀───────────── │  (Phoenix)   │
└──────────────┘                  └──────────────┘                └──────────────┘
                                       │
                                       └─ runs on the dev's machine
```

- `LoreMcp.Stdio` — minimal JSON-RPC 2.0 dispatcher (`initialize`,
  `tools/list`, `tools/call`, `resources/list`, `resources/read`)
- `LoreMcp.Tools.{Search,Read,Write,LinkFiles,Validate,DetectRepo}` — the six
  tools, implementing the `LoreMcp.Tool` behaviour
- `LoreMcp.Git` — local git inspection (`git remote get-url`, `git log`,
  `git rev-parse`) to auto-detect repo context and per-file commit hashes
- `LoreMcp.ApiClient` — Req-based HTTP wrapper around the Lore API

**Stdout discipline:** stdout is the wire for the protocol. The application
boot redirects the default Erlang/OTP logger to `:standard_error` so logs
never corrupt the JSON-RPC stream.

## Contributing

The MCP server is a thin proxy — adding a new tool is ~50 lines:

1. Create `lib/lore_mcp/tools/my_tool.ex` implementing the `LoreMcp.Tool`
   behaviour (`name/0`, `description/0`, `input_schema/0`, `execute/1`)
2. Register it in `lib/lore_mcp/server.ex` under `tools/0`
3. Test the handshake locally:

   ```bash
   LORE_TOKEN=... LORE_URL=... ./bin/lore-mcp <<EOF
   {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}
   {"jsonrpc":"2.0","method":"notifications/initialized"}
   {"jsonrpc":"2.0","id":2,"method":"tools/list"}
   EOF
   ```

The corresponding HTTP endpoint must already exist on the Lore Phoenix
backend (see [gskolber/lore](https://github.com/gskolber/lore)).

## Troubleshooting

**"no tools" / "connection failed"**

Run the launcher manually with the same env vars and pipe an `initialize`
request (see the contributing snippet above). You should get a JSON
response on stdout. Any error goes to stderr.

**`Tool execution failed: repository_not_linked`**

The repo you're in isn't connected to your Lore yet. Open
`$LORE_URL/settings/repositories` and click Connect on it.

**Article shows up but with the wrong author**

The `author` field in `lore.write` is hard-coded to `"claude"`. To attribute
to Cursor or another agent, fork or extend `LoreMcp.Tools.Write`.

## License

MIT — see [LICENSE](LICENSE).
