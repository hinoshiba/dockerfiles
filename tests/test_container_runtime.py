"""Backend regression checks; no installed engines, sockets or network required."""

import hashlib
import io
import json
import os
from pathlib import Path
import pty
import struct
import subprocess
import sys
import termios
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from container_runtime import Runtime, apple_supported, image_repository, install_apple_package


def completed(stdout="", returncode=0):
    return subprocess.CompletedProcess([], returncode, stdout=stdout, stderr="")


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.env = patch.dict(os.environ, {}, clear=True)
        self.env.start()
        self.addCleanup(self.env.stop)

    def apple(self):
        with patch("container_runtime.apple_supported", return_value=True):
            return Runtime("apple")

    def test_supported_os_arch_matrix(self):
        for system, arch, version, expected in [
            ("Darwin", "arm64", "26.5.2", True),
            ("Darwin", "aarch64", "27.0", True),
            ("Darwin", "arm64", "15.7", False),
            ("Darwin", "x86_64", "26.0", False),
            ("Linux", "aarch64", "", False),
            ("Darwin", "arm64", "", False),
        ]:
            with self.subTest(system=system, arch=arch, version=version), \
                    patch("container_runtime.platform.system", return_value=system), \
                    patch("container_runtime.platform.machine", return_value=arch), \
                    patch("container_runtime.platform.mac_ver", return_value=(version, (), "")):
                self.assertEqual(apple_supported(), expected)

    def test_auto_prefers_apple_even_when_not_installed(self):
        with patch("container_runtime.apple_supported", return_value=True), \
                patch("container_runtime.shutil.which", return_value=None):
            self.assertEqual(Runtime().engine, "apple")

    def test_auto_uses_docker_elsewhere(self):
        with patch("container_runtime.apple_supported", return_value=False):
            self.assertEqual(Runtime().engine, "docker")
            with self.assertRaisesRegex(RuntimeError, "macOS 26"):
                Runtime("apple")

    def test_explicit_docker_overrides_apple(self):
        with patch("container_runtime.apple_supported", return_value=True):
            self.assertEqual(Runtime("docker").engine, "docker")

    def test_unknown_engine_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "engine must"):
            Runtime("podman")

    def test_install_opt_out_does_not_install_or_fallback(self):
        runtime = self.apple()
        runtime.auto_install = False
        with patch("container_runtime.shutil.which", return_value=None), \
                patch("container_runtime.subprocess.run") as run:
            with self.assertRaisesRegex(RuntimeError, "auto_install=n"):
                runtime.ensure()
            run.assert_not_called()

    def test_missing_brew_uses_official_signed_package(self):
        runtime = self.apple()
        with patch("container_runtime.shutil.which", side_effect=[None, None, '/usr/local/bin/container']), \
                patch("container_runtime.install_apple_package") as install, \
                patch.object(runtime, 'call', return_value=completed('[]')):
            runtime.ensure()
        install.assert_called_once_with()

    def test_auto_installs_apple_then_checks_service(self):
        runtime = self.apple()
        with patch("container_runtime.shutil.which", side_effect=[None, "/opt/homebrew/bin/brew", "/opt/homebrew/bin/container"]), \
                patch("container_runtime.subprocess.run", return_value=completed("[]")) as run:
            runtime.ensure()
        self.assertEqual(run.call_args_list[0].args[0], ["brew", "install", "container"])
        self.assertEqual(run.call_args_list[1].args[0], ["container", "list", "--all", "--format", "json"])

    def test_service_probe_failure_starts_then_verifies(self):
        runtime = self.apple()
        with patch("container_runtime.shutil.which", return_value="/usr/local/bin/container"), \
                patch.object(runtime, "call", side_effect=[completed(returncode=1), completed(), completed("[]")]) as call:
            runtime.ensure()
        self.assertEqual(call.call_args_list[1].args[0], ["system", "start", "--enable-kernel-install"])
        self.assertTrue(call.call_args_list[2].kwargs.get("capture"))

    def test_running_service_is_not_restarted(self):
        runtime = self.apple()
        with patch("container_runtime.shutil.which", return_value="container"), \
                patch.object(runtime, "call", return_value=completed("[]")) as call:
            runtime.ensure()
        self.assertEqual(call.call_count, 1)

    def test_docker_missing_and_unavailable_are_distinct(self):
        runtime = Runtime("docker")
        with patch("container_runtime.shutil.which", return_value=None):
            with self.assertRaisesRegex(RuntimeError, "not installed"):
                runtime.ensure()
        with patch("container_runtime.shutil.which", return_value="docker"), \
                patch.object(runtime, "call", return_value=completed(returncode=1)):
            with self.assertRaisesRegex(RuntimeError, "Cannot connect"):
                runtime.ensure()

    def test_call_preserves_arguments_and_terminal(self):
        runtime = Runtime("docker")
        args = ["run", "-v", "/a b/$c:/a b/$c", "image", "echo", "$(touch /bad)"]
        with patch("container_runtime.subprocess.run", return_value=completed()) as run:
            runtime.call(args)
        self.assertEqual(run.call_args.args[0], ["docker", *args])
        self.assertIsNone(run.call_args.kwargs["stdout"])
        self.assertIsNone(run.call_args.kwargs["stderr"])
        self.assertNotIn("shell", run.call_args.kwargs)

    def test_run_memory_and_exec_terminal_options(self):
        runtime = self.apple()
        with patch.object(runtime, "call") as call:
            runtime.run(["-i", "-t", "image", "/bin/bash"])
            self.assertEqual(call.call_args.args[0], ["run", "--memory", "4g", "-i", "-t", "image", "/bin/bash"])
            runtime.exec(["-i", "-t", "workbench", "/bin/bash"])
            self.assertEqual(call.call_args.args[0], ["exec", "-i", "-t", "workbench", "/bin/bash"])

    def detached_apple_pty(self, failure=None):
        runtime = self.apple()
        descriptors = []
        real_openpty = pty.openpty

        def open_terminal():
            descriptors.extend(real_openpty())
            return tuple(descriptors)

        def execute(command, **kwargs):
            import fcntl
            self.assertEqual(command, ['container', 'run', '--memory', '4g', '--detach', '--interactive', '--tty', 'image'])
            self.assertEqual(kwargs['stdin'], descriptors[1])
            self.assertTrue(os.isatty(kwargs['stdin']))
            dimensions = fcntl.ioctl(kwargs['stdin'], termios.TIOCGWINSZ, b'\0' * 8)
            self.assertEqual(struct.unpack('HHHH', dimensions)[:2], (24, 80))
            if failure:
                raise failure
            return completed()

        with patch('container_runtime.sys.stdin.isatty', return_value=False), \
                patch('pty.openpty', side_effect=open_terminal), \
                patch('container_runtime.subprocess.run', side_effect=execute):
            if failure:
                with self.assertRaises(type(failure)):
                    runtime.run(['--detach', '--interactive', '--tty', 'image'])
            else:
                self.assertEqual(runtime.run(['--detach', '--interactive', '--tty', 'image']).returncode, 0)
        self.assertEqual(len(descriptors), 2)
        for descriptor in descriptors:
            with self.assertRaises(OSError, msg='temporary host PTY must close after native run'):
                os.fstat(descriptor)

    def test_apple_unattended_detach_uses_temporary_pty_and_closes_it(self):
        self.detached_apple_pty()

    def test_apple_detach_closes_temporary_pty_when_run_fails(self):
        self.detached_apple_pty(subprocess.CalledProcessError(1, 'container run'))

    def test_docker_detach_does_not_create_host_pty(self):
        runtime = Runtime('docker')
        args = ['--detach', '--interactive', '--tty', 'image']
        with patch('container_runtime.sys.stdin.isatty', return_value=False), \
                patch('pty.openpty') as open_terminal, \
                patch.object(runtime, 'call') as call:
            runtime.run(args)
        open_terminal.assert_not_called()
        call.assert_called_once_with(['run', *args])

    def test_apple_detach_inherits_existing_terminal(self):
        runtime = self.apple()
        args = ['--detach', '--interactive', '--tty', 'image']
        with patch('container_runtime.sys.stdin.isatty', return_value=True), \
                patch('pty.openpty') as open_terminal, \
                patch.object(runtime, 'call') as call:
            runtime.run(args)
        open_terminal.assert_not_called()
        call.assert_called_once_with(['run', '--memory', '4g', *args])

    def test_memory_override_does_not_change_docker(self):
        with patch.dict(os.environ, {"CONTAINER_MEMORY": "8g"}):
            runtime = self.apple()
            with patch.object(runtime, "call") as call:
                runtime.run(["image"])
                self.assertEqual(call.call_args.args[0], ["run", "--memory", "8g", "image"])
            runtime = Runtime("docker")
            with patch.object(runtime, "call") as call:
                runtime.run(["image"])
                self.assertEqual(call.call_args.args[0], ["run", "image"])

    def test_empty_make_exports_keep_memory_defaults(self):
        runtime = self.apple()
        with patch.dict(os.environ, {"CONTAINER_MEMORY": "", "CONTAINER_BUILD_MEMORY": ""}), \
                patch.object(runtime, "call") as call:
            runtime.run(["image"])
            self.assertEqual(call.call_args.args[0][1:3], ["--memory", "4g"])
            runtime.build(".", "image", [], False)
            self.assertEqual(call.call_args.args[0][1:3], ["--memory", "4g"])

    def test_unresponsive_docker_health_is_bounded(self):
        runtime = Runtime("docker")
        with patch("container_runtime.shutil.which", return_value="docker"), \
                patch.object(runtime, "call", side_effect=subprocess.TimeoutExpired("docker info", 10)) as call:
            with self.assertRaisesRegex(RuntimeError, "Cannot connect"):
                runtime.ensure()
        self.assertEqual(call.call_args.kwargs["timeout"], 10)

    def test_native_build_commands_and_proxy_argument(self):
        for engine in ("apple", "docker"):
            runtime = self.apple() if engine == "apple" else Runtime(engine)
            with self.subTest(engine=engine), patch.object(runtime, "call") as call:
                runtime.build("directory with spaces", "local/workbench:tag", ["strict=24.04", "https_proxy=http://proxy:80"], True)
                args = call.call_args.args[0]
                self.assertEqual(args[0], "build")
                self.assertIn("--no-cache", args)
                self.assertEqual(args[-7:], ["--build-arg", "strict=24.04", "--build-arg", "https_proxy=http://proxy:80", "-t", "local/workbench:tag", "directory with spaces"])
                self.assertEqual("--memory" in args, engine == "apple")

    def test_native_pull_tag_start_remove_commands(self):
        for engine in ("apple", "docker"):
            runtime = self.apple() if engine == "apple" else Runtime(engine)
            with self.subTest(engine=engine), patch.object(runtime, "call") as call:
                runtime.pull("alpine:3.22")
                self.assertEqual(call.call_args.args[0], (["image", "pull"] if engine == "apple" else ["pull"]) + ["alpine:3.22"])
                runtime.tag("old", "new")
                self.assertEqual(call.call_args.args[0], ["image", "tag", "old", "new"])
                runtime.start("workbench")
                self.assertEqual(call.call_args.args[0], ["start", "workbench"])
                runtime.remove("workbench")
                self.assertEqual(call.call_args.args[0], ["delete" if engine == "apple" else "rm", "--force", "workbench"])

    def test_docker_entrypoint_list_or_null(self):
        runtime = Runtime("docker")
        for output, expected in [('null', []), ('["/entrypoint.sh", "arg with spaces"]', ["/entrypoint.sh", "arg with spaces"])]:
            with self.subTest(output=output), patch.object(runtime, "call", return_value=completed(output)):
                self.assertEqual(runtime.inspect_image_entrypoint("image"), expected)

    def test_apple_entrypoint_selects_platform(self):
        runtime = self.apple()
        images = [{"variants": [
            {"platform": {"architecture": "amd64", "os": "linux"}, "config": {"config": {"Entrypoint": ["x86-entry"]}}},
            {"platform": {"architecture": "arm64", "os": "linux"}, "config": {"config": {"Entrypoint": ["arm-entry"]}}},
        ]}]
        with patch.object(runtime, "call", return_value=completed(json.dumps(images))), \
                patch("container_runtime.platform.machine", return_value="arm64"):
            self.assertEqual(runtime.inspect_image_entrypoint("image"), ["arm-entry"])
            with patch.dict(os.environ, {"CONTAINER_DEFAULT_PLATFORM": "linux/amd64"}):
                self.assertEqual(runtime.inspect_image_entrypoint("image"), ["x86-entry"])
            with patch.dict(os.environ, {"CONTAINER_DEFAULT_PLATFORM": "linux/s390x"}):
                with self.assertRaisesRegex(RuntimeError, "No loaded image variant"):
                    runtime.inspect_image_entrypoint("image")

    def test_invalid_entrypoint_is_not_silently_ignored(self):
        runtime = Runtime("docker")
        with patch.object(runtime, "call", return_value=completed('"not-an-array"')):
            with self.assertRaisesRegex(RuntimeError, "Invalid image entrypoint"):
                runtime.inspect_image_entrypoint("image")

    def test_exact_container_names_not_substring(self):
        docker_rows = '\n'.join(json.dumps(row) for row in [
            {"Names": "workbench-copy", "State": "running"},
            {"Names": "workbench", "State": "exited"},
        ])
        apple_rows = json.dumps([
            {"id": "workbench-copy", "status": {"state": "running"}},
            {"id": "workbench", "status": {"state": "stopped"}},
        ])
        for runtime, output in [(Runtime("docker"), docker_rows), (self.apple(), apple_rows)]:
            with self.subTest(engine=runtime.engine), patch.object(runtime, "call", return_value=completed(output)):
                self.assertEqual(runtime.container_state("workbench"), "stopped")
                self.assertEqual(runtime.container_state("workbench-copy"), "running")
                self.assertIsNone(runtime.container_state("work"))

    def test_repository_normalization(self):
        for reference, expected in [
            ("hinoshiba/workbench:latest", "docker.io/hinoshiba/workbench"),
            ("index.docker.io/hinoshiba/workbench:week", "docker.io/hinoshiba/workbench"),
            ("alpine:3.22", "docker.io/library/alpine"),
            ("docker.io/alpine:3.22", "docker.io/library/alpine"),
            ("localhost/workbench:latest", "localhost/workbench"),
            ("localhost:5000/workbench:latest", "localhost:5000/workbench"),
            ("ghcr.io/org/workbench@sha256:123", "ghcr.io/org/workbench"),
        ]:
            with self.subTest(reference=reference):
                self.assertEqual(image_repository(reference), expected)

    def test_remove_images_keeps_similar_repositories(self):
        runtime = self.apple()
        images = [
            {"configuration": {"name": "docker.io/hinoshiba/workbench:latest"}},
            {"configuration": {"name": "docker.io/hinoshiba/workbench:202647"}},
            {"configuration": {"name": "docker.io/hinoshiba/workbench-copy:latest"}},
            {"configuration": {"name": "ghcr.io/hinoshiba/workbench:latest"}},
        ]
        with patch.object(runtime, "call", side_effect=[completed(json.dumps(images)), completed()]) as call:
            runtime.remove_images("hinoshiba/workbench")
        self.assertEqual(call.call_args.args[0], ["image", "delete", "--force", "docker.io/hinoshiba/workbench:202647", "docker.io/hinoshiba/workbench:latest"])

    def test_docker_remove_images_uses_exact_repository(self):
        runtime = Runtime("docker")
        rows = [
            {"Repository": "hinoshiba/workbench", "Tag": "latest"},
            {"Repository": "hinoshiba/workbench-copy", "Tag": "latest"},
        ]
        with patch.object(runtime, "call", side_effect=[completed('\n'.join(map(json.dumps, rows))), completed()]) as call:
            runtime.remove_images("hinoshiba/workbench")
        self.assertEqual(call.call_args.args[0], ["image", "rm", "--force", "hinoshiba/workbench:latest"])

    def test_empty_cleanup_never_runs_delete_without_names(self):
        for runtime in [self.apple(), Runtime("docker")]:
            with self.subTest(engine=runtime.engine), patch.object(runtime, "call", return_value=completed("[]" if runtime.engine == "apple" else "")) as call:
                runtime.remove_images("missing/repository")
                self.assertEqual(call.call_count, 1)

    def test_apple_prune_only_deletes_stopped_containers(self):
        runtime = self.apple()
        rows = [{"id": "running", "status": {"state": "running"}}, {"id": "old", "status": {"state": "stopped"}}]
        with patch.object(runtime, "call", side_effect=[completed(json.dumps(rows)), completed()]) as call:
            runtime.prune_containers()
        self.assertEqual(call.call_args.args[0], ["delete", "old"])

    def test_system_prune_uses_supported_native_operations(self):
        runtime = self.apple()
        with patch.object(runtime, "prune_containers") as containers, patch.object(runtime, "call") as call:
            runtime.prune_system()
        containers.assert_called_once_with()
        self.assertEqual([c.args[0] for c in call.call_args_list], [["image", "prune"], ["network", "prune"], ["volume", "prune"]])


