#!/usr/bin/env bash
# Runs claude-profile against a stub claude in a throwaway HOME. Exits non-zero on the first failure.
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd -P)/bin/claude-profile"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
T="$(cd "$T" && pwd -P)"

export HOME="$T/home" CLAUDE_PROFILES_ROOT="$T/home/.claude-profiles" CLAUDE_BASE_CONFIG="$T/home/.claude"
export CLAUDE_BIN="$T/fake-claude"
# The shell functions from shell-init call claude-profile by name; resolve it to this checkout.
mkdir -p "$T/pbin" && ln -s "$SCRIPT" "$T/pbin/claude-profile"
export PATH="$T/pbin:$PATH"
unset CLAUDE_CONFIG_DIR CLAUDE_PROFILE
mkdir -p "$HOME" "$CLAUDE_BASE_CONFIG/skills" "$T/work"/{shared,a-only,b-only}

# Stub claude: auth status reports a login per config dir; anything else echoes its environment.
cat > "$CLAUDE_BIN" <<'EOF'
#!/usr/bin/env bash
if [[ "$1 $2" == "auth status" ]]; then
  n="$(basename "$(dirname "$CLAUDE_CONFIG_DIR")")"
  echo "{\"loggedIn\":true,\"email\":\"$n@example.com\",\"orgId\":\"org-$n\",\"orgName\":\"Org $n\",\"subscriptionType\":\"team\"}"
  exit 0
fi
echo "CONFIG=$CLAUDE_CONFIG_DIR ARGS=$*"
EOF
chmod +x "$CLAUDE_BIN"

echo "# Shared instructions" > "$CLAUDE_BASE_CONFIG/CLAUDE.md"
echo '{"outputStyle":"Base","theme":"dark","permissions":{"allow":["Bash(ls:*)"]},"sandbox":{"enabled":false}}' > "$CLAUDE_BASE_CONFIG/settings.json"
echo '{"theme":"dark","mcpServers":{"demo":{"command":"demo-mcp"},"mail":{"command":"mail-mcp"}}}' > "$HOME/.claude.json"
# An installed plugin that ships an MCP server.
mkdir -p "$CLAUDE_BASE_CONFIG/plugins/cache/notes" "$CLAUDE_BASE_CONFIG/plugins/cache/notes/.claude-plugin"
echo '{"mcpServers":{"notes":{"command":"notes-mcp"}}}' > "$CLAUDE_BASE_CONFIG/plugins/cache/notes/.mcp.json"
echo '{"name":"notes"}' > "$CLAUDE_BASE_CONFIG/plugins/cache/notes/.claude-plugin/plugin.json"
echo "{\"plugins\":{\"notes@market\":[{\"installPath\":\"$CLAUDE_BASE_CONFIG/plugins/cache/notes\"}]}}" > "$CLAUDE_BASE_CONFIG/plugins/installed_plugins.json"

# Repo in a-only with a worktree outside it.
git -C "$T/work/a-only" init -q -b main
git -C "$T/work/a-only" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
git -C "$T/work/a-only" worktree add -q "$T/work/a-tree" -b feature

