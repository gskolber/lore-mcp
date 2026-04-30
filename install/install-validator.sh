#!/bin/bash
# Lore Validator — install script for a target project.
#
# Wires up:
#   .claude/skills/lore-validator.md  (fetched from the MCP resource)
#   .claude/hooks/lore-validate.sh    (the actual trigger script)
#   .claude/settings.local.json       (registers the Stop hook)
#
# Run from the root of the project you want to validate. Requires:
#   - LORE_TOKEN exported
#   - LORE_URL exported (defaults to http://localhost:4000)
#   - claude CLI (Claude Code) on PATH

set -euo pipefail

LORE_URL="${LORE_URL:-http://localhost:4000}"
TOKEN="${LORE_TOKEN:?LORE_TOKEN env var is required}"

if [ ! -d ".claude" ]; then
  mkdir -p .claude/{skills,hooks}
fi
mkdir -p .claude/skills .claude/hooks

# 1. Install the skill content. Two paths:
#    a) Try fetching from the running Lore HTTP server (so the skill stays
#       in sync if you update it centrally).
#    b) Fall back to the version bundled in this repo.
echo "→ Installing validator skill..."
SKILL_PATH=".claude/skills/lore-validator.md"
if curl -fsS -H "Authorization: Bearer $TOKEN" \
     "$LORE_URL/api/skills/validator.md" \
     -o "$SKILL_PATH" 2>/dev/null && [ -s "$SKILL_PATH" ]; then
  echo "  fetched from $LORE_URL"
else
  cp "$(dirname "$0")/../priv/lore-validator.md" "$SKILL_PATH" \
    || { echo "FATAL: could not find bundled skill content"; exit 1; }
  echo "  installed from bundled copy"
fi

# 2. Drop the hook script.
cat > .claude/hooks/lore-validate.sh <<'HOOK'
#!/bin/bash
# Stop-hook: fires when Claude Code finishes a task. Spawns the validator
# sub-agent fully detached from this hook's I/O so Claude Code doesn't
# wait minutes for the hook to "finish".

set -e
cd "$CLAUDE_PROJECT_DIR" 2>/dev/null || cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

DIFF=$(git diff --unified=3 HEAD 2>/dev/null || true)
[ -z "$DIFF" ] && exit 0

DIFF=$(echo "$DIFF" | head -c 4000)

LOG=".claude/lore-validator.log"
SKILL_FILE=".claude/skills/lore-validator.md"
[ ! -f "$SKILL_FILE" ] && { echo "[$(date)] skill missing" >> "$LOG"; exit 0; }

MCP_CONFIG=".claude/lore-validator-mcp.json"
PROMPT_FILE=".claude/lore-validator-prompt.txt"
DIFF_FILE=".claude/lore-validator-diff.txt"

python3 - "$MCP_CONFIG" <<'PY'
import json, pathlib, sys
out = pathlib.Path(sys.argv[1])
home = pathlib.Path.home() / ".claude.json"
if not home.exists():
    out.write_text('{"mcpServers": {}}')
    sys.exit(0)
data = json.loads(home.read_text())
lore = (data.get("mcpServers") or {}).get("lore")
out.write_text(json.dumps({"mcpServers": {"lore": lore} if lore else {}}))
PY

printf '%s' "$DIFF" > "$DIFF_FILE"
{
  echo "Validate this git diff against the Lore wiki. File at most one finding via mcp__lore__validate. Silence is preferred — only file if confidence is at or above the threshold defined in your system prompt."
  echo
  echo '```diff'
  cat "$DIFF_FILE"
  echo '```'
} > "$PROMPT_FILE"

DIFF_BYTES=$(wc -c < "$DIFF_FILE" | tr -d ' ')
PROJECT="$(pwd)"

# Fully detach the spawn so Claude Code's hook runner doesn't block
# waiting on inherited fds. Double-fork (`( cmd & )`) orphans the spawn
# to init; explicit redirects close the inherited fds. Portable across
# macOS (no setsid) and Linux.
(
  nohup bash -c "
    cd '$PROJECT'
    echo \"[\$(date)] firing validator (diff $DIFF_BYTES bytes)\" >> '$LOG'
    SKILL=\$(cat '$SKILL_FILE')
    PROMPT=\$(cat '$PROMPT_FILE')
    claude \
      --append-system-prompt \"\$SKILL\" \
      --mcp-config '$MCP_CONFIG' \
      --strict-mcp-config \
      --print \
      \"\$PROMPT\" \
      >> '$LOG' 2>&1 || true
    echo \"[\$(date)] validator done\" >> '$LOG'
    rm -f '$MCP_CONFIG' '$PROMPT_FILE' '$DIFF_FILE'
  " < /dev/null > /dev/null 2>&1 &
)

exit 0
HOOK
chmod +x .claude/hooks/lore-validate.sh

# 3. Wire the hook in settings.local.json (preserves existing keys if present).
SETTINGS=".claude/settings.local.json"
if [ ! -f "$SETTINGS" ]; then
  echo '{}' > "$SETTINGS"
fi

python3 - "$SETTINGS" <<'PY'
import json, sys, pathlib
path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
hooks = data.setdefault("hooks", {})
stop = hooks.setdefault("Stop", [])

# Avoid duplicating the entry on re-install.
already = any(
    any(h.get("command", "").endswith("lore-validate.sh") for h in entry.get("hooks", []))
    for entry in stop
)
if not already:
    stop.append({
        "matcher": ".*",
        "hooks": [{"type": "command", "command": ".claude/hooks/lore-validate.sh"}]
    })

path.write_text(json.dumps(data, indent=2))
PY

echo ""
echo "✓ Lore Validator installed."
echo ""
echo "  Skill:    .claude/skills/lore-validator.md"
echo "  Hook:     .claude/hooks/lore-validate.sh"
echo "  Settings: .claude/settings.local.json (Stop hook added)"
echo ""
echo "Make sure these env vars are exported wherever Claude Code runs:"
echo "  export LORE_TOKEN=\"$TOKEN\""
echo "  export LORE_URL=\"$LORE_URL\""
echo ""
echo "Inbox: $LORE_URL/inbox"