class SignedInstallerTests(unittest.TestCase):
    def setUp(self):
        self.package = b'fixture signed installer payload'
        self.metadata = {
            'tag_name': '1.7.1',
            'assets': [{
                'name': 'container-1.7.1-installer-signed.pkg',
                'browser_download_url': 'https://github.com/apple/container/releases/download/1.7.1/container-1.7.1-installer-signed.pkg',
                'digest': 'sha256:' + hashlib.sha256(self.package).hexdigest(),
            }],
        }

    def responses(self):
        return [io.BytesIO(json.dumps(self.metadata).encode()), io.BytesIO(self.package)]

    def test_verified_official_package_is_installed_then_deleted(self):
        with patch('container_runtime.urllib.request.urlopen', side_effect=self.responses()) as download, \
                patch('container_runtime.subprocess.run', return_value=completed()) as run, \
                patch('container_runtime.os.geteuid', return_value=501):
            install_apple_package()
        self.assertEqual(download.call_count, 2)
        signature_command = run.call_args_list[0].args[0]
        self.assertEqual(signature_command[:2], ['/usr/sbin/pkgutil', '--check-signature'])
        package = signature_command[-1]
        self.assertEqual(run.call_args_list[1].args[0], ['/usr/bin/sudo', '/usr/sbin/installer', '-pkg', package, '-target', '/'])
        self.assertFalse(Path(package).exists())

    def test_missing_digest_still_requires_valid_package_signature(self):
        self.metadata['assets'][0].pop('digest')
        with patch('container_runtime.urllib.request.urlopen', side_effect=self.responses()), \
                patch('container_runtime.subprocess.run', return_value=completed()) as run, \
                patch('container_runtime.os.geteuid', return_value=0):
            install_apple_package()
        self.assertEqual(run.call_args_list[0].args[0][:2], ['/usr/sbin/pkgutil', '--check-signature'])
        self.assertEqual(run.call_args_list[1].args[0][0], '/usr/sbin/installer')

    def test_bad_checksum_never_executes_installer(self):
        self.metadata['assets'][0]['digest'] = 'sha256:' + '0' * 64
        with patch('container_runtime.urllib.request.urlopen', side_effect=self.responses()), \
                patch('container_runtime.subprocess.run') as run:
            with self.assertRaisesRegex(RuntimeError, 'SHA-256 mismatch'):
                install_apple_package()
        run.assert_not_called()

    def test_bad_signature_never_runs_sudo_or_installer(self):
        with patch('container_runtime.urllib.request.urlopen', side_effect=self.responses()), \
                patch('container_runtime.subprocess.run', side_effect=subprocess.CalledProcessError(1, 'pkgutil')) as run:
            with self.assertRaisesRegex(RuntimeError, 'signature validation failed'):
                install_apple_package()
        self.assertEqual(run.call_count, 1)
        self.assertEqual(run.call_args.args[0][0], '/usr/sbin/pkgutil')

    def test_unsigned_asset_is_never_selected(self):
        self.metadata['assets'][0]['name'] = 'container-installer-unsigned.pkg'
        with patch('container_runtime.urllib.request.urlopen', side_effect=self.responses()) as download, \
                patch('container_runtime.subprocess.run') as run:
            with self.assertRaisesRegex(RuntimeError, 'official signed installer'):
                install_apple_package()
        self.assertEqual(download.call_count, 1)
        run.assert_not_called()

    def test_asset_must_come_from_apple_container_release(self):
        self.metadata['assets'][0]['browser_download_url'] = 'https://example.invalid/installer.pkg'
        with patch('container_runtime.urllib.request.urlopen', side_effect=self.responses()) as download, \
                patch('container_runtime.subprocess.run') as run:
            with self.assertRaisesRegex(RuntimeError, 'official signed installer'):
                install_apple_package()
        self.assertEqual(download.call_count, 1)
        run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
