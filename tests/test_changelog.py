"""Exercise the changelog helper the release workflow runs."""

import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = REPOSITORY_ROOT / 'scripts/changelog.py'
SPEC = importlib.util.spec_from_file_location('changelog', SCRIPT_PATH)
CHANGELOG = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHANGELOG)

COMMIT = 'e136d9c83492580b6a9b5d9e723964fa3dd56bfd'
SAMPLE = '''# Changelog

Intro paragraph.

## Unreleased

- Pending change.

## 2.8.2-3 - 2026-10-15

- Gear Lever can update the AppImage (#13).
- Config deployment logs its target (#11).

## 2.8.2-2 - 2026-10-14

- Extension config paths map into the Proton profile.
'''
RELEASED_SAMPLE = SAMPLE.replace('## Unreleased\n\n- Pending change.\n\n', '## Unreleased\n\n')


def revisions(text):
    return [revision for revision, _date, _body in CHANGELOG.sections(text)]


class ReleaseNotesTest(unittest.TestCase):
    def test_returns_only_the_requested_section(self):
        notes = CHANGELOG.release_notes(SAMPLE, '2.8.2-3')
        self.assertEqual(
            notes,
            '- Gear Lever can update the AppImage (#13).\n- Config deployment logs its target (#11).',
        )

    def test_rejects_missing_and_empty_sections(self):
        with self.assertRaisesRegex(CHANGELOG.ChangelogError, 'no "## 2.9.0-1"'):
            CHANGELOG.release_notes(SAMPLE, '2.9.0-1')
        with self.assertRaisesRegex(CHANGELOG.ChangelogError, 'empty'):
            CHANGELOG.release_notes('## 2.9.0-1 - 2026-11-01\n\n## 2.8.2-3\n\n- x\n', '2.9.0-1')

    def test_repository_changelog_covers_the_pinned_revision(self):
        pkgbuild = (REPOSITORY_ROOT / 'PKGBUILD').read_text()
        version = next(l.split('=', 1)[1] for l in pkgbuild.splitlines() if l.startswith('pkgver='))
        release = next(l.split('=', 1)[1] for l in pkgbuild.splitlines() if l.startswith('pkgrel='))
        text = (REPOSITORY_ROOT / 'CHANGELOG.md').read_text()
        # A pkgrel bumped by hand keeps its notes under Unreleased until
        # prepare-release files them under the new revision, as release() does.
        text = CHANGELOG.release(text, f'{version}-{release}', '2026-01-01')
        self.assertTrue(CHANGELOG.release_notes(text, f'{version}-{release}'))
        # Newest release first, so the workflow can name the previous revision.
        self.assertEqual(revisions(text)[0], f'{version}-{release}')


class ReleaseTest(unittest.TestCase):
    def test_moves_unreleased_notes_into_the_new_section(self):
        updated = CHANGELOG.release(SAMPLE, '2.8.2-4', '2026-10-16')
        self.assertEqual(revisions(updated), ['2.8.2-4', '2.8.2-3', '2.8.2-2'])
        self.assertEqual(CHANGELOG.release_notes(updated, '2.8.2-4'), '- Pending change.')
        self.assertIn('## Unreleased\n\n## 2.8.2-4 - 2026-10-16\n\n- Pending change.\n\n## 2.8.2-3', updated)
        self.assertTrue(updated.endswith('- Extension config paths map into the Proton profile.\n'))

    def test_keeps_a_hand_written_section_and_refuses_an_empty_release(self):
        self.assertEqual(CHANGELOG.release(SAMPLE, '2.8.2-3', '2026-10-16'), SAMPLE)
        with self.assertRaisesRegex(CHANGELOG.ChangelogError, 'Nothing to release'):
            CHANGELOG.release(RELEASED_SAMPLE, '2.8.2-4', '2026-10-16')
        with self.assertRaisesRegex(CHANGELOG.ChangelogError, 'empty'):
            CHANGELOG.release('## 2.8.2-4 - 2026-10-16\n\n## 2.8.2-3\n\n- x\n', '2.8.2-4', '2026-10-16')
        with self.assertRaisesRegex(CHANGELOG.ChangelogError, 'package revision'):
            CHANGELOG.release(SAMPLE, 'v2.8.2-4', '2026-10-16')


