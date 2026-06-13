# Drop VS Code's host-reaching channels from interactive shells, so they aren't
# inherited by agents/processes started from a terminal. A devcontainer's
# `remoteEnv` blanks these for the processes VS Code spawns, but VS Code RE-INJECTS
# some of them (VSCODE_GIT_IPC_HANDLE / VSCODE_IPC_HOOK_CLI / BROWSER) into
# integrated terminals on top of remoteEnv — this is what cleans them there.
#
# Each variable is scrubbed UNLESS its per-variable toggle SCRUB_<VAR>_ENABLED is
# set to a false-y value (false/0/no/off). The default is to scrub (most secure).
# Set toggles via the container environment — compose `environment:` or
# devcontainer `containerEnv` — so they're present in every shell. They take
# effect at the next shell init; no rebuild needed. Example: to keep the forwarded
# SSH agent (e.g. hardware-key / FIDO usage), set SCRUB_SSH_AUTH_SOCK_ENABLED=false.
#
# POSIX sh: safe whether sourced by sh (login /etc/profile) or bash (/etc/bash.bashrc).
for _scrub_var in \
  GIT_ASKPASS \
  VSCODE_GIT_ASKPASS_NODE \
  VSCODE_GIT_ASKPASS_MAIN \
  VSCODE_GIT_ASKPASS_EXTRA_ARGS \
  VSCODE_GIT_IPC_HANDLE \
  VSCODE_IPC_HOOK_CLI \
  BROWSER \
  GPG_AGENT_INFO \
  SSH_AUTH_SOCK; do
  eval "_scrub_enabled=\${SCRUB_${_scrub_var}_ENABLED:-true}"
  case "$(printf '%s' "$_scrub_enabled" | tr '[:upper:]' '[:lower:]')" in
    false | 0 | no | off) : ;; # opted out — keep this var
    *) unset "$_scrub_var" ;;
  esac
done
unset _scrub_var _scrub_enabled
