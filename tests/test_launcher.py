"""Exercise Make's public interface without starting an engine or touching user data."""

import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))
from launch import Launcher, Options


class FakeRuntime:
    engine = "apple"

    def __init__(self):
        self.runs = []

    def container_state(self, name):
        return None

    def pull(self, image):
        pass

    def run(self, args):
        self.runs.append(args)
        self.environment = os.environ.copy()
        return subprocess.CompletedProcess(args, 0)


class LauncherCLITests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="dockerfiles-launcher-")
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.home = self.base / "home with spaces"
        self.home.mkdir()
        self.work = self.home / "git" / "project with spaces"
        self.work.mkdir(parents=True)
        for relative in ("work", ".shared_cache", "Downloads", ".ssh"):
            (self.home / relative).mkdir(exist_ok=True)
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.calls_path = self.base / "calls.jsonl"
        self.make = shutil.which("make")
        self.assertIsNotNone(self.make)
        self.repo = REPO
        self.docker_socket = self.base / "docker.sock"
        sock = socket.socket(socket.AF_UNIX)
        sock.bind(str(self.docker_socket))
        self.addCleanup(sock.close)
        self.env = os.environ.copy()
        for name in list(self.env):
            if name.startswith(("DF_", "DOCKERFILES_")) or name in (
                "SSH_AUTH_SOCK", "MAKEFLAGS", "MFLAGS", "MAKEOVERRIDES",
                "DOCKER_CONTEXT", "DOCKER_TLS_VERIFY", "DOCKER_CERT_PATH",
            ):
                self.env.pop(name, None)
        self.env.update(
            HOME=str(self.home),
            PATH=f"{self.bin}{os.pathsep}{os.environ['PATH']}",
            DOCKER_HOST=f"unix://{self.docker_socket}",
            DF_TEST_CALLS=str(self.calls_path),
            DF_TEST_SOCKET=str(self.docker_socket),
            DF_TEST_STATE="",
            DF_TEST_EXIT="0",
        )
        fake = "#!" + sys.executable + "\n" + r'''
import json, os, sys
from pathlib import Path
argv = sys.argv[1:]
with open(os.environ["DF_TEST_CALLS"], "a") as stream:
    stream.write(json.dumps(argv) + "\n")
if argv[:1] == ["info"]:
    print("{}")
elif argv[:1] == ["ps"]:
    for item in json.loads(os.environ.get("DF_TEST_STATE") or "[]"):
        print(json.dumps(item))
elif argv[:2] == ["image", "inspect"]:
    if "--format" not in argv and os.environ.get("DF_TEST_IMAGE_EXISTS", "1") == "0":
        sys.exit(1)
    print(json.dumps(["/usr/local/bin/exec_user.sh"]))
elif argv[:2] == ["context", "inspect"]:
    print(json.dumps([{"Endpoints": {"docker": {"Host": "unix://" + os.environ["DF_TEST_SOCKET"]}}}]))
elif argv[:2] == ["context", "show"]:
    print("default")
elif argv[:1] == ["run"]:
    sys.exit(int(os.environ["DF_TEST_EXIT"]))
'''
        (self.bin / "docker").write_text(fake)
        (self.bin / "docker").chmod(0o755)
        # Agent discovery must never read the real user's SSH configuration.
        (self.bin / "ssh").write_text("#!" + sys.executable + "\nimport os\nprint('identityagent ' + os.environ.get('DF_TEST_IDENTITY_AGENT', 'none'))\n")
        (self.bin / "ssh").chmod(0o755)

    def invoke(self, action="start", target="workbench", ok=True, **options):
        args = [
            self.make, "--no-print-directory", "-C", str(self.repo), action,
            "engine=docker", "auto_install=n", f"target={target}",
            f"work_dir={self.work}",
        ]
        args.extend(f"{key}={value}" for key, value in options.items())
        result = subprocess.run(args, env=self.env, text=True, capture_output=True,
                                stdin=subprocess.DEVNULL, timeout=30)
        if ok:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def calls(self):
        if not self.calls_path.exists():
            return []
        return [json.loads(line) for line in self.calls_path.read_text().splitlines()]

    def run_call(self):
        matches = [call for call in self.calls() if call[:1] == ["run"]]
        self.assertEqual(len(matches), 1, self.calls())
        return matches[0]

    @staticmethod
    def envs(argv):
        return dict(argv[i + 1].split("=", 1) for i, value in enumerate(argv[:-1])
                    if value in ("-e", "--env") and "=" in argv[i + 1])

    @staticmethod
    def mounts(argv):
        result = {}
        for i, value in enumerate(argv[:-1]):
            if value in ("-v", "--volume"):
                parts = argv[i + 1].split(":")
                result[parts[1]] = (parts[0], len(parts) > 2 and "ro" in parts[2].split(","))
            elif value == "--mount":
                spec = dict(part.split("=", 1) if "=" in part else (part, "")
                            for part in argv[i + 1].split(","))
                source = spec.get("src", spec.get("source"))
                dest = spec.get("dst", spec.get("target", spec.get("destination")))
                result[dest] = (source, "ro" in spec or "readonly" in spec)
        return result

    def test_workbench_keeps_shared_paths_and_identity_with_spaces(self):
        self.invoke(daemon="n")
        call = self.run_call()
        mounts = self.mounts(call)
        for name in ("work", "git", ".shared_cache"):
            path = str(self.home / name)
            self.assertEqual(mounts[path], (path, False))
        downloads = str(self.home / "Downloads")
        self.assertEqual(mounts[downloads], (downloads, True))
        env = self.envs(call)
        self.assertEqual(env["LOCAL_UID"], str(os.getuid()))
        self.assertEqual(env["LOCAL_HOME"], str(self.home))
        self.assertEqual(env["PATH_DOCKERFILES"], str(REPO))
        self.assertIn(str(self.work), call)

    def test_optional_config_mounts_keep_original_access_modes(self):
        for relative in (".gitconfig", ".docker.credential.gpg", ".screen_layout", ".ssh/config", ".ssh/known_hosts"):
            (self.home / relative).write_text("fixture\n")
        self.invoke(daemon="n")
        mounts = self.mounts(self.run_call())
        self.assertEqual(mounts[str(self.home / ".gitconfig.add")], (str(self.home / ".gitconfig"), True))
        self.assertEqual(mounts[str(self.home / ".host.ssh")], (str(self.home / ".ssh"), True))
        self.assertEqual(mounts[str(self.home / ".host.ssh/known_hosts")], (str(self.home / ".ssh/known_hosts"), False))
        for relative in (".docker.credential.gpg", ".screen_layout"):
            path = str(self.home / relative)
            self.assertEqual(mounts[path], (path, True))

    def test_partial_gpg_configuration_only_mounts_existing_files(self):
        (self.home / ".gnupg").mkdir()
        keyring = self.home / ".gnupg/pubring.kbx"
        keyring.write_text("fixture")
        self.invoke(daemon="n")
        mounts = self.mounts(self.run_call())
        self.assertEqual(mounts[str(keyring)], (str(keyring), True))
        self.assertNotIn(str(self.home / ".gnupg/pubring.kbx~"), mounts)

    def test_workbench_uses_separate_ai_cache(self):
        cache = self.home / ".shared_ai_cache"
        for name in (".codex", ".codex-cstm", ".claude"):
            (cache / name).mkdir(parents=True)
        (cache / ".claude.json").write_text("{}")
        self.invoke(daemon="n")
        mounts = self.mounts(self.run_call())
        self.assertEqual(mounts[str(cache)], (str(cache), False))
        for name in (".codex", ".codex-cstm", ".claude", ".claude.json"):
            self.assertEqual(mounts[str(self.home / name)], (str(cache / name), False))
        self.assertFalse((self.home / ".codex").exists())
        self.assertFalse((self.home / ".claude").exists())

    def test_custom_mount_port_name_tag_and_command_arguments(self):
        extra = self.home / "extra files"
        extra.mkdir()
        self.invoke(daemon="n", mount=str(extra), port="8765", cname="my-workbench", tag="test-tag", creater="example", cmd="printf '%s' 'hello world'")
        call = self.run_call()
        self.assertIn("127.0.0.1:8765:8765", call)
        self.assertIn("my-workbench", call)
        self.assertEqual(self.mounts(call)[str(extra)], (str(extra), False))
        image = call.index("example/workbench:test-tag")
        self.assertEqual(call[image + 1:], ["/bin/bash", "-c", "printf '%s' 'hello world'"])
        self.assertNotIn("-d", call)

    def test_docker_socket_is_preserved_for_nested_docker(self):
        self.invoke(daemon="n")
        mounts = self.mounts(self.run_call())
        # Docker Desktop resolves bind sources inside its own Linux VM.
        self.assertEqual(mounts["/var/run/docker.sock"], ("/var/run/docker.sock", False))

    def test_explicit_docker_socket_is_preserved(self):
        self.invoke(daemon="n", docker_socket=str(self.docker_socket))
        mounts = self.mounts(self.run_call())
        self.assertEqual(mounts["/var/run/docker.sock"], (str(self.docker_socket), False))

    def apple_launch(self, **environment):
        runtime = FakeRuntime()
        env = dict(self.env, DF_ENGINE="apple", DF_AUTO_INSTALL="n", DF_TARGET="workbench",
                   DF_REPO=str(REPO), DF_WORK_DIR=str(self.work), DF_DAEMON="n")
        env.update(environment)
        with mock.patch.dict(os.environ, env, clear=True), \
                mock.patch("launch.platform.system", return_value="Darwin"):
            Launcher(Options(), runtime).start()
        self.assertEqual(len(runtime.runs), 1)
        self.apple_runtime = runtime
        return runtime.runs[0]

    def agent_socket(self, name):
        path = self.base / name
        sock = socket.socket(socket.AF_UNIX)
        sock.bind(str(path))
        self.addCleanup(sock.close)
        return path

    def configured_agent(self):
        source = self.agent_socket("onepass.sock")
        alias = self.home / ".1password/agent.sock"
        alias.parent.mkdir()
        alias.symlink_to(source)
        (self.home / ".ssh/config").write_text("Host *\n  IdentityAgent ~/.1password/agent.sock\n")
        return alias

    def test_apple_uses_volume_for_files_and_docker_socket(self):
        (self.home / ".gitconfig").write_text("fixture")
        call = self.apple_launch()
        self.assertNotIn("--mount", call)
        self.assertNotIn("--publish-socket", call)
        mounts = self.mounts(call)
        self.assertEqual(mounts[str(self.home / ".gitconfig.add")], (str(self.home / ".gitconfig"), True))
        self.assertEqual(mounts["/var/run/docker.sock"], (str(self.docker_socket.resolve()), False))

    def test_apple_uses_native_ssh_forwarding_without_overriding_guest_socket(self):
        agent_path = self.base / "agent.sock"
        agent = socket.socket(socket.AF_UNIX)
        agent.bind(str(agent_path))
        self.addCleanup(agent.close)
        call = self.apple_launch(SSH_AUTH_SOCK=str(agent_path))
        self.assertIn("--ssh", call)
        self.assertNotIn("SSH_AUTH_SOCK", self.envs(call))
        self.assertNotIn("/run/host-services/ssh-auth.sock", self.mounts(call))

    def test_nested_docker_can_only_be_omitted_explicitly(self):
        call = self.apple_launch(DF_DOCKER_SOCKET="n")
        self.assertNotIn("/var/run/docker.sock", self.mounts(call))
        self.assertEqual(self.envs(call)["DOCKER_SOCKET_DISABLED"], "1")

    def test_apple_keeps_localhost_publish_binding(self):
        call = self.apple_launch(DF_PORT="8765")
        self.assertIn("127.0.0.1:8765:8765", call)

    def test_identity_agent_configuration_takes_precedence_over_launchd(self):
        configured = self.configured_agent()
        launchd = self.agent_socket("launchd.sock")
        call = self.apple_launch(DF_TEST_IDENTITY_AGENT=str(configured), SSH_AUTH_SOCK=str(launchd))
        self.assertEqual(self.apple_runtime.environment["SSH_AUTH_SOCK"], str(configured))
        self.assertEqual(self.mounts(call)[str(configured)], (str(configured), False))
        self.assertEqual(self.envs(call)["SSH_AGENT_ALIAS"], str(configured))

    def test_explicit_agent_override_preserves_identity_agent_alias(self):
        configured = self.configured_agent()
        override = self.agent_socket("override.sock")
        call = self.apple_launch(DF_TEST_IDENTITY_AGENT=str(configured), DF_SSH_AGENT=str(override))
        self.assertEqual(self.apple_runtime.environment["SSH_AUTH_SOCK"], str(override))
        self.assertEqual(self.mounts(call)[str(configured)], (str(override), False))

    def test_ai_identity_agent_alias_uses_container_home(self):
        configured = self.configured_agent()
        call = self.apple_launch(DF_TEST_IDENTITY_AGENT=str(configured), DF_TARGET="codex")
        alias = "/home/" + self.envs(call)["LOCAL_WHOAMI"] + "/.1password/agent.sock"
        self.assertEqual(self.mounts(call)[alias], (str(configured), False))
        self.assertEqual(self.envs(call)["SSH_AGENT_ALIAS"], alias)

    def test_workbench_identity_agent_under_ssh_maps_to_readonly_share(self):
        agent = self.agent_socket("onepass.sock")
        alias = self.home / ".ssh/agent.sock"
        alias.symlink_to(agent)
        (self.home / ".ssh/config").write_text("Host *\n  IdentityAgent ~/.ssh/agent.sock\n")
        call = self.apple_launch(DF_TEST_IDENTITY_AGENT=str(alias))
        destination = str(self.home / ".host.ssh/agent.sock")
        self.assertEqual(self.mounts(call)[destination], (str(alias), False))
        self.assertEqual(self.envs(call)["SSH_AGENT_ALIAS"], destination)

    def test_workbench_keeps_shell_command_operators(self):
        command = "printf '%s\\n' 'hello world' && pwd"
        self.invoke(daemon="n", cmd=command)
        call = self.run_call()
        image = call.index("hinoshiba/workbench:latest")
        self.assertEqual(call[image + 1:], ["/bin/bash", "-c", command])

    def test_workbench_accepts_quotes_inside_shell_comments(self):
        command = "echo ok # don't parse this comment as argv"
        self.invoke(daemon="n", cmd=command)
        call = self.run_call()
        image = call.index("hinoshiba/workbench:latest")
        self.assertEqual(call[image + 1:], ["/bin/bash", "-c", command])

    def test_global_volume_cleanup_requires_confirmation(self):
        for action in ("allclean", "allrmo"):
            with self.subTest(action=action):
                self.calls_path.unlink(missing_ok=True)
                result = subprocess.run(
                    [self.make, "--no-print-directory", "-C", str(REPO), action,
                     "engine=docker", "auto_install=n"], env=self.env,
                    input="n\n", text=True, capture_output=True, timeout=30,
                )
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(self.calls(), [], "Declined cleanup must not call the engine")

    def test_make_preserves_guest_shell_dollar_expressions(self):
        command = 'printf "%s\\n" "$HOME" "$(id -u)" "$$"'
        self.invoke(daemon="n", cmd=command)
        call = self.run_call()
        image = call.index("hinoshiba/workbench:latest")
        self.assertEqual(call[image + 1:], ["/bin/bash", "-c", command])

    def test_make_preserves_literal_dollars_in_ai_arguments(self):
        self.invoke(target="codex", ARGS="'$HOME' '$(id -u)' '$$'")
        self.assertEqual(self.run_call()[-3:], ["$HOME", "$(id -u)", "$$"])

    def test_make_preserves_dollars_in_paths(self):
        extra = self.home / "$cache $(directory)"
        extra.mkdir()
        self.invoke(daemon="n", mount=str(extra))
        self.assertEqual(self.mounts(self.run_call())[str(extra)], (str(extra), False))

    def test_autorm_can_be_disabled(self):
        self.invoke(daemon="n", autorm="n")
        self.assertNotIn("--rm", self.run_call())

    def test_noninteractive_smoke_does_not_request_a_tty(self):
        self.invoke("test", cmd="echo ok")
        call = self.run_call()
        self.assertNotIn("-t", call)
        self.assertNotIn("-it", call)
        self.assertNotIn("--tty", call)
        self.assertIn("--rm", call)

    def test_root_mode_retains_workbench_initialization(self):
        self.invoke(daemon="n", root="y")
        env = self.envs(self.run_call())
        self.assertEqual(env["WORKBENCH_ROOT"], "1")
        self.assertEqual(env["LOCAL_HOME"], str(self.home))

    def test_nonzero_container_exit_fails_make(self):
        self.env["DF_TEST_EXIT"] = "17"
        result = self.invoke("test", cmd="false", ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.run_call()

    def test_existing_exact_name_is_reused(self):
        self.env["DF_TEST_STATE"] = json.dumps([{"Names": "workbench", "State": "running"}])
        self.invoke()
        self.assertFalse(any(call[:1] == ["run"] for call in self.calls()))

    def test_similar_container_name_does_not_suppress_start(self):
        self.env["DF_TEST_STATE"] = json.dumps([{"Names": "workbench-backup", "State": "running"}])
        self.invoke(daemon="n")
        self.run_call()

    def test_attach_uses_workbench_user_entrypoint(self):
        self.env["DF_TEST_STATE"] = json.dumps([{"Names": "workbench", "State": "running"}])
        self.invoke("attach")
        calls = [call for call in self.calls() if call[:1] == ["exec"]]
        self.assertEqual(len(calls), 1)
        self.assertIn("workbench", calls[0])
        self.assertIn("/usr/local/bin/exec_user.sh", calls[0])

    def test_stop_removes_only_requested_name(self):
        self.env["DF_TEST_STATE"] = json.dumps([
            {"Names": "workbench", "State": "running"},
            {"Names": "workbench-backup", "State": "running"},
        ])
        self.invoke("stop")
        removals = [call for call in self.calls() if call[:1] == ["rm"]]
        self.assertEqual(len(removals), 1)
        self.assertEqual(removals[0][-1], "workbench")
        self.assertTrue("-f" in removals[0] or "--force" in removals[0])

    def test_local_image_is_built_without_pull_and_retagged_latest(self):
        # Keep build stamps out of the developer checkout.
        self.repo = self.base / "build checkout"
        self.repo.mkdir()
        shutil.copyfile(REPO / "Makefile", self.repo / "Makefile")
        shutil.copytree(REPO / "scripts", self.repo / "scripts")
        context = self.repo / "dockerfiles/workbench"
        context.mkdir(parents=True)
        (context / "Dockerfile").write_text("ARG strict\nFROM ubuntu:${strict}\nARG local_docker_gid\n")
        versions = self.repo / "version/ubuntu"
        versions.mkdir(parents=True)
        (versions / "strict").write_text("24.04\n")
        self.env["DF_TEST_IMAGE_EXISTS"] = "0"
        self.invoke(localimg="y", daemon="n")
        self.assertFalse(any(call[:1] == ["pull"] for call in self.calls()))
        builds = [call for call in self.calls() if call[:1] == ["build"]]
        self.assertEqual(len(builds), 1, self.calls())
        self.assertIn("strict=24.04", builds[0])
        tags = [call for call in self.calls() if call[:2] == ["image", "tag"]]
        self.assertEqual(len(tags), 1, self.calls())
        self.assertEqual(tags[0][-1], "localhost/workbench:latest")
        self.assertIn("localhost/workbench:latest", self.run_call())

    def test_ai_aliases_use_composite_image_and_forward_args(self):
        for target, command in (("codex", "codex"), ("claude", "claude")):
            with self.subTest(target=target):
                self.calls_path.unlink(missing_ok=True)
                self.invoke(target=target, ARGS="--fixture 'argument with spaces'")
                call = self.run_call()
                image = call.index("hinoshiba/claude-codex:latest")
                self.assertEqual(call[image + 1], command)
                self.assertEqual(call[-2:], ["--fixture", "argument with spaces"])
                self.assertIn(str(self.work), call)
                self.assertFalse((self.home / ".codex").exists())
                self.assertFalse((self.home / ".claude").exists())

    def test_default_ai_sessions_do_not_claim_a_shared_container_name(self):
        for target in ("codex", "claude"):
            with self.subTest(target=target):
                self.calls_path.unlink(missing_ok=True)
                self.invoke(target=target)
                self.assertNotIn("--name", self.run_call())

    def test_ai_explicit_container_name_is_honored(self):
        self.invoke(target="codex", cname="independent-ai-session")
        call = self.run_call()
        self.assertEqual(call[call.index("--name") + 1], "independent-ai-session")

    def test_ai_cache_and_customizations_have_expected_destinations(self):
        cache = self.home / ".shared_ai_cache"
        for name in (".codex-cstm", ".claude-cstm"):
            (cache / name).mkdir(parents=True)
        self.invoke(target="codex")
        call = self.run_call()
        username = self.envs(call)["LOCAL_WHOAMI"]
        container_home = Path("/home") / username
        mounts = self.mounts(call)
        for name in (".codex", ".claude", ".claude.json"):
            self.assertEqual(mounts[str(container_home / name)], (str(cache / name), False))
        for name in (".codex-cstm", ".claude-cstm"):
            self.assertEqual(mounts[str(container_home / name)], (str(cache / name), True))

    def test_ai_prebuild_preserves_entrypoint_and_argument_boundaries(self):
        (self.work / ".codex-build").write_text("echo prebuild\n")
        self.invoke(target="codex", ARGS="--fixture 'argument with spaces'")
        call = self.run_call()
        self.assertIn("--entrypoint", call)
        self.assertIn("/usr/local/bin/exec_user.sh", call)
        self.assertIn(".codex-build", " ".join(call))
        self.assertEqual(call[-2:], ["--fixture", "argument with spaces"])

    def test_ai_ignore_masks_only_matching_paths(self):
        private_dir = self.work / "private directory"
        private_dir.mkdir()
        private_file = self.work / "secret.env"
        private_file.write_text("fixture secret")
        visible = self.work / "visible.txt"
        visible.write_text("visible")
        (self.home / ".ai-ignore").write_text("# comment\nprivate directory\n*.env\nmissing\n")
        self.invoke(target="codex")
        mounts = self.mounts(self.run_call())
        self.assertTrue(mounts[str(private_dir)][1])
        self.assertTrue(mounts[str(private_file)][1])
        self.assertNotEqual(mounts[str(private_dir)][0], str(private_dir))
        self.assertNotEqual(mounts[str(private_file)][0], str(private_file))
        for masked in (private_dir, private_file):
            mask_source = Path(mounts[str(masked)][0])
            self.assertTrue(str(mask_source).startswith(str(self.home / '.shared_cache') + '/'))
            self.assertFalse(mask_source.exists(), 'temporary masks must be removed after run')
        self.assertNotIn(str(visible), mounts)
        self.assertEqual(private_file.read_text(), "fixture secret")

    def test_ai_ignore_recursive_globs_include_hidden_directories(self):
        private = self.work / ".private"
        private.mkdir()
        secret = private / "credentials.env"
        secret.write_text("fixture secret")
        (self.home / ".ai-ignore").write_text("**/*.env\n")
        self.invoke(target="codex")
        mounts = self.mounts(self.run_call())
        self.assertIn(str(secret), mounts)
        self.assertTrue(mounts[str(secret)][1])
        self.assertNotEqual(mounts[str(secret)][0], str(secret))

    def test_generic_images_keep_uid_gid_and_temporary_home(self):
        self.invoke(target="python", daemon="n", cmd="python --version")
        call = self.run_call()
        self.assertIn(f"{os.getuid()}:{os.getgid()}", call)
        self.assertEqual(self.envs(call)["HOME"], "/tmphome")
        self.assertIn("hinoshiba/python:latest", call)

    def test_linux_identity_agent_does_not_duplicate_socket_mount(self):
        configured = self.configured_agent()
        runtime = FakeRuntime()
        runtime.engine = "docker"
        env = dict(self.env, DF_ENGINE="docker", DF_TARGET="workbench",
                   DF_TEST_IDENTITY_AGENT=str(configured))
        with mock.patch.dict(os.environ, env, clear=True), \
                mock.patch("launch.platform.system", return_value="Linux"):
            args = []
            Launcher(Options(), runtime).ssh(args)
        mount_specs = [args[i + 1] for i, item in enumerate(args[:-1]) if item == "--mount"]
        self.assertEqual(len(mount_specs), 1, "Docker rejects duplicate mount destinations")
        self.assertEqual(self.mounts(args)[str(configured)], (str(configured), False))

    def test_remote_image_does_not_require_a_local_dockerfile(self):
        self.invoke(target="alpine", creater="library", root="y", daemon="n", cmd="echo remote")
        self.assertIn("library/alpine:latest", self.run_call())

    def test_custom_ai_command_overrides_are_preserved(self):
        for target, option in (("codex", "CODEX_CMD"), ("claude", "CLAUDE_CMD")):
            with self.subTest(target=target):
                self.calls_path.unlink(missing_ok=True)
                self.invoke(target=target, **{option: target + " --fixture-command"})
                call = self.run_call()
                image = call.index("hinoshiba/claude-codex:latest")
                self.assertEqual(call[image + 1:], [target, "--fixture-command"])

    def test_interactive_tty_survives_output_logging(self):
        with mock.patch("launch.sys.stdin.isatty", return_value=True), \
                mock.patch("launch.sys.stdout.isatty", return_value=False):
            self.assertIn("--tty", Launcher.terminal_options())
            self.assertNotIn("--tty", Launcher.terminal_options(interactive=False))

    def test_detached_workbench_keeps_tty_without_host_terminal(self):
        self.invoke()
        call = self.run_call()
        self.assertIn("--detach", call)
        self.assertIn("--interactive", call)
        self.assertIn("--tty", call)

    def test_foreground_workbench_without_host_terminal_omits_tty(self):
        self.invoke(daemon="n")
        call = self.run_call()
        self.assertNotIn("--detach", call)
        self.assertNotIn("--tty", call)


if __name__ == "__main__":
    unittest.main()