class UpstreamUpdateTest(unittest.TestCase):
    def test_takes_pending_notes_with_the_automatic_update(self):
        updated = CHANGELOG.add_upstream_update(SAMPLE, '2.8.3-1', '2.8.3', COMMIT, '2026-10-20')
        self.assertEqual(revisions(updated), ['2.8.3-1', '2.8.2-3', '2.8.2-2'])
        notes = CHANGELOG.release_notes(updated, '2.8.3-1')
        self.assertIn('Automatic update to Vortex 2.8.3', notes)
        self.assertIn(f'`{COMMIT}`', notes)
        self.assertIn('also includes the changes recorded below.\n\n- Pending change.', notes)
        self.assertNotIn('unchanged', notes)
        self.assertIn('## Unreleased\n\n## 2.8.3-1 - 2026-10-20\n', updated)
        self.assertTrue(updated.endswith('- Extension config paths map into the Proton profile.\n'))

    def test_says_nothing_else_changed_when_unreleased_is_empty(self):
        updated = CHANGELOG.add_upstream_update(
            RELEASED_SAMPLE, '2.8.3-1', '2.8.3', COMMIT, '2026-10-20'
        )
        notes = CHANGELOG.release_notes(updated, '2.8.3-1')
        self.assertIn('unchanged since 2.8.2-3', notes)
        self.assertNotIn('also includes', notes)

    def test_works_without_an_unreleased_section_or_releases(self):
        bare = '# Changelog\n\nIntro.\n'
        updated = CHANGELOG.add_upstream_update(bare, '2.8.3-1', '2.8.3', COMMIT, '2026-10-20')
        self.assertIn('## 2.8.3-1 - 2026-10-20', updated)
        self.assertIn('are unchanged.', updated)
        only_releases = '## 2.8.2-3 - 2026-10-15\n\n- x\n'
        updated = CHANGELOG.add_upstream_update(
            only_releases, '2.8.3-1', '2.8.3', COMMIT, '2026-10-20'
        )
        self.assertTrue(updated.startswith('## 2.8.3-1 - 2026-10-20\n'))
        self.assertIn('\n\n## 2.8.2-3 - 2026-10-15\n', updated)

    def test_keeps_hand_written_notes_for_the_same_revision(self):
        # A maintainer may describe the upcoming version before the bot publishes it.
        self.assertEqual(
            CHANGELOG.add_upstream_update(SAMPLE, '2.8.2-3', '2.8.2', COMMIT, '2026-10-20'),
            SAMPLE,
        )
        with self.assertRaisesRegex(CHANGELOG.ChangelogError, 'empty'):
            CHANGELOG.add_upstream_update(
                '## 2.8.3-1 - 2026-10-20\n\n## 2.8.2-3\n\n- x\n', '2.8.3-1', '2.8.3', COMMIT, '2026-10-20'
            )

    def test_refuses_bad_input(self):
        with self.assertRaisesRegex(CHANGELOG.ChangelogError, 'commit SHA'):
            CHANGELOG.add_upstream_update(SAMPLE, '2.8.3-1', '2.8.3', 'abc', '2026-10-20')
        with self.assertRaisesRegex(CHANGELOG.ChangelogError, 'package revision'):
            CHANGELOG.add_upstream_update(SAMPLE, 'v2.8.3', '2.8.3', COMMIT, '2026-10-20')


class CommandLineTest(unittest.TestCase):
    def run_script(self, *arguments):
        return subprocess.run(
            [sys.executable, str(SCRIPT_PATH), *arguments], capture_output=True, text=True
        )

    def test_release_update_and_notes_round_trip(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'CHANGELOG.md'
            path.write_text(SAMPLE)
            result = self.run_script('--path', str(path), 'notes', '2.8.2-2')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                result.stdout, '- Extension config paths map into the Proton profile.\n'
            )

            result = self.run_script(
                '--path', str(path), 'release', '--revision', '2.8.2-4', '--date', '2026-10-16'
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('Released', result.stdout)
            result = self.run_script('--path', str(path), 'notes', '2.8.2-4')
            self.assertEqual(result.stdout, '- Pending change.\n')
            # Running it again is a no-op, which lets the workflow retry safely.
            result = self.run_script(
                '--path', str(path), 'release', '--revision', '2.8.2-4', '--date', '2026-10-17'
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('Keeping', result.stdout)
            result = self.run_script('--path', str(path), 'release', '--revision', '2.8.2-5')
            self.assertEqual(result.returncode, 1)
            self.assertIn('Nothing to release', result.stderr)

            result = self.run_script(
                '--path', str(path), 'add-upstream-update',
                '--revision', '2.8.3-1', '--vortex', '2.8.3', '--commit', COMMIT,
                '--date', '2026-10-20',
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            result = self.run_script('--path', str(path), 'notes', '2.8.3-1')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('unchanged since 2.8.2-4', result.stdout)
            result = self.run_script('--path', str(path), 'notes', '9.9.9-9')
            self.assertEqual(result.returncode, 1)
            self.assertIn('no "## 9.9.9-9" section', result.stderr)


if __name__ == '__main__':
    unittest.main()
