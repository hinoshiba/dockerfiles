"""Isolated native-CLI contract tests; never install into the developer's HOME."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "dockerfiles/claude-codex/setup_ecc.sh"
PLUGIN = "ecc@dockerfiles-ecc"
REVISION = "c05b2d6614f62f6db0047669aa4eefb223d478f9"
FAKE_CLAUDE = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

root = Path(os.environ["ECC_TEST_DIR"])
args = sys.argv[1:]
with (root / "calls.jsonl").open("a") as stream:
    stream.write(json.dumps(args) + "\n")
if os.environ.get("ECC_FAIL") == " ".join(args[:3]):
    sys.exit(23)
state_file = root / "state.json"
state = json.loads(state_file.read_text())
config = Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude")
settings_file = config / "settings.json"
settings = json.loads(settings_file.read_text()) if settings_file.exists() else {}
if args == ["plugin", "list", "--json"]:
    print(json.dumps(state["plugins"]))
elif args == ["plugin", "marketplace", "list", "--json"]:
    print(json.dumps(state["marketplaces"]))
elif args[:3] == ["plugin", "marketplace", "add"]:
    manifest = json.loads((Path(args[3]) / ".claude-plugin/marketplace.json").read_text())
    state["marketplaces"].append({"name": manifest["name"], "source": "directory", "path": args[3]})
elif args[:2] == ["plugin", "install"]:
    state["plugins"].append({"id": args[2], "scope": "user", "enabled": True})
    settings.setdefault("enabledPlugins", {})[args[2]] = True
    if "--config" in args:
        assert args[args.index("--config") + 1] == "hooks_enabled=false"
        settings.setdefault("pluginConfigs", {}).setdefault(args[2], {}).setdefault("options", {})["hooks_enabled"] = False
elif args[:2] == ["plugin", "configure"]:
    values = json.load(sys.stdin)
    assert values == {"hooks_enabled": "false"}
    settings.setdefault("pluginConfigs", {}).setdefault(args[2], {}).setdefault("options", {})["hooks_enabled"] = False
elif args[:3] == ["plugin", "marketplace", "update"] or args[:2] == ["plugin", "update"]:
    pass
else:
    raise AssertionError(args)
config.mkdir(parents=True, exist_ok=True)
settings_file.write_text(json.dumps(settings))
state_file.write_text(json.dumps(state))
'''


class EccBootstrapTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ecc test ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "home with spaces"
        self.home.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        fake = self.bin / "claude"
        fake.write_text(FAKE_CLAUDE)
        fake.chmod(0o755)
        self.config = self.home / ".claude"
        self.config.mkdir()
        self.marker = self.config / "dockerfiles-ecc/bootstrapped"
        self.state = self.root / "state.json"
        self.state.write_text(json.dumps({"plugins": [], "marketplaces": []}))
        self.env = dict(os.environ, HOME=str(self.home), PATH=str(self.bin) + ":" + os.environ["PATH"],
                        ECC_TEST_DIR=str(self.root))
        for key in ("SKILLS_BOOTSTRAP", "SKILLS_REFRESH", "ECC_BOOTSTRAP", "CLAUDE_CONFIG_DIR"):
            self.env.pop(key, None)

    def run_script(self, **environment):
        return subprocess.run(["bash", str(SCRIPT)], env=dict(self.env, **environment),
                              capture_output=True, text=True, timeout=15)

    def calls(self):
        path = self.root / "calls.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def save_settings(self, settings):
        (self.config / "settings.json").write_text(json.dumps(settings))

    def settings(self):
        return json.loads((self.config / "settings.json").read_text())

    def test_install_pins_plugin_source_and_defaults_hooks_off(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((self.config / "dockerfiles-ecc/marketplace/.claude-plugin/marketplace.json").read_text())
        self.assertEqual(manifest["plugins"][0]["source"], {
            "source": "github", "repo": "affaan-m/ECC", "ref": "v2.2.3", "sha": REVISION})
        self.assertIn(["plugin", "install", PLUGIN, "--scope", "user", "--config", "hooks_enabled=false"], self.calls())
        self.assertFalse(self.settings()["pluginConfigs"][PLUGIN]["options"]["hooks_enabled"])
        self.assertIn(REVISION, self.marker.read_text())

    def test_success_is_cached_without_network_or_cli(self):
        self.assertEqual(self.run_script().returncode, 0)
        before = self.calls()
        self.assertEqual(self.run_script().returncode, 0)
        self.assertEqual(self.calls(), before)

    def test_global_and_ecc_opt_out_do_not_touch_configuration(self):
        for key in ("SKILLS_BOOTSTRAP", "ECC_BOOTSTRAP"):
            for value in ("0", "false", "FALSE", "no", "off"):
                self.assertEqual(self.run_script(**{key: value}).returncode, 0)
        self.assertEqual(self.calls(), [])
        self.assertFalse(self.marker.exists())

    def test_preserves_explicit_hook_options_and_unrelated_settings(self):
        settings = {"permissions": {"deny": ["Bash(rm:*)"]}, "env": {"EXAMPLE": "value"},
                    "pluginConfigs": {PLUGIN: {"options": {"hooks_enabled": True, "hook_profile": "minimal"}}}}
        self.save_settings(settings)
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        for key, value in settings.items():
            self.assertEqual(self.settings()[key], value)
        self.assertIn(["plugin", "install", PLUGIN, "--scope", "user"], self.calls())

    def test_explicit_disabled_choice_is_kept(self):
        settings = {"enabledPlugins": {PLUGIN: False}}
        self.save_settings(settings)
        self.assertEqual(self.run_script().returncode, 0)
        self.assertEqual(self.settings(), settings)
        self.assertFalse(self.marker.exists())
        self.assertEqual(self.calls(), [["plugin", "list", "--json"]])

    def test_manual_upstream_install_is_not_duplicated_or_updated(self):
        self.state.write_text(json.dumps({"plugins": [{"id": "ecc@ecc", "scope": "user", "enabled": False}], "marketplaces": []}))
        self.assertEqual(self.run_script(SKILLS_REFRESH="1").returncode, 0)
        self.assertEqual(self.calls(), [["plugin", "list", "--json"]])

    def test_install_failure_is_propagated_and_retried(self):
        failed = self.run_script(ECC_FAIL="plugin install " + PLUGIN)
        self.assertNotEqual(failed.returncode, 0)
        self.assertFalse(self.marker.exists())
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.marker.exists())

    def test_marketplace_failure_does_not_attempt_install(self):
        self.assertNotEqual(self.run_script(ECC_FAIL="plugin marketplace add").returncode, 0)
        self.assertFalse(any(call[:2] == ["plugin", "install"] for call in self.calls()))
        self.assertFalse(self.marker.exists())

    def test_refresh_keeps_pin_and_retries_after_failure(self):
        self.assertEqual(self.run_script().returncode, 0)
        result = self.run_script(SKILLS_REFRESH="1", ECC_FAIL="plugin update " + PLUGIN)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.marker.exists())
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.marker.exists())
        self.assertEqual(sum(call[:2] == ["plugin", "install"] for call in self.calls()), 1)

    def test_existing_disabled_install_stays_disabled_during_refresh(self):
        self.assertEqual(self.run_script().returncode, 0)
        settings = self.settings()
        settings["enabledPlugins"][PLUGIN] = False
        self.save_settings(settings)
        self.assertEqual(self.run_script(SKILLS_REFRESH="1").returncode, 0)
        self.assertFalse(self.settings()["enabledPlugins"][PLUGIN])
        self.assertFalse(any(call[:2] == ["plugin", "enable"] for call in self.calls()))

    def test_interrupted_install_sets_missing_hook_option_before_update(self):
        self.state.write_text(json.dumps({"plugins": [{"id": PLUGIN, "scope": "user"}], "marketplaces": []}))
        self.assertEqual(self.run_script().returncode, 0)
        configure = ["plugin", "configure", PLUGIN, "--values-stdin"]
        update = ["plugin", "update", PLUGIN, "--scope", "user"]
        self.assertLess(self.calls().index(configure), self.calls().index(update))
        self.assertFalse(self.settings()["pluginConfigs"][PLUGIN]["options"]["hooks_enabled"])

    def test_foreign_marketplace_with_same_name_is_not_overwritten(self):
        self.state.write_text(json.dumps({"plugins": [], "marketplaces": [{"name": "dockerfiles-ecc", "source": "github", "repo": "someone/other"}]}))
        self.assertNotEqual(self.run_script().returncode, 0)
        self.assertFalse(self.marker.exists())
        self.assertFalse((self.config / "dockerfiles-ecc/marketplace").exists())

    def test_invalid_existing_settings_are_not_replaced(self):
        (self.config / "settings.json").write_text("not json")
        self.assertNotEqual(self.run_script().returncode, 0)
        self.assertEqual((self.config / "settings.json").read_text(), "not json")
        self.assertFalse(self.marker.exists())

    def test_config_directory_override(self):
        alternate = self.root / "alternate config"
        result = self.run_script(CLAUDE_CONFIG_DIR=str(alternate))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((alternate / "dockerfiles-ecc/bootstrapped").exists())
        self.assertFalse(self.marker.exists())


if __name__ == "__main__":
    unittest.main()
