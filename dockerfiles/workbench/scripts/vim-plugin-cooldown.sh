#!/bin/bash
# Security "cooldown" for vim plugins.
#
# NeoBundle clones each plugin at its latest commit. To avoid pulling in a
# freshly pushed -- and possibly compromised -- plugin commit, this script
# rolls every installed plugin back to the newest commit that is at least
# COOLDOWN_DAYS (default 14) days old.
#
# Usage: vim-plugin-cooldown [BUNDLE_DIR]
#   BUNDLE_DIR defaults to ~/.vim/bundle
set -eu

COOLDOWN_DAYS="${COOLDOWN_DAYS:-14}"
BUNDLE_DIR="${1:-${HOME}/.vim/bundle}"

if [ ! -d "${BUNDLE_DIR}" ]; then
	echo "[vim-plugin-cooldown] no bundle dir at ${BUNDLE_DIR}; nothing to do" >&2
	exit 0
fi

for dir in "${BUNDLE_DIR}"/*/; do
	[ -d "${dir}.git" ] || continue
	name="$(basename "${dir}")"

	# A shallow clone cannot see history old enough to honour the cooldown,
	# so deepen it first (best-effort).
	if [ -f "$(git -C "${dir}" rev-parse --git-dir)/shallow" ]; then
		git -C "${dir}" fetch -q --unshallow || git -C "${dir}" fetch -q || true
	fi

	rev="$(git -C "${dir}" rev-list -1 --before="${COOLDOWN_DAYS} days ago" HEAD 2>/dev/null || true)"
	if [ -n "${rev}" ]; then
		echo "[vim-plugin-cooldown] ${name} -> ${rev}"
		git -C "${dir}" checkout -q "${rev}"
	else
		echo "[vim-plugin-cooldown] ${name}: no commit older than ${COOLDOWN_DAYS} days; leaving as-is" >&2
	fi
done
