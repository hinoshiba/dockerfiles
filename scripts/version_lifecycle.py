#!/usr/bin/env python3
"""Validate pinned versions and consume endoflife.date's typed v1 lifecycle API."""

import argparse
import datetime
import json
import os
from pathlib import Path
import re
import sys
import urllib.request


PRODUCTS = {'golang': 'go', 'node': 'nodejs', 'python': 'python', 'rust': 'rust'}
VERSION = re.compile(r'[0-9]+(?:\.[0-9]+)*')


def parse_version(value):
    if not isinstance(value, str) or not VERSION.fullmatch(value):
        raise ValueError('Expected a numeric pinned version, got ' + repr(value))
    return tuple(int(part) for part in value.split('.'))


def validate_pair(cycle, version):
    parse_version(cycle)
    parse_version(version)
    if version != cycle and not version.startswith(cycle + '.'):
        raise ValueError('Version ' + version + ' does not belong to cycle ' + cycle)


def read_versions(root, product):
    directory = Path(root) / 'version' / product
    cycle = (directory / 'major').read_text().strip()
    version = (directory / 'strict').read_text().strip()
    validate_pair(cycle, version)
    return cycle, version


def validate_all(root):
    for directory in sorted((Path(root) / 'version').iterdir()):
        if directory.is_dir():
            cycle, version = read_versions(root, directory.name)
            print(directory.name + ': ' + cycle + ' / ' + version)


def parse_date(value, field):
    if value is None:
        return None
    if not isinstance(value, str) or not re.fullmatch(r'[0-9]{4}-[0-9]{2}-[0-9]{2}', value):
        raise ValueError('Lifecycle date ' + field + ' must be an ISO date')
    return datetime.date.fromisoformat(value)


def lifecycle_flag(release, flag, date_field, today, optional=False):
    value = release.get(flag)
    if value is None and optional:
        value = False
    if type(value) is not bool:
        raise ValueError('Lifecycle field ' + flag + ' must be a boolean')
    deadline = parse_date(release.get(date_field), date_field)
    # Recompute date boundaries as well, so a cached API response does not delay
    # a notice when its end date arrives. Never compare Boolean strings to dates.
    return value or (deadline is not None and deadline <= today)


def evaluate(metadata, cycle, current, today=None):
    validate_pair(cycle, current)
    today = today or datetime.datetime.now(datetime.timezone.utc).date()
    if not isinstance(metadata, dict) or not isinstance(metadata.get('result'), dict):
        raise ValueError('Missing lifecycle API result')
    release = metadata['result']
    if release.get('name') != cycle:
        raise ValueError('Lifecycle API returned a different release cycle')
    latest = release.get('latest')
    if not isinstance(latest, dict):
        raise ValueError('Missing latest release metadata')
    candidate = latest.get('name')
    validate_pair(cycle, candidate)
    published = parse_date(latest.get('date'), 'latest.date')
    if published is not None and published > today:
        raise ValueError('Refusing a future-dated release')
    ended = lifecycle_flag(release, 'isEol', 'eolFrom', today)
    support_ended = lifecycle_flag(release, 'isEoas', 'eoasFrom', today, optional=True)
    # Metadata can lag a manually pinned patch: never create a downgrade PR.
    changed = parse_version(candidate) > parse_version(current)
    return {
        'cycle': cycle,
        'version': candidate if changed else current,
        'previous': current,
        'changed': str(changed).lower(),
        'eol': str(ended).lower(),
        'support_out': str(support_ended and not ended).lower(),
        'eol_date': release.get('eolFrom') or 'not announced',
    }


def fetch_metadata(product, cycle):
    url = 'https://endoflife.date/api/v1/products/' + PRODUCTS[product] + '/releases/' + cycle
    request = urllib.request.Request(url, headers={
        'Accept': 'application/json', 'User-Agent': 'dockerfiles-lifecycle-check',
    })
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def write_reports(directory, product, result):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    reference = 'https://endoflife.date/' + PRODUCTS[product]
    for kind, label in (('eol', 'EOL'), ('support_out', 'support_out')):
        if result[kind] != 'true':
            continue
        state = 'EOL' if kind == 'eol' else 'support out'
        title = product + '/' + result['cycle'] + ' is ' + state + '.'
        if kind == 'eol':
            body = 'This release cycle has reached end of life. Move to a supported release cycle.'
        else:
            body = ('Active support has ended. This does not mean end of life: security maintenance '
                    'may continue until ' + result['eol_date'] + '. Review the upstream support policy '
                    'before choosing a replacement cycle.')
        (directory / (kind + '.md')).write_text(
            '---\ntitle: ' + title + '\nlabels: ' + label + '\nassignees: hinoshiba\n---\n'
            + body + '\n\nDetails: ' + reference + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--check-files', action='store_true')
    parser.add_argument('--product', choices=PRODUCTS)
    parser.add_argument('--metadata', type=Path, help='Read an API fixture instead of using the network')
    parser.add_argument('--update', action='store_true', help='Write a newer patch in the selected cycle')
    parser.add_argument('--report-dir', type=Path)
    parser.add_argument('--github-output', type=Path)
    args = parser.parse_args()
    if args.check_files:
        validate_all(args.root)
        return
    if not args.product:
        parser.error('--product is required unless --check-files is used')
    cycle, current = read_versions(args.root, args.product)
    metadata = json.loads(args.metadata.read_text()) if args.metadata else fetch_metadata(args.product, cycle)
    result = evaluate(metadata, cycle, current)
    if args.update and result['changed'] == 'true':
        (args.root / 'version' / args.product / 'strict').write_text(result['version'] + '\n')
    if args.report_dir:
        write_reports(args.report_dir, args.product, result)
    output = args.github_output or (Path(os.environ['GITHUB_OUTPUT']) if os.environ.get('GITHUB_OUTPUT') else None)
    if output:
        with output.open('a') as stream:
            for key in ('cycle', 'version', 'previous', 'changed', 'eol', 'support_out'):
                stream.write(key + '=' + result[key] + '\n')
    print(json.dumps(result, sort_keys=True))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError) as error:
        print('ERROR: ' + str(error), file=sys.stderr)
        sys.exit(1)
