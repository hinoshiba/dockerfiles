#!/usr/bin/env python3
"""Use checkout versions for local builds and CI, including composite images."""
import argparse
from pathlib import Path
import re
import subprocess


TOOLCHAINS = {
    'RUST_VERSION': ('rust', 'strict'),
    'GO_VERSION': ('golang', 'strict'),
    'PYTHON_VERSION': ('python', 'strict'),
    'PYTHON_MAJOR': ('python', 'major'),
    'NODE_VERSION': ('node', 'strict'),
}


def version_inputs(repo, image):
    dockerfile = (repo / 'dockerfiles' / image / 'Dockerfile').read_text()
    base = next(line for line in dockerfile.splitlines() if line.startswith('FROM ')).split()[1]
    match = re.fullmatch(r'([^:]+):\$\{([^}]+)\}', base)
    inputs = {match[2]: (match[1], match[2])} if match else {}
    for argument, source in TOOLCHAINS.items():
        if re.search(r'^ARG ' + argument + r'(?:=|$)', dockerfile, re.MULTILINE):
            inputs[argument] = source
    return inputs


def build_args(repo, image):
    result = []
    for argument, (language, kind) in version_inputs(repo, image).items():
        value = (repo / 'version' / language / kind).read_text().strip()
        if not re.fullmatch(r'[0-9]+(?:\.[0-9]+)*', value):
            raise ValueError(f'Invalid version/{language}/{kind}: {value!r}')
        result.append(f'{argument}={value}')
    return result


def affected(repo, image, paths):
    versions = {f'version/{language}/{kind}' for language, kind in version_inputs(repo, image).values()}
    shared = {'scripts/image_build.py', '.github/workflows/build_test.yml',
              '.github/workflows/build_pr.yml', '.github/workflows/build_cron.yml'}
    if image in ('workbench', 'claude-codex'):
        shared.add('tests/composite-image-smoke.sh')
    if image in ('golang', 'rust'):
        shared.add('tests/language-image-smoke.sh')
    if image == 'node':
        shared.add('tests/node-image-smoke.sh')
    if image == 'workbench':
        shared.add('tests/workbench-image-smoke.sh')
    return any(path.startswith(f'dockerfiles/{image}/') or path in versions | shared for path in paths)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('image')
    parser.add_argument('--base', help='Git revision to compare with HEAD; omit to build unconditionally')
    options = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    changed = True
    if options.base:
        paths = subprocess.check_output(['git', 'diff', '--name-only', options.base, 'HEAD'], cwd=repo, text=True).splitlines()
        changed = affected(repo, options.image, paths)
    print('changed=' + str(changed).lower())
    print('build_args<<DOCKERFILES_BUILD_ARGS')
    print('\n'.join(build_args(repo, options.image)))
    print('DOCKERFILES_BUILD_ARGS')


if __name__ == '__main__':
    main()