pass=0
ok() { pass=$((pass + 1)); echo "ok $pass - $1"; }
fail() { echo "not ok - $1" >&2; [[ $# -gt 1 ]] && echo "$2" >&2; exit 1; }
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else fail "$d"; fi; }
eq() { if [[ "$3" == "$2" ]]; then ok "$1"; else fail "$1" "expected: $2"$'\n'"actual:   $3"; fi; }
jqt() { jq -e "$2" "$1" >/dev/null 2>&1; }
cp_() { "$SCRIPT" "$@"; }

A="$CLAUDE_PROFILES_ROOT/acme"; B="$CLAUDE_PROFILES_ROOT/beta"
cp_ add --client Acme --alias acme --dir "$T/work/shared" --dir "$T/work/a-only" --mcp demo </dev/null >/dev/null
cp_ add --client Beta --alias beta --email beta@example.com --dir "$T/work/shared" --dir "$T/work/b-only" --no-login </dev/null >/dev/null 2>&1

S="$A/config/settings.json"
check "login records org and locks it" jqt "$S" '.forceLoginOrgUUID == "org-acme" and .forceLoginMethod == "claudeai"'
check "login records the signed-in email when none was given" jqt "$A/profile.json" '.email == "acme@example.com"'
check "sandbox is enforced" jqt "$S" '.sandbox.enabled and .sandbox.failIfUnavailable and (.sandbox.allowUnsandboxedCommands == false)'
check "reads outside working dirs are blocked" jqt "$S" '.permissions.blockReadsOutsideWorkingDirectories'
check "worktree outside the repo is a working dir" jqt "$S" ".permissions.additionalDirectories | index(\"$T/work/a-tree\")"
check "acme blocks beta's own dir" jqt "$S" ".sandbox.filesystem.denyRead | index(\"$T/work/b-only\")"
check "acme blocks beta's profile folder" jqt "$S" ".permissions.deny | index(\"Read(/$B/**)\")"
check "acme does not block the shared dir" jqt "$S" "(.sandbox.filesystem.denyRead | index(\"$T/work/shared\")) == null"
check "beta blocks acme's worktree" jqt "$B/config/settings.json" ".sandbox.filesystem.denyRead | index(\"$T/work/a-tree\")"
check "default settings are inherited" jqt "$S" '.outputStyle == "Base" and (.permissions.allow | index("Bash(ls:*)"))'
check "default sandbox=false does not win" jqt "$S" '.sandbox.enabled == true'
mkdir -p "$CLAUDE_BASE_CONFIG/memory"; echo "personal note" > "$CLAUDE_BASE_CONFIG/memory/MEMORY.md"
ln -sfn "$CLAUDE_BASE_CONFIG/memory" "$A/config/memory"   # as left by an older version
cp_ add-dir acme "$T/work/a-only" >/dev/null 2>&1
check "global memory is the profile's own folder, not a link" bash -c "[[ -d '$A/config/memory' && ! -L '$A/config/memory' ]]"
check "global memory starts without the personal notes" bash -c "[[ ! -e '$A/config/memory/MEMORY.md' ]]"
check "agent memory is the profile's own folder" bash -c "[[ -d '$B/config/agent-memory' && ! -L '$B/config/agent-memory' ]]"
check "the profile's own memory is a working dir" jqt "$S" ".permissions.additionalDirectories | index(\"$A/config/memory\")"
check "the personal memory folder is not a working dir" jqt "$S" "(.permissions.additionalDirectories | index(\"$CLAUDE_BASE_CONFIG/memory\")) == null"
check "CLAUDE.md is linked from the default config" test "$(readlink "$A/config/CLAUDE.md")" = "$CLAUDE_BASE_CONFIG/CLAUDE.md"
check "an allowed user MCP server is copied" jqt "$A/config/.claude.json" '.mcpServers.demo.command == "demo-mcp"'
check "other user MCP servers are not copied" jqt "$A/config/.claude.json" '.mcpServers.mail == null'
check "other user MCP servers are denied" jqt "$S" '.deniedMcpServers | index({"serverName":"mail"})'
check "plugin MCP servers are denied by default" jqt "$S" '.deniedMcpServers | index({"serverName":"plugin:notes:notes"})'
check "an allowed MCP server is not denied" jqt "$S" '(.deniedMcpServers | index({"serverName":"demo"})) == null'
check "a profile with no allow list gets no user MCP servers" jqt "$B/config/.claude.json" '(.mcpServers | length) == 0'
cp_ mcp acme allow plugin:notes:notes >/dev/null 2>&1
check "mcp allow lifts the plugin deny" jqt "$S" '(.deniedMcpServers | index({"serverName":"plugin:notes:notes"})) == null'
eq "mcp lists status" "allowed  demo|blocked  mail|allowed  plugin:notes:notes" "$(cp_ mcp acme | paste -sd'|' -)"
cp_ mcp acme deny plugin:notes:notes >/dev/null 2>&1
check "mcp deny restores the deny" jqt "$S" '.deniedMcpServers | index({"serverName":"plugin:notes:notes"})'
slug="${T//[^A-Za-z0-9]/-}-work-a-only"
check "repo memory is linked to the default config" test "$(readlink "$A/config/projects/$slug/memory")" = "$CLAUDE_BASE_CONFIG/projects/$slug/memory"

echo '{"outputStyle":"Override","sandbox":{"enabled":false}}' > "$A/settings.override.json"
cp_ add-dir acme "$T/work/a-only" >/dev/null 2>&1
check "override file wins over default settings" jqt "$S" '.outputStyle == "Override"'
check "override file cannot disable the sandbox" jqt "$S" '.sandbox.enabled == true'

out="$(cd "$T/work/a-only" && cp_ run </dev/null 2>/dev/null)"
eq "run picks the profile from the cwd" "CONFIG=$A/config ARGS=--settings $S" "$out"
out="$(cd "$T/work/a-tree" && cp_ match)"
eq "match covers a worktree outside the repo" "acme" "$out"
out="$(cd "$T/work/shared" && cp_ match | tr '\n' ' ')"
eq "match lists every profile sharing a dir" "acme beta " "$out"
check "match exits 1 outside every profile" bash -c "cd '$T' && ! '$SCRIPT' match"
check "run without alias refuses a shared dir with no tty" bash -c "cd '$T/work/shared' && ! '$SCRIPT' run </dev/null"
out="$(cd "$T/work/shared" && cp_ run beta -- -p hi </dev/null 2>/dev/null)"
eq "run ALIAS passes claude args" "CONFIG=$B/config ARGS=--settings $B/config/settings.json -p hi" "$out"
check "run refuses a dir outside the profile" bash -c "cd '$T/work/b-only' && ! '$SCRIPT' run acme </dev/null"

git -C "$T/work/a-only" worktree add -q "$T/work/a-tree2" -b feature2
out="$(cd "$T/work/a-tree2" && cp_ match)"
eq "a new worktree is picked up without re-adding" "acme" "$out"

init="$(cp_ shell-init)"
out="$(cd "$T/work/a-only" && bash -c "$init"$'\n'"claude --version" 2>/dev/null </dev/null)"
eq "shell claude() routes into the profile" "CONFIG=$A/config ARGS=--settings $S --version" "$out"
mkdir -p "$T/bin"; printf '#!/bin/sh\necho plain\n' > "$T/bin/claude"; chmod +x "$T/bin/claude"
out="$(cd "$T" && PATH="$T/bin:$PATH" bash -c "$init"$'\n'"claude" 2>/dev/null)"
eq "shell claude() is plain outside profiles" "plain" "$out"
out="$(cd "$T/work/a-only" && CLAUDE_PROFILE=none PATH="$T/bin:$PATH" bash -c "$init"$'\n'"claude" 2>/dev/null)"
eq "CLAUDE_PROFILE=none skips profiles" "plain" "$out"

cp_ remove beta >/dev/null 2>&1
check "remove keeps the profile files" bash -c "ls -d '$CLAUDE_PROFILES_ROOT'/.removed/beta-*"
check "remove unblocks the removed profile's dirs" jqt "$S" "(.sandbox.filesystem.denyRead | index(\"$T/work/b-only\")) == null"

echo "all $pass tests passed"
