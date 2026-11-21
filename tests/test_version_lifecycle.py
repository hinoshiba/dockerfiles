import datetime
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'scripts' / 'version_lifecycle.py'
SPEC = importlib.util.spec_from_file_location('version_lifecycle', SCRIPT)
lifecycle = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(lifecycle)
TODAY = datetime.date(2026, 11, 21)


def metadata(cycle='26', version='26.13.1', **fields):
    release = {
        'name': cycle,
        'isEol': False,
        'eolFrom': None,
        'latest': {'name': version, 'date': '2026-11-10'},
    }
    release.update(fields)
    return {'schema_version': '1.2.1', 'result': release}


class VersionValidationTests(unittest.TestCase):
    def test_cycle_requires_a_component_boundary(self):
        for cycle, version in [('1.27', '1.27.4'), ('26', '26.13.1'), ('24.04', '24.04')]:
            lifecycle.validate_pair(cycle, version)
        for cycle, version in [('1.2', '1.27.4'), ('26', '126.0.0'), ('1.27', '11.27.4')]:
            with self.subTest(cycle=cycle, version=version), self.assertRaises(ValueError):
                lifecycle.validate_pair(cycle, version)

    def test_rejects_non_numeric_or_multiline_versions(self):
        for version in [None, 26, '', '26.14.0-rc.1', 'v26.13.1', '26.13.1\neol=true']:
            with self.subTest(version=version), self.assertRaises(ValueError):
                lifecycle.validate_pair('26', version)

    def test_repository_pins_are_valid(self):
        for directory in (ROOT / 'version').iterdir():
            if directory.is_dir():
                lifecycle.read_versions(ROOT, directory.name)


class LifecycleTests(unittest.TestCase):
    def evaluate(self, data, current='26.13.0'):
        return lifecycle.evaluate(data, '26', current, TODAY)

    def test_active_cycle_without_support_date_does_not_alert(self):
        result = self.evaluate(metadata())
        self.assertEqual(result['eol'], 'false')
        self.assertEqual(result['support_out'], 'false')

    def test_boolean_flags_remain_booleans(self):
        result = self.evaluate(metadata(isEol=True))
        self.assertEqual(result['eol'], 'true')
        for value in ['false', 'true', '2026-11-10', 0, 1, None]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.evaluate(metadata(isEol=value))

    def test_optional_support_flag_can_be_null(self):
        self.assertEqual(self.evaluate(metadata(isEoas=None))['support_out'], 'false')
        with self.assertRaises(ValueError):
            self.evaluate(metadata(isEoas='false'))

    def test_cached_flags_respect_end_date_including_boundary(self):
        for end, expected in [('2026-11-20', 'true'), ('2026-11-21', 'true'), ('2026-11-22', 'false')]:
            with self.subTest(end=end):
                result = self.evaluate(metadata(eolFrom=end))
                self.assertEqual(result['eol'], expected)

    def test_end_of_active_support_is_not_eol(self):
        result = self.evaluate(metadata(isEoas=True, eoasFrom='2026-10-20', eolFrom='2028-04-30'))
        self.assertEqual(result['eol'], 'false')
        self.assertEqual(result['support_out'], 'true')
        self.assertEqual(result['eol_date'], '2028-04-30')

    def test_eol_only_creates_one_kind_of_notice(self):
        result = self.evaluate(metadata(isEol=True, isEoas=True))
        self.assertEqual(result['eol'], 'true')
        self.assertEqual(result['support_out'], 'false')

    def test_numeric_patch_order_prevents_downgrades(self):
        for current, candidate, changed, selected in [
            ('26.9.0', '26.13.1', 'true', '26.13.1'),
            ('26.13.1', '26.13.1', 'false', '26.13.1'),
            ('26.14.0', '26.13.1', 'false', '26.14.0'),
        ]:
            with self.subTest(current=current, candidate=candidate):
                result = self.evaluate(metadata(version=candidate), current)
                self.assertEqual(result['changed'], changed)
                self.assertEqual(result['version'], selected)

    def test_cannot_cross_cycle_or_select_a_prerelease(self):
        for data in [metadata(cycle='27'), metadata(version='27.0.0'), metadata(version='26.14.0-rc.1')]:
            with self.subTest(data=data), self.assertRaises(ValueError):
                self.evaluate(data)

    def test_future_release_is_rejected(self):
        data = metadata(latest={'name': '26.14.0', 'date': '2026-11-22'})
        with self.assertRaisesRegex(ValueError, 'future-dated'):
            self.evaluate(data)

    def test_bad_dates_or_missing_result_are_rejected(self):
        cases = [None, {}, {'result': []}, metadata(latest=None)]
        for field in ['eolFrom', 'eoasFrom']:
            for value in [True, 'false', '2026-13-01', '20261121']:
                cases.append(metadata(**{field: value}))
        cases.append(metadata(latest={'name': '26.13.1', 'date': 20261110}))
        for data in cases:
            with self.subTest(data=data), self.assertRaises(ValueError):
                self.evaluate(data)

    def test_support_report_distinguishes_maintenance_from_eol(self):
        result = self.evaluate(metadata(isEoas=True, eolFrom='2028-04-30'))
        with tempfile.TemporaryDirectory() as directory:
            lifecycle.write_reports(directory, 'node', result)
            report = (Path(directory) / 'support_out.md').read_text()
            self.assertIn('title: node/26 is support out.', report)
            self.assertIn('This does not mean end of life', report)
            self.assertIn('2028-04-30', report)
            self.assertFalse((Path(directory) / 'eol.md').exists())


class CommandTests(unittest.TestCase):
    def run_command(self, data, current='26.13.0'):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        directory = root / 'version' / 'node'
        directory.mkdir(parents=True)
        (directory / 'major').write_text('26\n')
        (directory / 'strict').write_text(current + '\n')
        fixture = root / 'metadata.json'
        fixture.write_text(json.dumps(data))
        result = subprocess.run([
            sys.executable, str(SCRIPT), '--root', str(root), '--product', 'node',
            '--metadata', str(fixture), '--update', '--report-dir', str(root / 'reports'),
            '--github-output', str(root / 'output'),
        ], capture_output=True, text=True)
        return result, root

    def test_updates_only_strict_and_exports_validated_outputs(self):
        result, root = self.run_command(metadata())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((root / 'version/node/major').read_text(), '26\n')
        self.assertEqual((root / 'version/node/strict').read_text(), '26.13.1\n')
        self.assertEqual((root / 'output').read_text(),
                         'cycle=26\nversion=26.13.1\nprevious=26.13.0\nchanged=true\neol=false\nsupport_out=false\n')

    def test_stale_metadata_does_not_downgrade(self):
        result, root = self.run_command(metadata(), current='26.14.0')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((root / 'version/node/strict').read_text(), '26.14.0\n')
        self.assertIn('changed=false\n', (root / 'output').read_text())

    def test_invalid_metadata_cannot_partially_update_pin_or_outputs(self):
        for data in [metadata(isEol='false'), metadata(version='26.14.0\neol=true')]:
            with self.subTest(data=data):
                result, root = self.run_command(data)
                self.assertEqual(result.returncode, 1)
                self.assertIn('ERROR:', result.stderr)
                self.assertEqual((root / 'version/node/strict').read_text(), '26.13.0\n')
                self.assertFalse((root / 'output').exists())
                self.assertFalse((root / 'reports').exists())


if __name__ == '__main__':
    unittest.main()
