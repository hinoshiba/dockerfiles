#!/bin/bash
# setup_skills.sh - Bootstrap the standard Claude Code / Codex skills (plugins).
#
# Installs, idempotently and best-effort, the well-known, (semi-)official
# integration and security plugins for Claude Code and OpenAI Codex:
#
#   Claude Code:
#     - codex@openai-codex                        (github: openai/codex-plugin-cc)
#         Drive Codex from inside Claude Code: /codex:review, /codex:rescue, ...
#     - security-guidance@claude-plugins-official  (github: anthropics/claude-plugins-official)
#         Anthropic's official "review code as it is written" security plugin.
#
#   Codex:
#     - cc-plugin-codex                            (github: sendbird/cc-plugin-codex)
#         Drive Claude Code from inside Codex: $cc:review, $cc:rescue, ...
#
# It also links the repo's version-controlled coding-knowhow skills (Agent
# Skills, SKILL.md format), baked into the image at /opt/coding-skills, into the
# locations Claude Code / Codex discover. See dockerfiles/claude-codex/skills/.
#
# State is written under the host-mounted ~/.claude and ~/.codex directories,
# so it persists across container runs. Running this on every container start
# keeps the set converged for "maintenance continuity": once a plugin is
# installed the step is a fast no-op, and the weekly image rebuild keeps the
# underlying CLIs current.
#
# Controls (environment variables):
#   SKILLS_BOOTSTRAP=0   Disable this bootstrap entirely.
#   SKILLS_REFRESH=1     Force re-install / "plugin update" even if already set up.
#
# This script is best-effort: it must never abort the container start, so it
# always exits 0.

set -u

export PATH="${HOME}/.local/bin:${PATH}"

LOG_PREFIX="[skills]"
log()  { echo "${LOG_PREFIX} $*"; }
warn() { echo "${LOG_PREFIX} WARN: $*" >&2; }

case "${SKILLS_BOOTSTRAP:-1}" in
	0|no|NO|false|FALSE|off|OFF)
		log "SKILLS_BOOTSTRAP is disabled; skipping skills bootstrap."
		exit 0
		;;
esac

FORCE=""
case "${SKILLS_REFRESH:-0}" in
	1|yes|YES|true|TRUE|on|ON) FORCE="1" ;;
esac

# Preserve the command status so failures are retried on the next start.
# Callers remain best-effort and never abort the interactive container.
run() {
	log "+ $*"
	"$@" </dev/null || { warn "command failed; will retry: $*"; return 1; }
}

setup_claude() {
	command -v claude >/dev/null 2>&1 || {
		warn "claude not found on PATH; skipping Claude Code plugins."
		return 0
	}

	mkdir -p "${HOME}/.claude" 2>/dev/null || true
	local sentinel="${HOME}/.claude/.standard-skills.bootstrap"

	if [ -f "${sentinel}" ] && [ -z "${FORCE}" ]; then
		log "Claude Code plugins already bootstrapped; skipping (SKILLS_REFRESH=1 to refresh)."
		return 0
	fi

	log "Registering Claude Code plugin marketplaces..."
	run claude plugin marketplace add openai/codex-plugin-cc || true
	run claude plugin marketplace add anthropics/claude-plugins-official || true

	log "Installing standard Claude Code plugins..."
	local failed=0
	run claude plugin install codex@openai-codex --scope user || failed=1
	run claude plugin install security-guidance@claude-plugins-official --scope user || failed=1

	if [ -n "${FORCE}" ]; then
		log "Refreshing Claude Code plugins..."
		run claude plugin update codex@openai-codex || failed=1
		run claude plugin update security-guidance@claude-plugins-official || failed=1
	fi

	[ "$failed" -eq 0 ] || { rm -f "${sentinel}"; return 1; }
	: > "${sentinel}" 2>/dev/null || return 1
	log "Claude Code plugins ready (codex, security-guidance)."
}

setup_codex() {
	command -v codex >/dev/null 2>&1 || {
		warn "codex not found on PATH; skipping Codex plugins."
		return 0
	}
	command -v npx >/dev/null 2>&1 || {
		warn "npx not found on PATH; skipping Codex plugins."
		return 0
	}

	mkdir -p "${HOME}/.codex" 2>/dev/null || true
	local sentinel="${HOME}/.codex/.cc-plugin-codex.bootstrap"

	if [ -f "${sentinel}" ] && [ -z "${FORCE}" ]; then
		log "Codex plugin already bootstrapped; skipping (SKILLS_REFRESH=1 to refresh)."
		return 0
	fi

	log "Installing cc-plugin-codex (use Claude Code from inside Codex)..."
	run npx -y cc-plugin-codex@latest install || { rm -f "${sentinel}"; return 1; }

	: > "${sentinel}" 2>/dev/null || true
	log "Codex plugin installed; run '\$cc:setup' once inside Codex to finish wiring."
}

# Location of the baked-in, version-controlled coding-knowhow skills.
CODING_SKILLS_SRC="${CODING_SKILLS_SRC:-/opt/coding-skills}"

# Never replace a user's directory, file, or differently targeted symlink.
link_skill() {
	local source="$1" destination="$2"
	if [ -L "$destination" ] && [ "$(readlink "$destination")" = "$source" ]; then
		return 0
	fi
	if [ -e "$destination" ] || [ -L "$destination" ]; then
		warn "Keeping existing user skill: $destination"
		return 0
	fi
	ln -s "$source" "$destination" || return 1
}

setup_coding_skills() {
	[ -d "${CODING_SKILLS_SRC}" ] || return 0
	# Reconcile on every start: a previous image's sentinel must not hide new skills.
	local destination d name linked=0 failed=0
	for destination in "${HOME}/.agents/skills" "${HOME}/.claude/skills" "${HOME}/.codex/skills"; do
		mkdir -p "$destination" || { warn "Cannot create skill directory: $destination"; failed=1; continue; }
		for d in "${CODING_SKILLS_SRC}"/*/; do
			[ -d "$d" ] || continue
			name="$(basename "$d")"
			case "$name" in _*|.*) continue ;; esac
			[ -f "${d}SKILL.md" ] || continue
			link_skill "${d%/}" "$destination/$name" || { failed=1; continue; }
			linked=$((linked + 1))
		done
	done
	# Preserve the old documented shortcut alongside actual discovery locations.
	link_skill "$CODING_SKILLS_SRC" "${HOME}/.codex/coding-skills" || return 1
	log "Coding skill locations reconciled ($linked entries)."
	return "$failed"
}

# Local skills do not depend on the network or external plugin installation.
setup_coding_skills || warn "Some local skills could not be linked."
setup_claude || warn "Claude plugins incomplete; retrying on next start."
setup_codex || warn "Codex plugin incomplete; retrying on next start."
ecc_helper="$(dirname "${BASH_SOURCE[0]}")/setup_ecc.sh"
if [ -f "$ecc_helper" ]; then
	bash "$ecc_helper" || warn "ECC setup incomplete; retrying on next start."
fi

log "Standard skills bootstrap complete."
exit 0
