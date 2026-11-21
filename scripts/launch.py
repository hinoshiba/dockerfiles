#!/usr/bin/env python3
"""Make's portable launcher; deliberately not a Docker CLI emulation layer."""
import contextlib
import datetime
import json
import os
from pathlib import Path
import platform
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile
import time

from container_runtime import Runtime


class Options:
    def __init__(self):
        for key in ('target', 'tag', 'mount', 'root', 'autorm', 'creater', 'port',
                    'cname', 'daemon', 'cmd', 'autorebuild', 'nocache', 'work_dir',
                    'localimg', 'args', 'ssh_agent', 'docker_socket', 'docker_ssh_agent'):
            setattr(self, key, os.environ.get('DF_' + key.upper(), ''))
        self.repo = Path(os.environ.get('DF_REPO') or Path(__file__).resolve().parents[1])
        self.home = Path.home()
        self.engine = os.environ.get('DF_ENGINE') or 'auto'
        self.auto_install = os.environ.get('DF_AUTO_INSTALL', 'y') != 'n'
        self.work_dir = str(Path(self.work_dir or os.getcwd()).absolute())
        self.image_target = 'claude-codex' if self.target in ('claude', 'codex') else self.target
        self.creater = 'localhost' if self.localimg else (self.creater or 'hinoshiba')
        self.name = 'localhost' if self.localimg else (self.cname or self.target)
        self.image = self.creater + '/' + self.image_target + ':' + (self.tag or 'latest')
        self.uid = os.getuid()
        self.gid = self.uid if platform.system() == 'Darwin' else os.getgid()
        self.user = subprocess.check_output(['id', '-un'], text=True).strip()
        self.group = subprocess.check_output(['id', '-gn'], text=True).strip()
        self.ai = self.target in ('codex', 'claude')


def is_socket(path):
    try:
        return stat.S_ISSOCK(os.stat(path).st_mode)
    except OSError:
        return False


