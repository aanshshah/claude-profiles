# claude-profiles

Run [Claude Code](https://code.claude.com) under several Claude accounts on one machine, with each account confined to its own directories.

Use it if you work for several clients, each with its own Claude Team (or Max/Pro) subscription, and want:

- `claude` in a client's repo to use that client's account, with no manual switching;
- a session for one client to be unable to read another client's code;
- one `CLAUDE.md`, one set of skills, plugins, hooks and MCP servers, shared by every account.

Not affiliated with or endorsed by Anthropic.

## Requirements

- macOS or Linux (Claude Code's sandbox runs on both; it uses `bubblewrap` on Linux)
- Claude Code, `bash`, `jq`, `git`

## Install

```sh
git clone https://github.com/aanshshah/claude-profiles.git
cd claude-profiles
./install.sh                      # links bin/claude-profile into ~/.local/bin
echo 'eval "$(claude-profile shell-init)"' >> ~/.zshrc
exec zsh
```

`shell-init` defines three things in your shell:

| Name | What it does |
|---|---|
| `claude` | Uses the profile that covers `$PWD`; anywhere else it runs plain `claude` |
| `ccp` | Short for `claude-profile`; with no subcommand it runs `claude-profile run` |
| `claude-<alias>` | Starts a session in that profile |

## Quick start

```sh
# One profile per account. --dir may repeat. The login opens a browser.
claude-profile add --client Acme --alias acme --email you@acme.example --dir ~/src/acme-api --dir ~/src/acme-web

# Two accounts may share a directory; `claude` there asks which one to use.
claude-profile add --client Globex --alias globex --dir ~/src/shared-lib --dir ~/src/globex
claude-profile add --client Initech --alias initech --dir ~/src/shared-lib

cd ~/src/acme-api && claude       # runs as acme
```

In a session, `/status` shows the account and organization in use.

## Commands

```
claude-profile add --client NAME --alias ALIAS [--email EMAIL] --dir PATH [--dir PATH...] [--mcp NAME...] [--no-login]
claude-profile login ALIAS        sign in (opens a browser) and lock the profile to that org
claude-profile run [ALIAS] [-- claude args...]
claude-profile match              print the profiles covering $PWD; exit 1 if none
claude-profile list
claude-profile mcp ALIAS [allow|deny NAME...]
claude-profile add-dir ALIAS PATH
claude-profile remove ALIAS       log out; files move to $CLAUDE_PROFILES_ROOT/.removed
claude-profile shell-init
claude-profile version
```

| Variable | Default | Meaning |
|---|---|---|
| `CLAUDE_PROFILES_ROOT` | `~/.claude-profiles` | where profiles are stored |
| `CLAUDE_BASE_CONFIG` | `~/.claude` | the config every profile shares |
| `CLAUDE_BIN` | `claude` | the Claude Code executable |
| `CLAUDE_PROFILE=none` | unset | makes the `claude` function skip profiles |

## How it works

Each profile is a separate `CLAUDE_CONFIG_DIR` at `~/.claude-profiles/<alias>/config`. Claude Code keys stored credentials by config directory, so each profile keeps its own login (on macOS, a separate Keychain entry).

The profile's `settings.json` is generated in three layers, last wins:

1. `~/.claude/settings.json`, your normal settings: hooks, plugins, output style, permissions
2. `~/.claude-profiles/<alias>/settings.override.json`, if present, for settings specific to one profile
3. Isolation settings, which cannot be overridden:

| Setting | Effect |
|---|---|
| `forceLoginMethod: claudeai`, `forceLoginOrgUUID` | the profile only accepts a login to the org it was first logged into |
| `permissions.additionalDirectories` | the profile's directories and their git worktrees |
| `permissions.blockReadsOutsideWorkingDirectories` | Claude's file tools cannot read outside those directories |
| `permissions.deny` `Read`/`Edit` rules | other profiles' directories, worktrees and config folders |
| `sandbox.enabled`, `failIfUnavailable`, `allowUnsandboxedCommands: false` | shell commands run sandboxed, with no fallback to running outside the sandbox |
| `sandbox.filesystem.denyRead` / `denyWrite` | other profiles' directories, enforced by the OS sandbox for shell commands |

`run` also passes the same file with `--settings`, so a repository's own `.claude/settings.json` cannot loosen it.

These are linked from `~/.claude`, so every profile uses the same files:
`CLAUDE.md`, `commands`, `skills`, `agents`, `hooks`, `output-styles`, `plugins`, `keybindings.json`, and `projects/<repo>/memory` for the profile's own repos.

Each profile has its own `memory` and `agent-memory` folders, so notes a session saves outside a repo's memory stay in that profile. Repo memory is shared by every profile that includes the repo and by plain `claude` sessions in it.

Conversation history stays per profile.

### MCP servers

Your own MCP servers often reach personal data (mail, calendar, meeting notes), so a profile gets none of them by default. Every user-level server in `~/.claude.json` and every server shipped by an installed plugin is added to the profile's `deniedMcpServers`. Allow the ones a client may use:

```sh
claude-profile mcp acme                         # allowed / blocked, per server
claude-profile mcp acme allow linear plugin:github:github
claude-profile mcp acme deny linear
claude-profile add ... --mcp linear             # at creation
```

Use names exactly as `claude mcp list` prints them. These are not affected:

- project-level servers for the profile's own repos (`.mcp.json`, or project entries in `~/.claude.json`);
- plugins and claude.ai connectors that come from the account the profile logs into.

### Shared directories and worktrees

A directory can belong to several profiles. `claude` there shows a menu; `claude-profile run ALIAS` skips it. Profiles that share a directory do not block it for each other.

Any git worktree of a repo in a profile, wherever it lives, counts as that profile's directory. The worktree list is re-read whenever its inputs change, so new worktrees need no setup. Generated settings are cached against a fingerprint of their inputs: a launch costs about 0.5 s when nothing changed and a few seconds after a change.

## Limits

- MCP servers and hooks run outside the sandbox. An allowed local MCP server, or any hook, can read any file your user can.
- The deny list covers servers known when settings are rebuilt. A server added to a project's `.mcp.json` belongs to that project and is not denied.
- A directory cannot be blocked for a profile when it contains one of that profile's own directories, for example `~/src` for one profile and `~/src/acme` for another. `add` warns when this happens.
- Web-hosted MCP servers that sign in with OAuth need signing in once per profile.
- claude.ai connectors come from the account each profile logs into.
- Changes made in a session to a profile's `settings.json` are overwritten on the next rebuild; put them in `settings.override.json` instead.

## Uninstall

```sh
claude-profile remove <alias>      # for each profile; logs out
rm ~/.local/bin/claude-profile     # and delete the shell-init line from your rc file
```

## Development

```sh
bash tests/test.sh                 # stubbed claude in a temporary HOME; never touches your config
shellcheck -s bash bin/claude-profile install.sh tests/test.sh
```

## License

MIT
