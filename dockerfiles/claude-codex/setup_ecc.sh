#!/bin/bash
# Native Claude plugin bootstrap. The caller may warn and continue on failure.
set -eu

case "${SKILLS_BOOTSTRAP:-1}" in 0|no|NO|false|FALSE|off|OFF) exit 0 ;; esac
case "${ECC_BOOTSTRAP:-1}" in 0|no|NO|false|FALSE|off|OFF) exit 0 ;; esac
export PATH="${HOME}/.local/bin:${PATH}"

exec python3 - <<'PY'
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


# v2.2.3 was released on 2026-10-01, beyond the image's 14-day cooldown.
# Review the executable hooks again before changing this immutable source.
REVISION = "c05b2d6614f62f6db0047669aa4eefb223d478f9"
VERSION = "2.2.3"
MARKETPLACE = "dockerfiles-ecc"
PLUGIN = "ecc@" + MARKETPLACE
EXISTING_IDS = {"ecc@ecc", "everything-claude-code@everything-claude-code"}
STAMP = "v1:" + REVISION
CONFIG = Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude")
STATE = CONFIG / "dockerfiles-ecc"
MARKER = STATE / "bootstrapped"
REFRESH = os.environ.get("SKILLS_REFRESH", "0").lower() in {"1", "yes", "true", "on"}


def log(message):
    print("[skills:ecc] " + message, file=sys.stderr)


def atomic_write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".bootstrap-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(content)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def claude(*args, capture=False, values=None):
    # Management commands must not prompt or run ECC lifecycle automation.
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0", ECC_HOOKS_ENABLED="false")
    result = subprocess.run(
        ["claude", "plugin", *args],
        input=json.dumps(values) if values is not None else None,
        stdin=subprocess.DEVNULL if values is None else None,
        stdout=subprocess.PIPE if capture else None,
        text=True, env=env, timeout=180, check=True,
    )
    if capture:
        return json.loads(result.stdout)


def main():
    if not REFRESH and MARKER.exists() and MARKER.read_text().strip() == STAMP:
        return
    # A failed explicit refresh must be retried on the next ordinary startup.
    if MARKER.exists():
        MARKER.unlink()
    if shutil.which("claude") is None:
        raise RuntimeError("claude is unavailable; ECC will be retried next startup")

    settings_path = CONFIG / "settings.json"
    settings = json.loads(settings_path.read_text()) if settings_path.exists() else {}
    if not isinstance(settings, dict):
        raise RuntimeError("Claude settings must be a JSON object")
    plugins = claude("list", "--json", capture=True)
    if not isinstance(plugins, list):
        raise RuntimeError("unexpected Claude plugin list format")
    if any(plugin.get("id") in EXISTING_IDS for plugin in plugins):
        log("keeping the existing ECC installation and its settings")
        return
    installed = any(plugin.get("id") == PLUGIN and plugin.get("scope") == "user"
                    for plugin in plugins)
    enabled = settings.get("enabledPlugins", {}).get(PLUGIN)
    if not installed and enabled is False:
        log("keeping the explicitly disabled ECC plugin")
        return
    options = settings.get("pluginConfigs", {}).get(PLUGIN, {}).get("options", {})
    hooks_configured = "hooks_enabled" in options

    catalog = STATE / "marketplace"
    marketplaces = claude("marketplace", "list", "--json", capture=True)
    if not isinstance(marketplaces, list):
        raise RuntimeError("unexpected Claude marketplace list format")
    existing = next((item for item in marketplaces if item.get("name") == MARKETPLACE), None)
    if existing is not None and (
        existing.get("source") != "directory"
        or Path(existing.get("path", "")).resolve() != catalog.resolve()
    ):
        raise RuntimeError("dockerfiles-ecc already names another marketplace; leaving it unchanged")
    manifest = {
        "name": MARKETPLACE,
        "owner": {"name": "hinoshiba/dockerfiles"},
        "plugins": [{
            "name": "ecc",
            "description": "Everything Claude Code, pinned by hinoshiba/dockerfiles",
            "source": {"source": "github", "repo": "affaan-m/ECC",
                       "ref": "v" + VERSION, "sha": REVISION},
        }],
    }
    atomic_write(catalog / ".claude-plugin" / "marketplace.json",
                 json.dumps(manifest, indent=2) + "\n")
    if existing is None:
        claude("marketplace", "add", str(catalog), "--scope", "user")
    else:
        claude("marketplace", "update", MARKETPLACE)

    if installed:
        # The namespace belongs to this bootstrap; recover an interrupted first
        # install without replacing any explicitly configured hook preference.
        if not hooks_configured:
            claude("configure", PLUGIN, "--values-stdin", values={"hooks_enabled": "false"})
        claude("update", PLUGIN, "--scope", "user")
    else:
        args = ["install", PLUGIN, "--scope", "user"]
        if not hooks_configured:
            args += ["--config", "hooks_enabled=false"]
        claude(*args)
    atomic_write(MARKER, STAMP + "\n")
    log("ECC " + VERSION + " installed; existing hook preferences preserved (new installs default to hooks off)")


try:
    main()
except (OSError, ValueError, TypeError, AttributeError, RuntimeError, subprocess.SubprocessError) as error:
    log("failed: " + str(error))
    sys.exit(1)
PY
