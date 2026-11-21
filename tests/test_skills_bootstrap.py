import os
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
SCRIPT = REPO / 'dockerfiles/claude-codex/setup_skills.sh'


class SkillsBootstrapTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.home = self.root / 'home with spaces'
        self.home.mkdir()
        self.source = self.root / 'source skills'
        self.source.mkdir()
        self.add_skill('one')
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.log = self.root / 'commands'
        for name in ('claude', 'codex', 'npx'):
            file = self.bin / name
            file.write_text('#!/bin/bash\necho "$0 $*" >> "$CALL_LOG"\n'
                            'case "$*" in *"plugin install"*|*"cc-plugin-codex"*) exit "${FAIL_INSTALL:-0}";; esac\n')
            file.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.home), PATH=f'{self.bin}:/usr/bin:/bin',
                        CALL_LOG=str(self.log), CODING_SKILLS_SRC=str(self.source),
                        SKILLS_BOOTSTRAP='1', SKILLS_REFRESH='0', ECC_BOOTSTRAP='0')

    def add_skill(self, name):
        ((self.source / name).resolve()).mkdir()
        (self.source / name / 'SKILL.md').write_text(f'---\nname: {name}\ndescription: fixture\n---\n')

    def run_bootstrap(self, **env):
        result = subprocess.run(['bash', str(SCRIPT)], env=dict(self.env, **env), text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def test_repo_aliases_resolve_to_same_skills_without_template(self):
        source = REPO / 'dockerfiles/claude-codex/skills'
        for alias in ('.agents/skills', '.claude/skills', '.codex/skills'):
            self.assertTrue((REPO / alias).is_symlink())
            self.assertEqual((REPO / alias).resolve(), source)
            self.assertFalse((REPO / alias / '_template').exists())
            self.assertTrue((REPO / alias / 'readable-code/SKILL.md').is_file())
            self.assertTrue((REPO / alias / 'verify-deliverables/SKILL.md').is_file())

    def test_new_image_skills_are_discovered_after_existing_bootstrap(self):
        self.run_bootstrap()
        first_calls = self.log.read_text()
        self.add_skill('two')
        self.run_bootstrap()
        self.assertEqual(first_calls, self.log.read_text())
        for directory in ('.agents/skills', '.claude/skills', '.codex/skills'):
            for name in ('one', 'two'):
                self.assertEqual((self.home / directory / name).resolve(), (self.source / name).resolve())

    def test_owned_directory_and_unrelated_broken_symlink_are_preserved(self):
        owned = self.home / '.claude/skills/one'
        owned.mkdir(parents=True)
        (owned / 'SKILL.md').write_text('user-owned')
        link = self.home / '.codex/skills/one'
        link.parent.mkdir(parents=True)
        link.symlink_to('/missing/user-owned-skill')
        self.run_bootstrap(SKILLS_REFRESH='1')
        self.assertEqual((owned / 'SKILL.md').read_text(), 'user-owned')
        self.assertEqual(list(owned.iterdir()), [owned / 'SKILL.md'])
        self.assertEqual(os.readlink(link), '/missing/user-owned-skill')

    def test_failure_does_not_record_success_and_retries(self):
        self.run_bootstrap(FAIL_INSTALL='1')
        for sentinel in ('.claude/.standard-skills.bootstrap', '.codex/.cc-plugin-codex.bootstrap'):
            self.assertFalse((self.home / sentinel).exists())
        self.run_bootstrap()
        for sentinel in ('.claude/.standard-skills.bootstrap', '.codex/.cc-plugin-codex.bootstrap'):
            self.assertTrue((self.home / sentinel).is_file())

    def test_one_blocked_directory_does_not_block_other_agents(self):
        (self.home / '.agents').write_text('user-owned file')
        self.run_bootstrap()
        self.assertEqual((self.home / '.agents').read_text(), 'user-owned file')
        for directory in ('.claude/skills', '.codex/skills'):
            self.assertTrue((self.home / directory / 'one/SKILL.md').is_file())

    def test_disabled_bootstrap_is_a_noop(self):
        self.run_bootstrap(SKILLS_BOOTSTRAP='0')
        self.assertFalse(self.log.exists())
        self.assertEqual(list(self.home.iterdir()), [])