class Launcher:
    def __init__(self, options=None, runtime=None):
        self.o = options or Options()
        self.runtime = runtime or Runtime(self.o.engine, self.o.auto_install)

    def check_target(self):
        if not self.o.target:
            raise RuntimeError('not set target. usage: make <operation> target=<your target>')

    def install(self):
        for name in ('work', 'git', '.shared_cache', 'Downloads',
                     '.shared_ai_cache/.claude', '.shared_ai_cache/.codex'):
            (self.o.home / name).mkdir(parents=True, exist_ok=True)
        (self.o.home / '.shared_ai_cache/.claude.json').touch(exist_ok=True)

    def uninstall(self):
        # Remove only empty directories; never erase authentication or user data.
        for name in ('work', 'git', '.shared_cache', 'Downloads',
                     '.shared_ai_cache/.claude', '.shared_ai_cache/.codex',
                     '.shared_ai_cache/.claude-cstm', '.shared_ai_cache/.codex-cstm',
                     '.shared_ai_cache'):
            with contextlib.suppress(OSError):
                (self.o.home / name).rmdir()

    def mount(self, args, source, destination=None, readonly=False):
        source, destination = str(source), str(destination or source)
        if self.runtime.engine == 'apple':
            # --mount accepts directories only. --volume also forwards files and
            # Unix sockets. publish-socket forwards in the opposite direction.
            if ':' in source or ':' in destination:
                raise RuntimeError("Apple volume paths cannot contain ':': " + source)
            args.extend(['--volume', source + ':' + destination + (':ro' if readonly else '')])
        else:
            if ',' in source or ',' in destination:
                raise RuntimeError("Docker bind paths cannot contain ',': " + source)
            args.extend(['--mount', 'type=bind,src=' + source + ',dst=' + destination + (',readonly' if readonly else '')])

    @staticmethod
    def env(args, key, value):
        args.extend(['--env', key + '=' + str(value)])

    def ssh(self, args):
        configured = ''
        if shutil.which('ssh') and (self.o.home / '.ssh/config').is_file():
            result = subprocess.run(['ssh', '-F', str(self.o.home / '.ssh/config'), '-G', 'github.com'], text=True,
                                    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            for line in result.stdout.splitlines():
                if line.lower().startswith('identityagent '):
                    value = line.split(' ', 1)[1]
                    if value not in ('none', 'SSH_AUTH_SOCK', '$SSH_AUTH_SOCK'):
                        configured = os.path.expandvars(os.path.expanduser(value))
                    break
        daemon_source = self.o.docker_ssh_agent or os.environ.get('DOCKERFILES_DOCKER_SSH_SOCK', '')
        if daemon_source and not os.path.isabs(daemon_source):
            raise RuntimeError('docker_ssh_agent must be an absolute path visible to the Docker daemon')
        if self.runtime.engine == 'apple' and (self.o.target == 'workbench' or self.o.ai) and self.o.docker_socket != 'n':
            # A socket forwarded into Apple's VM is not visible to the Docker
            # daemon. Nested launchers must use that daemon's own agent bridge.
            self.env(args, 'DOCKERFILES_DOCKER_SSH_SOCK',
                     daemon_source or '/run/host-services/ssh-auth.sock')
        # IdentityAgent overrides SSH_AUTH_SOCK in OpenSSH (common with
        # 1Password). An explicit Make option takes precedence over both.
        source = self.o.ssh_agent or (configured if is_socket(configured) else '') or os.environ.get('SSH_AUTH_SOCK', '')
        if self.runtime.engine == 'docker' and daemon_source:
            source = daemon_source
        if not source:
            return
        if self.runtime.engine == 'apple':
            if not is_socket(source):
                raise RuntimeError('SSH agent socket not found: ' + source)
            os.environ['SSH_AUTH_SOCK'] = source
            args.append('--ssh')
        else:
            if daemon_source:
                # daemon_source belongs to the Docker host, which may be a
                # different VM. A caller-side stat would reject valid paths.
                pass
            elif platform.system() == 'Darwin':
                source = '/run/host-services/ssh-auth.sock'
            elif not is_socket(source):
                raise RuntimeError('SSH agent socket not found: ' + source)
            self.mount(args, source)
            self.env(args, 'SSH_AUTH_SOCK', source)
            self.env(args, 'DOCKERFILES_DOCKER_SSH_SOCK', source)
        if configured and os.path.isabs(configured):
            destination = configured
            if self.o.ai and destination.startswith(str(self.o.home) + '/'):
                destination = '/home/' + self.o.user + destination[len(str(self.o.home)):]
            if self.o.target == 'workbench' and destination.startswith(str(self.o.home / '.ssh') + '/'):
                destination = str(self.o.home / '.host.ssh') + destination[len(str(self.o.home / '.ssh')):]
            # Docker already mounted source at this destination above. Native
            # runtimes reject duplicate mount targets, even for the same socket.
            if self.runtime.engine == 'apple' or destination != source:
                self.mount(args, source, destination)
            self.env(args, 'SSH_AGENT_ALIAS', destination)

    def docker_socket(self, args):
        if self.o.docker_socket == 'n':
            self.env(args, 'DOCKER_SOCKET_DISABLED', '1')
            return
        source = self.o.docker_socket or '/var/run/docker.sock'
        if self.runtime.engine == 'apple':
            # Nested Docker/Compose/devcontainers still require the Docker API.
            docker = shutil.which('docker')
            desktop = Path('/Applications/Docker.app')
            desktop_cli = desktop / 'Contents/Resources/bin/docker'
            if not docker and desktop_cli.is_file():
                docker = str(desktop_cli)
            if not docker and self.o.auto_install and shutil.which('brew'):
                subprocess.run(['brew', 'install', '--cask', 'docker-desktop'], check=True)
                docker = shutil.which('docker') or (str(desktop_cli) if desktop_cli.is_file() else None)
            if not docker:
                suffix = ' (auto_install=n)' if not self.o.auto_install else ''
                raise RuntimeError("Docker is required for workbench's Docker/Compose commands" + suffix + ". Install/start Docker or explicitly use docker_socket=n.")
            if not self.o.docker_socket:
                # DOCKER_CONTEXT overrides DOCKER_HOST in the Docker CLI. Use
                # the same endpoint, not an unrelated default daemon's socket.
                context = os.environ.get('DOCKER_CONTEXT', '')
                endpoint = '' if context else os.environ.get('DOCKER_HOST', '')
                if not endpoint:
                    command = [docker, 'context', 'inspect'] + ([context] if context else [])
                    data = json.loads(subprocess.check_output(command, text=True))
                    endpoint = data[0]['Endpoints']['docker']['Host']
                if not endpoint.startswith('unix://'):
                    raise RuntimeError('Apple workbench needs a local Docker socket; select a local Docker context or set docker_socket=<path>.')
                source = endpoint[len('unix://'):]
            source = str(Path(source).expanduser().resolve())
            # Probe the socket actually being forwarded. This also makes an
            # explicit docker_socket independent of the current Docker context.
            probe_env = os.environ.copy()
            for key in ('DOCKER_HOST', 'DOCKER_CONTEXT', 'DOCKER_TLS_VERIFY', 'DOCKER_CERT_PATH'):
                probe_env.pop(key, None)
            def ready():
                try:
                    return subprocess.run([docker, '--host', 'unix://' + source, 'info'],
                                          env=probe_env, stdout=subprocess.DEVNULL,
                                          stderr=subprocess.DEVNULL, timeout=5).returncode == 0
                except subprocess.TimeoutExpired:
                    return False
            if not ready():
                desktop_sockets = [self.o.home / '.docker/run/docker.sock',
                                   self.o.home / 'Library/Containers/com.docker.docker/Data/docker.sock']
                uses_desktop = any(str(path.resolve()) == source for path in desktop_sockets)
                uses_desktop = uses_desktop or (not self.o.docker_socket and source in (
                    '/var/run/docker.sock', '/private/var/run/docker.sock'))
                # Starting Desktop is useful only for its own socket. Never
                # launch it to repair a Colima/remote/custom Docker endpoint.
                if desktop.exists() and uses_desktop:
                    subprocess.run(['open', '-a', 'Docker'], check=True)
                    deadline = time.monotonic() + 60
                    while time.monotonic() < deadline and not ready():
                        time.sleep(1)
                if not ready():
                    raise RuntimeError('Docker daemon is unavailable at ' + source + '. Start that daemon to preserve nested Docker/Compose, or explicitly use docker_socket=n.')
            if not is_socket(source):
                raise RuntimeError('Docker socket not found: ' + source)
            # Desktop can create the /var/run symlink during its first launch.
            source = str(Path(source).resolve())
        self.mount(args, source, '/var/run/docker.sock')

    def user_environment(self, args):
        docker_gid = ''
        if self.runtime.engine == 'docker' and platform.system() != 'Darwin':
            import grp
            with contextlib.suppress(KeyError):
                docker_gid = grp.getgrnam('docker').gr_gid
        for key, value in (('LOCAL_UID', self.o.uid), ('LOCAL_GID', self.o.gid),
                           ('DOCKERFILES_ENGINE', self.runtime.engine),
                           ('LOCAL_WHOAMI', self.o.user), ('LOCAL_GROUP', self.o.group),
                           ('LOCAL_HOME', self.o.home), ('LOCAL_HOSTNAME', platform.node()),
                           ('LOCAL_DOCKER_GID', docker_gid), ('PATH_DOCKERFILES', self.o.repo)):
            self.env(args, key, value)

    def workbench_options(self, args):
        self.install()
        self.user_environment(args)
        if self.o.root:
            self.env(args, 'WORKBENCH_ROOT', '1')
        for name in ('work', 'git', '.shared_cache', '.shared_ai_cache'):
            self.mount(args, self.o.home / name)
        self.mount(args, self.o.home / 'Downloads', readonly=True)
        if (self.o.home / '.ai-ignore').exists():
            self.mount(args, self.o.home / '.ai-ignore')
        for name in ('.codex', '.codex-cstm', '.claude', '.claude.json'):
            source = self.o.home / '.shared_ai_cache' / name
            if source.exists():
                self.mount(args, source, self.o.home / name)
        if (self.o.home / '.ssh').is_dir():
            self.mount(args, self.o.home / '.ssh', self.o.home / '.host.ssh', readonly=True)
            if (self.o.home / '.ssh/known_hosts').is_file():
                self.mount(args, self.o.home / '.ssh/known_hosts', self.o.home / '.host.ssh/known_hosts')
        for name in ('openpgp-revocs.d', 'private-keys-v1.d', 'pubring.kbx', 'pubring.kbx~', 'trustdb.gpg'):
            source = self.o.home / '.gnupg' / name
            if source.exists():
                self.mount(args, source, readonly=True)
        for source, dest in (('.gitconfig', '.gitconfig.add'), ('.docker.credential.gpg', '.docker.credential.gpg'),
                             ('.screen_layout', '.screen_layout')):
            if (self.o.home / source).exists():
                self.mount(args, self.o.home / source, self.o.home / dest, readonly=True)
        self.docker_socket(args)

    def ai_options(self, args, temporary):
        self.install()
        self.user_environment(args)
        self.mount(args, self.o.work_dir)
        home = Path('/home') / self.o.user
        for name in ('.codex', '.claude', '.claude.json', '.codex-cstm', '.claude-cstm'):
            source = self.o.home / '.shared_ai_cache' / name
            if source.exists():
                self.mount(args, source, home / name, readonly=name.endswith('-cstm'))
        for name in ('.ssh', '.gitconfig'):
            source = self.o.home / name
            if source.exists():
                self.mount(args, source, home / name, readonly=True)
        self.env(args, 'WORK_DIR', self.o.work_dir)
        for key in ('SKILLS_BOOTSTRAP', 'SKILLS_REFRESH'):
            self.env(args, key, os.environ.get(key, ''))
        ignore = self.o.home / '.ai-ignore'
        if ignore.is_file():
            for line in ignore.read_text().splitlines():
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                # pathlib includes dotfiles, matching the former bash dotglob
                # and globstar behavior even on macOS's Python 3.9.
                pattern = Path(line)
                base = Path(pattern.anchor) if pattern.is_absolute() else Path(self.o.work_dir)
                relative = str(pattern.relative_to(pattern.anchor)) if pattern.is_absolute() else line
                for index, path in enumerate(base.glob(relative)):
                    if not os.path.exists(path):
                        continue
                    masked = Path(temporary) / str(len(args)) / str(index)
                    masked.parent.mkdir(parents=True, exist_ok=True)
                    if os.path.isdir(path):
                        masked.mkdir()
                    else:
                        masked.touch()
                    self.mount(args, masked, path, readonly=True)
        self.docker_socket(args)

    def command(self, attach=False):
        if self.o.target == 'workbench':
            # Preserve workbench's existing shell-command semantics, including
            # pipes/redirects, while retaining quotes rather than joining argv.
            command = ['/bin/bash', '-c', self.o.cmd] if self.o.cmd else []
            return (['/usr/local/bin/exec_user.sh'] if attach else []) + command
        command = shlex.split(self.o.cmd) if self.o.cmd else []
        return command or ['/bin/bash']

    @staticmethod
    def terminal_options(interactive=True):
        return (['--interactive'] if interactive else []) + (['--tty'] if interactive and sys.stdin.isatty() else [])

    def pull(self):
        if not self.o.localimg:
            try:
                self.runtime.pull(self.o.image)
            except subprocess.CalledProcessError:
                self.runtime.inspect_image_entrypoint(self.o.image)
                print('[warn] Pull failed; using cached image ' + self.o.image, file=sys.stderr)

    def build(self):
        context = self.o.repo / 'dockerfiles' / self.o.image_target
        lines = (context / 'Dockerfile').read_text().splitlines()
        base = next(line for line in lines if line.startswith('FROM ')).split()[1]
        match = re.fullmatch(r'([^:]+):\$\{([^}]+)\}', base)
        build_args = []
        if match:
            build_args.append(match[2] + '=' + (self.o.repo / 'version' / match[1] / match[2]).read_text().strip())
        for key in ('http_proxy', 'https_proxy'):
            if os.environ.get(key):
                build_args.append(key + '=' + os.environ[key])
        if platform.system() != 'Darwin' and any(re.match(r'^ARG local_docker_gid(?:=|$)', line) for line in lines):
            import grp
            with contextlib.suppress(KeyError):
                build_args.append('local_docker_gid=' + str(grp.getgrnam('docker').gr_gid))
        version = 'latest' if self.o.autorebuild else datetime.date.today().strftime('%Y%U')
        image = self.o.creater + '/' + self.o.image_target + ':' + version
        marker = self.o.repo / '.mtx' / (self.runtime.engine + '.' + self.o.image_target + '.' + self.o.creater.replace('/', '_') + '.' + version)
        sources = [p for p in context.rglob('*') if p.is_file() and not p.name.endswith('.swp')]
        sources += list((self.o.repo / 'version').glob('*/*'))
        fresh = marker.exists() and all(p.stat().st_mtime <= marker.stat().st_mtime for p in sources)
        latest = self.o.creater + '/' + self.o.image_target + ':latest'
        aliases = [latest]
        if self.o.tag:
            aliases.append(self.o.image)
        aliases = list(dict.fromkeys(alias for alias in aliases if alias != image))
        if fresh and self.runtime.image_exists(image):
            # Build stamps belong to the source/version, not every possible
            # requested tag. Recreate missing aliases without a needless build.
            for alias in aliases:
                if not self.runtime.image_exists(alias):
                    self.runtime.tag(image, alias)
            return
        self.runtime.build(str(context), image, build_args, not bool(self.o.nocache))
        for alias in aliases:
            self.runtime.tag(image, alias)
        marker.parent.mkdir(exist_ok=True)
        marker.touch()

    def start(self, testing=False):
        if not testing and not self.o.ai:
            state = self.runtime.container_state(self.o.name)
            if state:
                if state != 'running':
                    self.runtime.start(self.o.name)
                return
        if not testing:
            self.build() if self.o.localimg else self.pull()
        args = []
        if not testing and (not self.o.ai or self.o.cname):
            args += ['--name', self.o.name]
        args += self.terminal_options(not testing)
        if testing or not self.o.autorm or self.o.ai:
            args.append('--rm')
        if not testing and not self.o.daemon and not self.o.ai:
            args.append('--detach')
            # A detached shell needs its own terminal even when Make is run
            # from a pipe/CI. Without it Apple's stdin closes and PID 1 exits,
            # terminating an immediately following attach during startup.
            if '--tty' not in args:
                args.append('--tty')
        temporary_parent = None
        if self.o.ai:
            self.install()
            # Docker bind sources are resolved by its daemon. When Make runs
            # inside Apple workbench, only this shared absolute path (not the
            # guest's /tmp) exists on the host too.
            temporary_parent = str(self.o.home / '.shared_cache')
        with tempfile.TemporaryDirectory(prefix='dockerfiles-ai-', dir=temporary_parent) as temporary:
            if self.o.target == 'workbench':
                self.workbench_options(args)
            elif self.o.ai:
                self.ai_options(args, temporary)
            elif not self.o.root:
                args.extend(['--user', str(self.o.uid) + ':' + str(os.getgid())])
                self.env(args, 'HOME', '/tmphome')
            self.ssh(args)
            if self.o.mount:
                self.mount(args, self.o.mount)
            args.extend(['--workdir', self.o.work_dir])
            if self.o.port:
                args.extend(['--publish', '127.0.0.1:' + self.o.port + ':' + self.o.port])
            if self.o.ai:
                default = 'codex' if self.o.target == 'codex' else 'claude --permission-mode auto --dangerously-skip-permissions'
                command = shlex.split(os.environ.get('DF_' + self.o.target.upper() + '_CMD') or default)
                command += shlex.split(self.o.args)
                build_file = '.' + self.o.target + '-build'
                if (Path(self.o.work_dir) / build_file).is_file():
                    entrypoint = self.runtime.inspect_image_entrypoint(self.o.image)
                    args.extend(['--entrypoint', '/bin/bash'])
                    command = ['-lc', 'set -euo pipefail; build_file="$1"; shift; bash "$build_file"; exec "$@"', '--', build_file] + entrypoint + command
            else:
                command = self.command()
            self.runtime.run(args + [self.o.image] + command)

    def attach(self):
        if self.runtime.container_state(self.o.name) == 'running':
            self.runtime.exec(self.terminal_options() + [self.o.name] + self.command(attach=True))

    def dispatch(self, action):
        if action in ('install', 'uninstall'):
            getattr(self, action)()
            if action == 'install':
                self.runtime.ensure()
            return
        if action == 'check_target':
            self.check_target()
            return
        if action not in ('allclean', 'allrm', 'allrmi', 'allrmo', 'check_health'):
            self.check_target()
        self.runtime.ensure()
        if action == 'all':
            self.start()
            if not self.o.daemon and not self.o.ai:
                self.attach()
        elif action == 'test':
            self.start(testing=True)
        elif action in ('start', 'attach', 'build', 'pull'):
            getattr(self, action)()
        elif action == 'stop':
            if self.runtime.container_state(self.o.name):
                self.runtime.remove(self.o.name)
        elif action == 'clean':
            self.runtime.remove_images(self.o.creater + '/' + self.o.image_target)
            for p in (self.o.repo / '.mtx').glob(self.runtime.engine + '.' + self.o.image_target + '.' + self.o.creater.replace('/', '_') + '.*'):
                p.unlink()
        elif action in ('allrm', 'allrmi', 'allrmo', 'allclean'):
            if action in ('allrm', 'allclean'):
                self.runtime.prune_containers()
            if action in ('allrmi', 'allclean'):
                self.runtime.prune_images()
            if action in ('allrmo', 'allclean'):
                self.runtime.prune_system()
        elif action != 'check_health':
            raise RuntimeError('Unknown operation: ' + action)


if __name__ == '__main__':
    try:
        Launcher().dispatch(sys.argv[1] if len(sys.argv) > 1 else 'all')
    except subprocess.CalledProcessError as error:
        sys.exit(error.returncode if error.returncode > 0 else 128 - error.returncode)
    except (RuntimeError, ValueError, OSError) as error:
        print('ERROR: ' + str(error), file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        sys.exit(130)
