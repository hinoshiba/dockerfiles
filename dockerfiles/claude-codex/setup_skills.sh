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

# best-effort runner: echo the command, swallow failures so a flaky network or
# an already-applied change can never break the container start.
run() {
	log "+ $*"
	"$@" </dev/null || warn "command failed (ignored): $*"
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
	run claude plugin marketplace add openai/codex-plugin-cc
	run claude plugin marketplace add anthropics/claude-plugins-official

	log "Installing standard Claude Code plugins..."
	run claude plugin install codex@openai-codex --scope user
	run claude plugin install security-guidance@claude-plugins-official --scope user

	if [ -n "${FORCE}" ]; then
		log "Refreshing Claude Code plugins..."
		run claude plugin update codex@openai-codex
		run claude plugin update security-guidance@claude-plugins-official
	fi

	: > "${sentinel}" 2>/dev/null || true
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
	run npx -y cc-plugin-codex@latest install

	: > "${sentinel}" 2>/dev/null || true
	log "Codex plugin installed; run '\$cc:setup' once inside Codex to finish wiring."
}

# Location of the baked-in, version-controlled coding-knowhow skills.
CODING_SKILLS_SRC="${CODING_SKILLS_SRC:-/opt/coding-skills}"

setup_coding_skills() {
	# Link the repo's coding-knowhow skills (Agent Skills, SKILL.md format) into
	# the places Claude Code / Codex look, so the team's know-how travels with
	# the image and stays PR-reviewable.
	[ -d "${CODING_SKILLS_SRC}" ] || {
		log "no coding skills at ${CODING_SKILLS_SRC}; skipping."
		return 0
	}

	mkdir -p "${HOME}/.claude" "${HOME}/.codex" 2>/dev/null || true
	local sentinel="${HOME}/.claude/.coding-skills.bootstrap"

	if [ -f "${sentinel}" ] && [ -z "${FORCE}" ]; then
		log "Coding skills already linked; skipping (SKILLS_REFRESH=1 to refresh)."
		return 0
	fi

	# Claude Code: personal skills live under ~/.claude/skills/<name>/SKILL.md.
	local claude_skills="${HOME}/.claude/skills"
	mkdir -p "${claude_skills}" 2>/dev/null || true

	# Codex: expose the same tree at a stable, documented path.
	run ln -sfn "${CODING_SKILLS_SRC}" "${HOME}/.codex/coding-skills"

	local linked=0 d name
	for d in "${CODING_SKILLS_SRC}"/*/; do
		[ -d "${d}" ] || continue
		name="$(basename "${d}")"
		# Skip templates / drafts / hidden entries.
		case "${name}" in
			_*|.*) continue ;;
		esac
		# Only link real skills (a directory holding a SKILL.md).
		[ -f "${d}SKILL.md" ] || continue
		run ln -sfn "${d%/}" "${claude_skills}/${name}"
		linked=$((linked + 1))
	done

	: > "${sentinel}" 2>/dev/null || true
	log "Coding skills linked: ${linked} into ${claude_skills} (and ~/.codex/coding-skills)."
}

setup_claude
setup_codex
setup_coding_skills

log "Standard skills bootstrap complete."
exit 0
