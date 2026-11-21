"""Focused launcher checks for engine/socket selection and build stamp recovery."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from launch import Launcher


class SocketTests(unittest.TestCase):
    def setUp(self):
        self.options = SimpleNamespace(docker_socket='', auto_install=True, home=Path('/test/home'))
        self.runtime = SimpleNamespace(engine='apple')
        self.launcher = Launcher(self.options, self.runtime)
        self.env = patch.dict(os.environ, {}, clear=True)
        self.env.start()
        self.addCleanup(self.env.stop)

    def test_disable_is_explicit_and_does_not_probe_or_install(self):
        self.options.docker_socket = 'n'
        with patch('launch.subprocess.run') as run:
            args = []
            self.launcher.docker_socket(args)
        run.assert_not_called()
        self.assertEqual(args, ['--env', 'DOCKER_SOCKET_DISABLED=1'])

    def test_docker_backend_keeps_vm_socket_default(self):
        self.runtime.engine = 'docker'
        with patch.dict(os.environ, {'DOCKER_HOST': 'unix:///some/host-facing.sock'}):
            args = []
            self.launcher.docker_socket(args)
        self.assertEqual(args, ['--mount', 'type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock'])

    def test_explicit_socket_overrides_unrelated_context(self):
        self.options.docker_socket = '/test/custom.sock'
        with patch('launch.shutil.which', return_value='/usr/local/bin/docker'), \
                patch('launch.is_socket', return_value=True), \
                patch('launch.subprocess.run', return_value=subprocess.CompletedProcess([], 0)) as run, \
                patch('launch.subprocess.check_output') as output, \
                patch.dict(os.environ, {'DOCKER_CONTEXT': 'remote', 'DOCKER_HOST': 'tcp://remote:2376', 'DOCKER_TLS_VERIFY': '1'}):
            args = []
            self.launcher.docker_socket(args)
        output.assert_not_called()
        self.assertEqual(run.call_args.args[0], ['/usr/local/bin/docker', '--host', 'unix:///test/custom.sock', 'info'])
        for key in ('DOCKER_CONTEXT', 'DOCKER_HOST', 'DOCKER_TLS_VERIFY'):
            self.assertNotIn(key, run.call_args.kwargs['env'])
        self.assertEqual(args, ['--volume', '/test/custom.sock:/var/run/docker.sock'])

    def test_context_overrides_docker_host_like_docker_cli(self):
        metadata = [{'Endpoints': {'docker': {'Host': 'unix:///test/context.sock'}}}]
        with patch('launch.shutil.which', return_value='docker'), \
                patch('launch.is_socket', return_value=True), \
                patch('launch.subprocess.run', return_value=subprocess.CompletedProcess([], 0)) as run, \
                patch('launch.subprocess.check_output', return_value=json.dumps(metadata)) as output, \
                patch.dict(os.environ, {'DOCKER_CONTEXT': 'preferred', 'DOCKER_HOST': 'unix:///ignored.sock'}):
            args = []
            self.launcher.docker_socket(args)
        self.assertEqual(output.call_args.args[0], ['docker', 'context', 'inspect', 'preferred'])
        self.assertEqual(run.call_args.args[0], ['docker', '--host', 'unix:///test/context.sock', 'info'])
        self.assertIn('/test/context.sock:/var/run/docker.sock', args)

    def test_remote_endpoint_fails_without_launching_desktop(self):
        with patch('launch.shutil.which', return_value='docker'), \
                patch('launch.subprocess.run') as run, \
                patch.dict(os.environ, {'DOCKER_HOST': 'ssh://host'}):
            with self.assertRaisesRegex(RuntimeError, 'local Docker socket'):
                self.launcher.docker_socket([])
        run.assert_not_called()

    def test_custom_daemon_failure_does_not_start_desktop(self):
        self.options.docker_socket = '/test/colima.sock'
        with patch('launch.shutil.which', return_value='docker'), \
                patch('launch.Path.exists', return_value=True), \
                patch('launch.subprocess.run', return_value=subprocess.CompletedProcess([], 1)) as run:
            with self.assertRaisesRegex(RuntimeError, 'unavailable at /test/colima.sock'):
                self.launcher.docker_socket([])
        self.assertTrue(all(call.args[0][0] == 'docker' for call in run.call_args_list))

    def test_install_opt_out_never_invokes_brew(self):
        self.options.auto_install = False
        with patch('launch.shutil.which', return_value=None), \
                patch('launch.Path.is_file', return_value=False), \
                patch('launch.subprocess.run') as run:
            with self.assertRaisesRegex(RuntimeError, 'auto_install=n'):
                self.launcher.docker_socket([])
        run.assert_not_called()


class NestedAgentTests(unittest.TestCase):
    def setUp(self):
        self.options = SimpleNamespace(docker_socket='', docker_ssh_agent='', ssh_agent='',
                                       home=Path('/Users/example'), target='workbench',
                                       ai=False, user='example')
        self.runtime = SimpleNamespace(engine='docker')
        self.launcher = Launcher(self.options, self.runtime)
        self.env = patch.dict(os.environ, {}, clear=True)
        self.env.start()
        self.addCleanup(self.env.stop)

    def test_nested_linux_uses_daemon_agent_not_apple_guest_socket(self):
        daemon_agent = '/run/host-services/ssh-auth.sock'
        with patch.dict(os.environ, {'SSH_AUTH_SOCK': '/var/host-services/ssh-auth.sock',
                                    'DOCKERFILES_DOCKER_SSH_SOCK': daemon_agent}), \
                patch('launch.shutil.which', return_value=None), \
                patch('launch.platform.system', return_value='Linux'), \
                patch('launch.is_socket', return_value=False) as check_socket:
            args = []
            self.launcher.ssh(args)
        self.assertIn('type=bind,src=' + daemon_agent + ',dst=' + daemon_agent, args)
        self.assertIn('SSH_AUTH_SOCK=' + daemon_agent, args)
        self.assertIn('DOCKERFILES_DOCKER_SSH_SOCK=' + daemon_agent, args)
        self.assertNotIn('/var/host-services/ssh-auth.sock', ' '.join(args))
        self.assertNotIn(daemon_agent, [call.args[0] for call in check_socket.call_args_list])

    def test_explicit_daemon_agent_overrides_inherited_bridge(self):
        self.options.docker_ssh_agent = '/run/custom-agent.sock'
        with patch.dict(os.environ, {'DOCKERFILES_DOCKER_SSH_SOCK': '/run/old-agent.sock'}), \
                patch('launch.shutil.which', return_value=None), \
                patch('launch.platform.system', return_value='Linux'):
            args = []
            self.launcher.ssh(args)
        self.assertIn('SSH_AUTH_SOCK=/run/custom-agent.sock', args)
        self.assertNotIn('/run/old-agent.sock', ' '.join(args))

    def test_nested_identity_agent_alias_mount_uses_daemon_source(self):
        configured = '/Users/example/.1password/agent.sock'
        daemon = '/run/host-services/ssh-auth.sock'
        output = subprocess.CompletedProcess([], 0, stdout='identityagent ' + configured + '\n')
        with patch.dict(os.environ, {'DOCKERFILES_DOCKER_SSH_SOCK': daemon}), \
                patch('launch.shutil.which', return_value='ssh'), \
                patch('launch.Path.is_file', return_value=True), \
                patch('launch.platform.system', return_value='Linux'), \
                patch('launch.is_socket', return_value=False), \
                patch('launch.subprocess.run', return_value=output) as run:
            args = []
            self.launcher.ssh(args)
        self.assertEqual(run.call_args.args[0], ['ssh', '-F', '/Users/example/.ssh/config', '-G', 'github.com'])
        self.assertIn('type=bind,src=' + daemon + ',dst=' + configured, args)
        self.assertIn('SSH_AGENT_ALIAS=' + configured, args)

    def test_apple_workbench_passes_desktop_hint_for_nested_launchers(self):
        self.runtime.engine = 'apple'
        with patch('launch.shutil.which', return_value=None):
            args = []
            self.launcher.ssh(args)
        self.assertIn('DOCKERFILES_DOCKER_SSH_SOCK=/run/host-services/ssh-auth.sock', args)

    def test_apple_custom_daemon_hint_is_preserved(self):
        self.runtime.engine = 'apple'
        self.options.docker_ssh_agent = '/run/colima-agent.sock'
        with patch('launch.shutil.which', return_value=None):
            args = []
            self.launcher.ssh(args)
        self.assertIn('DOCKERFILES_DOCKER_SSH_SOCK=/run/colima-agent.sock', args)

    def test_direct_apple_ai_launch_also_preserves_nested_docker_agent(self):
        self.runtime.engine = 'apple'
        self.options.target = 'codex'
        self.options.ai = True
        with patch('launch.shutil.which', return_value=None):
            args = []
            self.launcher.ssh(args)
        self.assertIn('DOCKERFILES_DOCKER_SSH_SOCK=/run/host-services/ssh-auth.sock', args)

    def test_disabled_docker_does_not_pass_nested_agent_hint(self):
        self.runtime.engine = 'apple'
        self.options.docker_socket = 'n'
        with patch('launch.shutil.which', return_value=None):
            args = []
            self.launcher.ssh(args)
        self.assertEqual(args, [])


class BuildStampTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='dockerfiles-build-stamp-')
        self.addCleanup(temporary.cleanup)
        self.repo = Path(temporary.name)
        context = self.repo / 'dockerfiles/workbench'
        context.mkdir(parents=True)
        (context / 'Dockerfile').write_text('ARG strict\nFROM ubuntu:${strict}\nARG local_docker_gid\n')
        versions = self.repo / 'version/ubuntu'
        versions.mkdir(parents=True)
        (versions / 'strict').write_text('24.04\n')
        self.options = SimpleNamespace(repo=self.repo, image_target='workbench',
                                       autorebuild='', creater='localhost', tag='',
                                       image='localhost/workbench:latest', nocache='')
        self.runtime = Mock(engine='docker')
        self.launcher = Launcher(self.options, self.runtime)

    def test_fresh_marker_with_deleted_image_rebuilds(self):
        self.launcher.build()
        self.runtime.reset_mock()
        self.runtime.image_exists.return_value = False
        self.launcher.build()
        self.runtime.build.assert_called_once()

    def test_missing_latest_tag_is_repaired_without_rebuilding(self):
        self.launcher.build()
        built_image = self.runtime.build.call_args.args[1]
        self.runtime.reset_mock()
        self.runtime.image_exists.side_effect = [True, False]
        self.launcher.build()
        self.runtime.build.assert_not_called()
        self.runtime.tag.assert_called_once_with(built_image, 'localhost/workbench:latest')

    def test_new_requested_tag_is_created_from_cached_build(self):
        self.launcher.build()
        built_image = self.runtime.build.call_args.args[1]
        self.runtime.reset_mock()
        self.options.tag = 'development'
        self.options.image = 'localhost/workbench:development'
        self.runtime.image_exists.side_effect = [True, True, False]
        self.launcher.build()
        self.runtime.build.assert_not_called()
        self.runtime.tag.assert_called_once_with(built_image, 'localhost/workbench:development')

    def test_stamps_are_separate_between_engines(self):
        self.launcher.build()
        self.runtime.reset_mock()
        self.runtime.engine = 'apple'
        self.launcher.build()
        self.runtime.build.assert_called_once()

    def test_linux_docker_group_build_arg_is_preserved(self):
        with patch('launch.platform.system', return_value='Linux'), \
                patch('grp.getgrnam', return_value=SimpleNamespace(gr_gid=1234)):
            self.launcher.build()
        self.assertIn('local_docker_gid=1234', self.runtime.build.call_args.args[2])

    def test_existing_nocache_flag_semantics_are_preserved(self):
        self.options.nocache = 'n'
        self.launcher.build()
        self.assertFalse(self.runtime.build.call_args.args[3])


if __name__ == '__main__':
    unittest.main()
