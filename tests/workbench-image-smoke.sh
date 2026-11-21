#!/bin/bash
# Run inside the built image, for example:
# docker run --rm -i --entrypoint /bin/bash IMAGE -s < tests/workbench-image-smoke.sh
# container run --rm -i --entrypoint /bin/bash IMAGE -s < tests/workbench-image-smoke.sh
set -euo pipefail

export PATH="${HOME}/.cargo/bin:/usr/local/go/bin:${PATH}"

# Everyday tools, networking, source control, language tools and workbench helpers.
for command in bash sudo git git-lfs vim screen telnet nc nmap ifconfig tcpdump \
    curl wget less make hexdump ip zip gpg objdump jq ping dig rsync nkf \
    python3 pip3 flake8 pylint mypy black isort ruff numpydoc pytest \
    node npm npx n corepack gcc g++ devcontainer docker go rustup cargo rustc rustfmt \
    rust-analyzer work template work-git work-cve-maker dockerfiles; do
    command -v "$command" >/dev/null || { echo "Missing command: $command" >&2; exit 1; }
done

# Installed language libraries/docs remain; duplicated downloads and source builds do not.
test -d /usr/local/go/src
test -d /usr/local/include/node
test ! -e /tmp/workbench-python
test -z "$(find / -maxdepth 1 -name 'Python-*' -print -quit)"
test ! -d /usr/local/n/versions/node || test -z "$(find /usr/local/n/versions/node -mindepth 1 -print -quit)"
test ! -d /root/.cache/pip || test -z "$(find /root/.cache/pip -type f -print -quit)"
test ! -d /root/.npm || test -z "$(find /root/.npm -type f -print -quit)"

docker --version
docker compose version
git --version
git lfs version
vim --version | sed -n '1,3p'
screen --version
python3 --version
python3 - <<'PY'
import bz2
import ctypes
import curses
import dbm.gnu
import hashlib
import lzma
import readline
import sqlite3
import ssl
import zlib
from importlib.metadata import version

for package in (
    "pip", "flake8", "pylint", "mypy", "black", "isort", "xyzservices", "ruff",
    "numpydoc", "pytest", "pytest-benchmark",
):
    print(f"{package}: {version(package)}")
for codec in (bz2, lzma):
    assert codec.decompress(codec.compress(b"workbench")) == b"workbench"
with sqlite3.connect(":memory:") as db:
    assert db.execute("SELECT 308").fetchone() == (308,)
assert zlib.decompress(zlib.compress(b"workbench")) == b"workbench"
assert ssl.create_default_context().cert_store_stats()["x509_ca"] > 0
PY
node --version
node -e 'if (JSON.parse("{\"ok\":true}").ok !== true) process.exit(1)'
npm --version
n --version
devcontainer --version
go version
rustc --version
cargo --version
cargo clippy --version
rustfmt --version
rust-analyzer --version
rustup component list --installed | grep '^rust-src'
rustup component list --installed | grep '^rust-docs'

locale -a | grep -iq '^ja_JP\.utf8$'
test -f /etc/dotfiles/bashrc
test -f /etc/dotfiles/screenrc
test -d /var/dotfiles/.vim
echo 'Workbench image smoke checks passed.'
