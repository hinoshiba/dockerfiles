#!/usr/bin/env python3
"""Small native CLI adapter for Docker and Apple container.

This is deliberately not a Docker API shim. Image stores, container lifecycles,
and supported maintenance commands stay specific to the selected engine.
"""

import hashlib
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from typing import List, Optional, Sequence


def apple_supported() -> bool:
    """Only use Apple's supported Apple silicon/macOS 26+ configuration."""
    if platform.system() != "Darwin" or platform.machine().lower() not in (
        "arm64", "aarch64"
    ):
        return False
    try:
        return int(platform.mac_ver()[0].split(".")[0]) >= 26
    except (ValueError, IndexError):
        return False


def image_repository(reference: str) -> str:
    """Normalize registry defaults, without conflating similarly named images."""
    reference = reference.split("@", 1)[0]
    last_slash = reference.rfind("/")
    last_colon = reference.rfind(":")
    if last_colon > last_slash:
        reference = reference[:last_colon]
    parts = reference.split("/")
    if len(parts) == 1:
        return "docker.io/library/" + reference
    first = parts[0]
    if first in ("docker.io", "index.docker.io"):
        parts[0] = "docker.io"
        if len(parts) == 2:
            parts.insert(1, "library")
        return "/".join(parts)
    if "." not in first and ":" not in first and first != "localhost":
        return "docker.io/" + reference
    return reference


