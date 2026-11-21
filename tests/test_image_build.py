import sys
from pathlib import Path
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / 'scripts'))
from image_build import affected, build_args


class ImageBuildTests(unittest.TestCase):
    def test_composites_use_checkout_versions(self):
        for image in ('workbench', 'claude-codex'):
            args = dict(value.split('=', 1) for value in build_args(REPO, image))
            for argument, language in [('RUST_VERSION', 'rust'), ('GO_VERSION', 'golang'),
                                       ('PYTHON_VERSION', 'python'), ('NODE_VERSION', 'node')]:
                self.assertEqual(args[argument], (REPO / 'version' / language / 'strict').read_text().strip())
                self.assertTrue(affected(REPO, image, [f'version/{language}/strict']))
            self.assertNotIn('raw.githubusercontent.com/hinoshiba/dockerfiles/master/version',
                             (REPO / 'dockerfiles' / image / 'Dockerfile').read_text())

    def test_base_image_dependencies_and_unrelated_changes(self):
        self.assertTrue(affected(REPO, 'research', ['version/ubuntu/strict']))
        self.assertTrue(affected(REPO, 'cvemaker', ['version/python/major']))
        self.assertFalse(affected(REPO, 'research', ['version/node/strict']))
        self.assertFalse(affected(REPO, 'workbench', ['docs/README.md']))
        self.assertFalse(affected(REPO, 'node', ['dockerfiles/node-other/Dockerfile']))
        self.assertTrue(affected(REPO, 'node', ['dockerfiles/node/Dockerfile']))
        self.assertTrue(affected(REPO, 'node', ['scripts/image_build.py']))

    def test_invalid_version_fails_before_build(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            (repo / 'dockerfiles/test').mkdir(parents=True)
            (repo / 'version/node').mkdir(parents=True)
            (repo / 'dockerfiles/test/Dockerfile').write_text('FROM node:${strict}\n')
            (repo / 'version/node/strict').write_text('26.1; unexpected\n')
            with self.assertRaises(ValueError):
                build_args(repo, 'test')
