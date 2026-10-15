"""Check the AppStream metadata template that build-appimage.sh bundles."""

from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ElementTree


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
METAINFO_PATH = REPOSITORY_ROOT / 'appimage/com.nexusmods.vortex.metainfo.xml'
BUILD_SCRIPT = REPOSITORY_ROOT / 'scripts/build-appimage.sh'
RELEASE_REPOSITORY = 'Arkazzae/VortexLinux'


def render(package_revision='2.8.2-3', release_date='2026-10-15'):
    """Substitute the placeholders the same way build-appimage.sh does."""
    return (
        METAINFO_PATH.read_text()
        .replace('@PACKAGE_REVISION@', package_revision)
        .replace('@RELEASE_DATE@', release_date)
    )


class AppImageMetainfoTest(unittest.TestCase):
    def test_component_matches_bundled_desktop_entry(self):
        component = ElementTree.fromstring(render())
        self.assertEqual(component.get('type'), 'desktop-application')
        self.assertEqual(component.findtext('id'), 'com.nexusmods.vortex')
        launchable = component.find('launchable')
        self.assertEqual(launchable.get('type'), 'desktop-id')
        self.assertEqual(launchable.text, 'com.nexusmods.vortex.desktop')
        self.assertEqual(component.findtext('project_license'), 'GPL-3.0-only')
        self.assertIn('x-scheme-handler/nxm', [
            element.text for element in component.findall('provides/mediatype')
        ])

    def test_urls_point_at_this_repository(self):
        component = ElementTree.fromstring(render())
        urls = {url.get('type'): url.text for url in component.findall('url')}
        for url_type in ('homepage', 'bugtracker', 'vcs-browser'):
            self.assertTrue(
                urls[url_type].startswith(f'https://github.com/{RELEASE_REPOSITORY}'),
                urls[url_type],
            )

    def test_release_placeholders_render_the_package_revision(self):
        self.assertIn('@PACKAGE_REVISION@', METAINFO_PATH.read_text())
        rendered = render('2.8.2-3', '2026-10-15')
        self.assertIsNone(re.search(r'@[A-Z_]+@', rendered))
        release = ElementTree.fromstring(rendered).find('releases/release')
        self.assertEqual(release.get('version'), '2.8.2-3')
        self.assertEqual(release.get('date'), '2026-10-15')
        self.assertEqual(
            release.find('url').text,
            f'https://github.com/{RELEASE_REPOSITORY}/releases/tag/v2.8.2-3',
        )

    def test_build_script_embeds_matching_update_information(self):
        script = BUILD_SCRIPT.read_text()
        self.assertIn(f'GITHUB_REPOSITORY:-{RELEASE_REPOSITORY}', script)
        self.assertIn('|latest|Vortex-*-x86_64.AppImage.zsync"', script)
        self.assertIn('--updateinformation "$update_information"', script)
        self.assertIn('appimage_zsync=', script)

    def test_rendered_metadata_validates(self):
        if shutil.which('appstreamcli') is None:
            self.skipTest('appstreamcli is not installed')
        with tempfile.TemporaryDirectory() as directory:
            rendered = Path(directory) / METAINFO_PATH.name
            rendered.write_text(render())
            result = subprocess.run(
                ['appstreamcli', 'validate', '--no-net', str(rendered)],
                capture_output=True,
                text=True,
            )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