def install_apple_package():
    """Install only the signed package from apple/container's latest release."""
    request = urllib.request.Request(
        'https://api.github.com/repos/apple/container/releases/latest',
        headers={'Accept': 'application/vnd.github+json', 'User-Agent': 'dockerfiles-runtime-setup'},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        release = json.load(response)
    tag = release.get('tag_name', '')
    if not re.fullmatch(r'v?[0-9]+\.[0-9]+\.[0-9]+', tag):
        raise RuntimeError('Unexpected Apple container release metadata; install the signed package from https://github.com/apple/container/releases')
    name = 'container-' + tag + '-installer-signed.pkg'
    url = 'https://github.com/apple/container/releases/download/' + tag + '/' + name
    assets = [asset for asset in release.get('assets', [])
              if asset.get('name') == name and asset.get('browser_download_url') == url]
    if len(assets) != 1:
        raise RuntimeError('The latest Apple container release has no unique official signed installer; see https://github.com/apple/container/releases')
    digest = assets[0].get('digest')
    if digest and not re.fullmatch(r'sha256:[0-9a-fA-F]{64}', digest):
        raise RuntimeError('Unsupported checksum in Apple container release metadata; installation cancelled')
    print('[runtime] Downloading the official signed Apple container installer (' + tag + ')...', file=sys.stderr)
    with tempfile.TemporaryDirectory(prefix='dockerfiles-container-install-') as directory:
        package = os.path.join(directory, 'container-installer-signed.pkg')
        checksum = hashlib.sha256()
        with urllib.request.urlopen(url, timeout=30) as response, open(package, 'wb') as stream:
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                checksum.update(chunk)
                stream.write(chunk)
        if digest and checksum.hexdigest() != digest.split(':', 1)[1].lower():
            raise RuntimeError('Apple container installer SHA-256 mismatch; installation cancelled')
        try:
            subprocess.run(['/usr/sbin/pkgutil', '--check-signature', package],
                           check=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        except subprocess.CalledProcessError as error:
            raise RuntimeError('Apple container installer signature validation failed; installation cancelled') from error
        print('[runtime] Installing the verified package; macOS may request your administrator password.', file=sys.stderr)
        command = ['/usr/sbin/installer', '-pkg', package, '-target', '/']
        if os.geteuid() != 0:
            command.insert(0, '/usr/bin/sudo')
        subprocess.run(command, check=True)


class Runtime:
    def __init__(self, engine: str = "auto", auto_install: bool = True):
        if engine == "container":
            engine = "apple"
        if engine not in ("auto", "apple", "docker"):
            raise RuntimeError("engine must be auto, apple, or docker")
        if engine == "auto":
            engine = "apple" if apple_supported() else "docker"
        if engine == "apple" and not apple_supported():
            raise RuntimeError("Apple container requires Apple silicon and macOS 26 or later; use engine=docker")
        self.engine = engine
        self.binary = "container" if engine == "apple" else "docker"
        self.auto_install = auto_install

    def call(self, args: Sequence[str], capture: bool = False, check: bool = True,
             timeout: Optional[float] = None):
        # No shell: whitespace/metacharacters in mounts, names, or commands must
        # remain ordinary argument contents. Uncaptured calls inherit the TTY.
        return subprocess.run(
            [self.binary, *map(str, args)],
            check=check,
            text=True,
            stdout=subprocess.PIPE if capture else None,
            stderr=subprocess.PIPE if capture else None,
            timeout=timeout,
        )

    def ensure(self):
        if shutil.which(self.binary) is None:
            if self.engine != "apple":
                raise RuntimeError("docker is not installed; install Docker Engine/Docker Desktop, or select engine=apple on a supported Mac")
            if not self.auto_install:
                raise RuntimeError("Apple container is not installed (auto_install=n); install it or use engine=docker")
            if shutil.which("brew") is None:
                install_apple_package()
            else:
                print("[runtime] Installing Apple container with Homebrew...", file=sys.stderr)
                subprocess.run(["brew", "install", "container"], check=True)
            if shutil.which(self.binary) is None:
                raise RuntimeError("Installed container is not on PATH; add its bin directory (/usr/local/bin for Apple's package) to PATH and retry")
        if self.engine == "apple":
            # `system status` can exit zero even when the service is stopped.
            # A read-only API operation checks whether the service is usable.
            try:
                available = self.call(["list", "--all", "--format", "json"], capture=True, check=False, timeout=10).returncode == 0
            except subprocess.TimeoutExpired:
                available = False
            if not available:
                self.call(["system", "start", "--enable-kernel-install"])
                try:
                    self.call(["list", "--all", "--format", "json"], capture=True, timeout=10)
                except subprocess.TimeoutExpired as error:
                    raise RuntimeError("Apple container services did not become responsive; check container system status/logs") from error
        else:
            try:
                available = self.call(["info"], capture=True, check=False, timeout=10).returncode == 0
            except subprocess.TimeoutExpired:
                available = False
            if not available:
                raise RuntimeError("Cannot connect to Docker; start the configured Docker daemon/Desktop and check docker context/DOCKER_HOST")

    def run(self, args: Sequence[str]):
        resources = []
        if self.engine == "apple":
            resources = ["--memory", os.environ.get("CONTAINER_MEMORY") or "4g"]
            if '--detach' in args and '--tty' in args and not sys.stdin.isatty():
                # Apple reads terminal attributes even in detached mode. A
                # short-lived host PTY allows unattended `make start`, while
                # the guest retains its terminal for the long-lived shell.
                import fcntl
                import pty
                import struct
                import termios
                master, slave = pty.openpty()
                try:
                    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
                    return subprocess.run([self.binary, 'run', *resources, *args],
                                          stdin=slave, check=True, text=True)
                finally:
                    os.close(slave)
                    os.close(master)
        return self.call(["run", *resources, *args])

    def exec(self, args: Sequence[str]):
        return self.call(["exec", *args])

    def pull(self, image: str):
        return self.call((["image", "pull"] if self.engine == "apple" else ["pull"]) + [image])

    def build(self, context: str, image: str, build_args: Sequence[str], no_cache: bool):
        args = ["build"]
        if self.engine == "apple":
            args += ["--memory", os.environ.get("CONTAINER_BUILD_MEMORY") or "4g"]
        if no_cache:
            args.append("--no-cache")
        for value in build_args:
            args += ["--build-arg", value]
        return self.call([*args, "-t", image, str(context)])

    def tag(self, source: str, destination: str):
        return self.call(["image", "tag", source, destination])

    def image_exists(self, image: str) -> bool:
        return self.call(["image", "inspect", image], capture=True, check=False).returncode == 0

    def inspect_image_entrypoint(self, image: str) -> List[str]:
        if self.engine == "docker":
            result = self.call(["image", "inspect", "--format", "{{json .Config.Entrypoint}}", image], capture=True)
            entrypoint = json.loads(result.stdout)
        else:
            result = self.call(["image", "inspect", image], capture=True)
            images = json.loads(result.stdout)
            if not images:
                raise RuntimeError("Apple container returned no metadata for " + image)
            variants = images[0].get("variants", [])
            arch = {"aarch64": "arm64", "x86_64": "amd64"}.get(platform.machine().lower(), platform.machine().lower())
            requested = os.environ.get("CONTAINER_DEFAULT_PLATFORM", "linux/" + arch).split("/")
            selected = [
                variant for variant in variants
                if variant.get("platform", {}).get("os") == requested[0]
                and variant.get("platform", {}).get("architecture") == requested[1]
                and (len(requested) < 3 or variant.get("platform", {}).get("variant") == requested[2])
            ] if len(requested) >= 2 else []
            if not selected:
                raise RuntimeError("No loaded image variant matches " + "/".join(requested) + " for " + image)
            entrypoint = selected[0].get("config", {}).get("config", {}).get("Entrypoint")
        if entrypoint is None:
            return []
        if not isinstance(entrypoint, list) or not all(isinstance(value, str) for value in entrypoint):
            raise RuntimeError("Invalid image entrypoint for " + image)
        return entrypoint

    def _containers(self):
        if self.engine == "apple":
            return json.loads(self.call(["list", "--all", "--format", "json"], capture=True).stdout)
        result = self.call(["ps", "--all", "--format", "{{json .}}"], capture=True)
        return [json.loads(line) for line in result.stdout.splitlines() if line.strip()]

    def container_state(self, name: str) -> Optional[str]:
        for container in self._containers():
            if self.engine == "apple":
                if container.get("id") == name:
                    return "running" if container.get("status", {}).get("state") == "running" else "stopped"
            elif container.get("Names") == name:
                return "running" if container.get("State") == "running" else "stopped"
        return None

    def start(self, name: str):
        return self.call(["start", name])

    def remove(self, name: str):
        return self.call(["delete" if self.engine == "apple" else "rm", "--force", name])

    def remove_images(self, reference: str):
        repository = image_repository(reference)
        if self.engine == "apple":
            rows = json.loads(self.call(["image", "list", "--format", "json"], capture=True).stdout)
            names = [row.get("configuration", {}).get("name", "") for row in rows]
        else:
            result = self.call(["image", "ls", "--format", "{{json .}}"], capture=True)
            rows = [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
            names = [row["Repository"] + ":" + row["Tag"] for row in rows if row.get("Repository") != "<none>" and row.get("Tag") != "<none>"]
        names = sorted(set(name for name in names if name and image_repository(name) == repository))
        if names:
            return self.call(["image", "delete" if self.engine == "apple" else "rm", "--force", *names])
        return None

    def prune_containers(self):
        if self.engine == "docker":
            return self.call(["container", "prune", "--force"])
        names = [row["id"] for row in self._containers() if row.get("status", {}).get("state") == "stopped"]
        if names:
            return self.call(["delete", *names])
        return None

    def prune_images(self):
        # This backs the existing allrmi target, which removes every image.
        if self.engine == "apple":
            return self.call(["image", "delete", "--all"])
        result = self.call(["image", "ls", "--all", "--quiet"], capture=True)
        ids = sorted(set(result.stdout.split()))
        if ids:
            return self.call(["image", "rm", "--force", *ids])
        return None

    def prune_system(self):
        if self.engine == "docker":
            return self.call(["system", "prune", "--volumes", "--force"])
        self.prune_containers()
        self.call(["image", "prune"])
        self.call(["network", "prune"])
        return self.call(["volume", "prune"])
