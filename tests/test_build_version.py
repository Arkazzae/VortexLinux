#!/usr/bin/env python3
"""Offline integration tests for building a historical packaging snapshot.

Run with: python3 -m unittest discover -s tests -v
"""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


BUILD_VERSION = Path(__file__).resolve().parents[1] / "scripts/build-version.py"
UPSTREAM_COMMIT = "1234567890abcdef1234567890abcdef12345678"

# These tiny build scripts record the selected snapshot and produce only dummy
# artifacts. They exercise orchestration without invoking makepkg or networking.
FAKE_BUILD_SCRIPT = r'''#!/usr/bin/env bash
set -euo pipefail
python3 - "$0" "$@" <<'PY'
import json
import os
from pathlib import Path
import re
import sys

script = Path(sys.argv[1]).resolve()
source = script.parents[1]
args = sys.argv[2:]
version = re.search(r"^pkgver=(.+)$", (source / "PKGBUILD").read_text(), re.M)[1]
with open(os.environ["TEST_BUILD_LOG"], "a") as log:
    log.write(json.dumps({"script": str(script), "args": args,
                          "cwd": os.getcwd(),
                          "marker": (source / "patches/fix.patch").read_text()}) + "\n")
if script.name == "build-arch-package.sh":
    output = Path(args[0])
    output.mkdir(parents=True, exist_ok=True)
    name = f"vortex-linux-{version}-x86_64.pkg.tar.zst"
    (output / name).write_text("dummy Arch package\n")
    (output / (name + ".sha256")).write_text("dummy checksum\n")
else:
    assert len(args) == 2, args
    assert Path(args[0]).is_file(), args[0]
    output = Path(args[1])
    output.mkdir(parents=True, exist_ok=True)
    (output / f"Vortex-{version}-x86_64.AppImage").write_text("dummy AppImage\n")
PY
'''


class BuildVersionTests(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory(prefix="vortex-version-test-")
        self.addCleanup(self.temporary_directory.cleanup)
        self.directory = Path(self.temporary_directory.name)
        self.repository = self.directory / "repository"
        self.repository.mkdir()
        self.environment = os.environ.copy()
        # Do not inherit the real workflow's output files or Git repository.
        for key in ("GITHUB_OUTPUT", "GITHUB_STEP_SUMMARY", "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"):
            self.environment.pop(key, None)
        self.environment.update({
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": os.devnull,
            "TEST_BUILD_LOG": str(self.directory / "build-log.jsonl"),
        })
        self.git("init", "--quiet")
        self.git("config", "user.name", "Version Test")
        self.git("config", "user.email", "version-test@example.invalid")
        self.write("scripts/build-version.py", BUILD_VERSION.read_text())
        for name in ("build-arch-package.sh", "build-appimage.sh"):
            self.write("scripts/" + name, FAKE_BUILD_SCRIPT)
            (self.repository / "scripts" / name).chmod(0o755)
        self.recipe("2.7.1", "2")
        self.write("patches/fix.patch", "original older patch\n")
        self.old_commit = self.commit("Older port")
        self.git("tag", "older-port", self.old_commit)
        self.write("patches/fix.patch", "latest older patch\n")
        self.latest_old_commit = self.commit("Fix older port without changing PKGBUILD")
        self.recipe("2.8.0", "1")
        self.write("patches/fix.patch", "current patch\n")
        self.current_commit = self.commit("Current port")

    def write(self, relative_path, contents):
        path = self.repository / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents)
        return path

    def recipe(self, version, revision, recipe_path="."):
        self.write(Path(recipe_path) / "PKGBUILD", (
            "pkgname=vortex-linux\n"
            f"pkgver={version}\n"
            f"pkgrel={revision}\n"
            f"_upstream_commit='{UPSTREAM_COMMIT}'\n"
            "source=(\"vortex::git+https://github.com/Nexus-Mods/Vortex.git#commit=$_upstream_commit\")\n"
        ))
        self.write(Path(recipe_path) / ".SRCINFO", (
            "pkgbase = vortex-linux\n"
            f"\tpkgver = {version}\n"
            f"\tpkgrel = {revision}\n"
            f"\tsource = vortex::git+https://github.com/Nexus-Mods/Vortex.git#commit={UPSTREAM_COMMIT}\n"
            "pkgname = vortex-linux\n"
        ))

    def maintained_recipe(self, version="1.16.9", revision="1"):
        recipe_path = Path("recipes") / version
        self.recipe(version, revision, recipe_path)
        self.write(recipe_path / "patches/fix.patch", f"maintained {version} patch\n")
        for name in ("build-arch-package.sh", "build-appimage.sh"):
            self.write(recipe_path / "scripts" / name, FAKE_BUILD_SCRIPT).chmod(0o755)
        self.write(recipe_path / "appimage/AppRun", "#!/bin/sh\necho legacy AppRun\n").chmod(0o755)
        return recipe_path

    def git(self, *arguments):
        result = subprocess.run(
            ["git", *arguments], cwd=self.repository, env=self.environment,
            text=True, capture_output=True, check=True,
        )
        return result.stdout.strip()

    def commit(self, message):
        self.git("add", ".")
        self.git("commit", "--quiet", "-m", message)
        return self.git("rev-parse", "HEAD")

    def run_builder(self, *arguments, success=True, environment=None):
        result = subprocess.run(
            [sys.executable, str(self.repository / "scripts/build-version.py"), *arguments],
            # Deliberately run from elsewhere: paths must be anchored to the repo.
            cwd=self.directory, env=environment or self.environment,
            text=True, capture_output=True,
        )
        details = f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        if success:
            self.assertEqual(result.returncode, 0, details)
        else:
            self.assertNotEqual(result.returncode, 0, details)
        return result

    def output(self, version="2.7.1"):
        return self.repository / "dist/versions" / version

    def manifest(self, output=None):
        return json.loads(((output or self.output()) / "build-manifest.json").read_text())

    def test_selects_latest_matching_snapshot_and_preserves_dirty_worktree(self):
        dirty_recipe = (self.repository / "PKGBUILD").read_text().replace("2.8.0", "9.9.9")
        self.write("PKGBUILD", dirty_recipe)
        self.write("patches/fix.patch", "uncommitted patch\n")
        self.write("untracked-private-file", "must never enter snapshot\n")
        status_before = self.git("status", "--porcelain")

        self.run_builder("--version", "v2.7.1", "--prepare-only")

        snapshot = self.output() / "source"
        self.assertIn("pkgver=2.7.1\n", (snapshot / "PKGBUILD").read_text())
        self.assertEqual((snapshot / "patches/fix.patch").read_text(), "latest older patch\n")
        self.assertFalse((snapshot / "untracked-private-file").exists())
        self.assertFalse((snapshot / ".git").exists())
        self.assertEqual((self.repository / "PKGBUILD").read_text(), dirty_recipe)
        self.assertEqual(self.git("rev-parse", "HEAD"), self.current_commit)
        # The generated dist directory may be untracked, so compare only the
        # preexisting paths rather than the entire post-build status output.
        self.assertTrue(set(status_before.splitlines()).issubset(self.git("status", "--porcelain").splitlines()))
        manifest = self.manifest()
        self.assertEqual(manifest["package_version"], "2.7.1")
        self.assertEqual(manifest["package_revision"], "2.7.1-2")
        self.assertEqual(manifest["packaging_commit"], self.latest_old_commit)
        self.assertEqual(manifest["recipe_path"], ".")
        self.assertEqual(manifest["upstream_commit"], UPSTREAM_COMMIT)
        self.assertEqual(manifest["format"], "both")
        self.assertFalse((self.directory / "build-log.jsonl").exists())

    def test_explicit_tag_selects_exact_older_revision(self):
        output = self.directory / "custom-output"
        self.run_builder("--version", "2.7.1", "--packaging-ref", "older-port",
                         "--output-dir", str(output), "--prepare-only")
        self.assertEqual(self.manifest(output)["packaging_commit"], self.old_commit)
        self.assertEqual((output / "source/patches/fix.patch").read_text(), "original older patch\n")

    def test_maintained_recipe_exports_only_its_own_committed_files(self):
        recipe_path = self.maintained_recipe()
        self.write("modern-only-file", "current port assets\n")
        recipe_commit = self.commit("Maintain the legacy port beside the current one")
        self.write(recipe_path / "patches/fix.patch", "uncommitted legacy patch\n")
        self.write(recipe_path / "private-untracked-file", "local only\n")

        self.run_builder("--version", "v1.16.9", "--prepare-only")

        output = self.output("1.16.9")
        snapshot = output / "source"
        manifest = self.manifest(output)
        self.assertEqual(manifest["recipe_path"], "recipes/1.16.9")
        self.assertEqual(manifest["packaging_commit"], recipe_commit)
        self.assertEqual(manifest["package_version"], "1.16.9")
        self.assertEqual(manifest["package_revision"], "1.16.9-1")
        self.assertIn("pkgver=1.16.9\n", (snapshot / "PKGBUILD").read_text())
        self.assertEqual((snapshot / "patches/fix.patch").read_text(), "maintained 1.16.9 patch\n")
        self.assertEqual((snapshot / "appimage/AppRun").stat().st_mode & 0o777, 0o755)
        self.assertFalse((snapshot / "modern-only-file").exists())
        self.assertFalse((snapshot / "recipes").exists())
        self.assertFalse((snapshot / "private-untracked-file").exists())
        self.assertIn("pkgver=2.8.0\n", (self.repository / "PKGBUILD").read_text())
        self.assertEqual((self.repository / recipe_path / "patches/fix.patch").read_text(), "uncommitted legacy patch\n")

    def test_maintained_recipe_precedes_historical_root_release(self):
        self.git("tag", "v2.7.1-2", self.old_commit)
        self.maintained_recipe("2.7.1", "3")
        recipe_commit = self.commit("Update the maintained older port")

        self.run_builder("--version", "2.7.1", "--prepare-only")

        self.assertEqual(self.manifest()["packaging_commit"], recipe_commit)
        self.assertEqual(self.manifest()["package_revision"], "2.7.1-3")
        self.assertEqual(self.manifest()["recipe_path"], "recipes/2.7.1")

    def test_explicit_ref_selects_the_maintained_recipe_at_that_revision(self):
        recipe_path = self.maintained_recipe()
        old_recipe_commit = self.commit("Original maintained legacy port")
        self.git("tag", "legacy-snapshot", old_recipe_commit)
        self.recipe("1.16.9", "2", recipe_path)
        self.write(recipe_path / "patches/fix.patch", "newer maintained legacy patch\n")
        self.commit("Update legacy recipe")

        self.run_builder("--version", "1.16.9", "--packaging-ref", "legacy-snapshot", "--prepare-only")

        output = self.output("1.16.9")
        self.assertEqual(self.manifest(output)["packaging_commit"], old_recipe_commit)
        self.assertEqual(self.manifest(output)["recipe_path"], "recipes/1.16.9")
        self.assertEqual((output / "source/patches/fix.patch").read_text(), "maintained 1.16.9 patch\n")

    def test_explicit_root_release_overrides_current_maintained_recipe(self):
        self.maintained_recipe("2.7.1", "3")
        self.commit("Maintain the older port separately")

        self.run_builder("--version", "2.7.1", "--packaging-ref", "older-port", "--prepare-only")

        self.assertEqual(self.manifest()["packaging_commit"], self.old_commit)
        self.assertEqual(self.manifest()["recipe_path"], ".")

    def test_list_includes_only_committed_version_recipes_without_duplicates(self):
        self.maintained_recipe()
        self.maintained_recipe("2.7.1", "3")
        self.git("tag", "v2.7.1-2", self.old_commit)
        recipe_commit = self.commit("Maintain multiple ports together")
        self.maintained_recipe("1.15.0")

        result = self.run_builder("--list")

        rows = [line.split("\t") for line in result.stdout.splitlines()[1:]]
        self.assertEqual([row[0] for row in rows], ["2.8.0", "2.7.1", "1.16.9"])
        self.assertEqual(rows[1], ["2.7.1", "2.7.1-3", recipe_commit, "recipes/2.7.1"])
        self.assertEqual(rows[2], ["1.16.9", "1.16.9-1", recipe_commit, "recipes/1.16.9"])
        self.run_builder("--version", "1.15.0", "--prepare-only", success=False)
        self.assertFalse(self.output("1.15.0").exists())

    def test_maintained_recipe_version_must_match_its_directory(self):
        recipe_path = self.maintained_recipe()
        self.recipe("1.16.8", "1", recipe_path)
        self.commit("Legacy recipe in the wrong version directory")

        result = self.run_builder("--version", "1.16.9", "--prepare-only", success=False)

        self.assertIn("1.16.9", result.stderr)
        self.assertFalse(self.output("1.16.9").exists())

    def test_maintained_recipe_srcinfo_is_validated_inside_its_directory(self):
        recipe_path = self.maintained_recipe()
        srcinfo = self.repository / recipe_path / ".SRCINFO"
        srcinfo.write_text(srcinfo.read_text().replace("pkgrel = 1", "pkgrel = 2"))
        self.commit("Mismatched legacy metadata")

        result = self.run_builder("--version", "1.16.9", "--prepare-only", success=False)

        self.assertIn("SRCINFO", result.stderr)
        self.assertFalse(self.output("1.16.9").exists())

    def test_maintained_recipe_cannot_borrow_missing_scripts_from_root(self):
        recipe_path = self.maintained_recipe()
        (self.repository / recipe_path / "scripts/build-appimage.sh").unlink()
        self.commit("Legacy recipe supports only Arch packages")

        self.run_builder("--version", "1.16.9", "--prepare-only", success=False)
        self.assertFalse(self.output("1.16.9").exists())
        self.run_builder("--version", "1.16.9", "--format", "arch", "--prepare-only")
        self.assertFalse((self.output("1.16.9") / "source/scripts/build-appimage.sh").exists())

    @unittest.skipIf(os.geteuid() == 0, "Actual builds intentionally reject root")
    def test_maintained_recipe_builds_with_its_own_scripts_and_assets(self):
        self.maintained_recipe()
        for name in ("build-arch-package.sh", "build-appimage.sh"):
            self.write("scripts/" + name, "#!/bin/sh\nexit 99\n")
        self.commit("Separate legacy build tooling from the current port")
        workflow_output = self.directory / "legacy-github-output"
        environment = dict(self.environment, GITHUB_OUTPUT=str(workflow_output))

        self.run_builder("--version", "1.16.9", environment=environment)

        output = self.output("1.16.9")
        calls = [json.loads(line) for line in (self.directory / "build-log.jsonl").read_text().splitlines()]
        self.assertEqual(len(calls), 2)
        self.assertTrue(all(call["marker"] == "maintained 1.16.9 patch\n" for call in calls))
        self.assertTrue(all(Path(call["script"]).parents[1] == output / "source" for call in calls))
        self.assertTrue((output / "artifacts/Vortex-1.16.9-x86_64.AppImage").is_file())
        outputs = dict(line.split("=", 1) for line in workflow_output.read_text().splitlines())
        self.assertEqual(outputs["recipe_path"], "recipes/1.16.9")

    def test_release_tag_is_preferred_over_later_untagged_patches(self):
        # Work toward the next upstream release can change patches before the
        # package version is bumped; a published snapshot takes precedence.
        self.git("tag", "v2.7.1-2", self.old_commit)

        self.run_builder("--version", "2.7.1", "--prepare-only")

        self.assertEqual(self.manifest()["packaging_commit"], self.old_commit)
        self.assertEqual((self.output() / "source/patches/fix.patch").read_text(), "original older patch\n")

    def test_highest_numeric_release_tag_wins_and_annotated_tags_are_supported(self):
        self.git("tag", "v2.7.1-2", self.old_commit)
        self.recipe("2.7.1", "10")
        self.write("patches/fix.patch", "released tenth revision\n")
        release_commit = self.commit("Tenth package revision")
        self.git("tag", "-a", "v2.7.1-10", "-m", "Published tenth revision", release_commit)
        self.write("patches/fix.patch", "unreleased transition patch\n")
        self.commit("Start preparing the next upstream release")

        self.run_builder("--version", "v2.7.1", "--prepare-only")

        self.assertEqual(self.manifest()["packaging_commit"], release_commit)
        self.assertEqual(self.manifest()["package_revision"], "2.7.1-10")
        self.assertEqual((self.output() / "source/patches/fix.patch").read_text(), "released tenth revision\n")

    def test_explicit_ref_overrides_automatic_release_tag_preference(self):
        self.git("tag", "v2.8.0-1", self.current_commit)
        self.write("patches/fix.patch", "explicitly requested development patch\n")
        development_commit = self.commit("Unreleased development snapshot")

        self.run_builder("--version", "2.8.0", "--packaging-ref", "HEAD", "--prepare-only")

        output = self.output("2.8.0")
        self.assertEqual(self.manifest(output)["packaging_commit"], development_commit)
        self.assertEqual((output / "source/patches/fix.patch").read_text(), "explicitly requested development patch\n")

    def test_explicit_ref_cannot_build_a_different_version(self):
        result = self.run_builder("--version", "2.7.1", "--packaging-ref", "HEAD",
                                  "--prepare-only", success=False)
        self.assertIn("2.7.1", result.stderr)
        self.assertIn("2.8.0", result.stderr)
        self.assertFalse(self.output().exists())

    def test_unknown_ref_reports_error_without_creating_snapshot(self):
        self.run_builder("--version", "2.7.1", "--packaging-ref", "missing-port-ref",
                         "--prepare-only", success=False)
        self.assertFalse(self.output().exists())

    def test_unknown_version_explains_missing_port(self):
        result = self.run_builder("--version", "1.16.9", "--prepare-only", success=False)
        diagnostic = result.stderr.lower()
        self.assertIn("1.16.9", diagnostic)
        self.assertIn("linux", diagnostic)
        self.assertIn("port", diagnostic)
        self.assertFalse(self.output("1.16.9").exists())

    def test_malformed_versions_are_rejected(self):
        for version in ("../../outside", "2.7.1-beta.1", "2.7.1;touch bad", "$(touch bad)", ""):
            with self.subTest(version=version):
                self.run_builder("--version", version, "--prepare-only", success=False)
        self.assertFalse((self.directory / "bad").exists())
        self.assertFalse((self.repository / "dist").exists())

    def test_list_reports_available_versions_once(self):
        result = self.run_builder("--list")
        versions = [line.split("\t")[0] for line in result.stdout.splitlines()[1:]]
        self.assertEqual(versions, ["2.8.0", "2.7.1"])
        self.assertFalse((self.repository / "dist").exists())

    def test_automatic_selection_ignores_merged_side_branch_recipes(self):
        main_branch = self.git("branch", "--show-current")
        self.git("checkout", "--quiet", "-b", "side-port", self.old_commit)
        self.write("patches/fix.patch", "unrelated side branch patch\n")
        self.commit("A different older port on a side branch")
        self.git("checkout", "--quiet", main_branch)
        self.git("merge", "--quiet", "--no-edit", "-s", "ours", "side-port")

        self.run_builder("--version", "2.7.1", "--prepare-only")

        self.assertEqual(self.manifest()["packaging_commit"], self.latest_old_commit)

    def test_explicit_branch_can_select_a_backport_outside_main_history(self):
        main_branch = self.git("branch", "--show-current")
        self.git("checkout", "--quiet", "-b", "legacy-port", self.old_commit)
        self.recipe("1.16.9", "1")
        port_commit = self.commit("A separately maintained legacy port")
        self.git("checkout", "--quiet", main_branch)

        self.run_builder("--version", "1.16.9", "--prepare-only", success=False)
        self.run_builder("--version", "1.16.9", "--packaging-ref", "legacy-port", "--prepare-only")

        self.assertEqual(self.manifest(self.output("1.16.9"))["packaging_commit"], port_commit)
        self.assertEqual(self.git("rev-parse", "HEAD"), self.current_commit)

    def test_historical_flat_patch_layout_is_preserved(self):
        (self.repository / "patches/fix.patch").rename(self.repository / "0001-legacy.patch")
        flat_commit = self.commit("Recipe with patches stored in the repository root")

        self.run_builder("--version", "2.8.0", "--prepare-only")

        snapshot = self.output("2.8.0") / "source"
        self.assertEqual((snapshot / "0001-legacy.patch").read_text(), "current patch\n")
        self.assertFalse((snapshot / "patches").exists())
        self.assertEqual(self.manifest(self.output("2.8.0"))["packaging_commit"], flat_commit)

    def test_missing_version_in_shallow_checkout_explains_how_to_fetch_history(self):
        shallow = self.directory / "shallow"
        self.git("clone", "--quiet", "--depth", "1", self.repository.as_uri(), str(shallow))
        self.repository = shallow

        result = self.run_builder("--version", "2.7.1", "--prepare-only", success=False)

        self.assertIn("shallow", result.stderr.lower())
        self.assertIn("--unshallow", result.stderr)
        self.assertFalse(self.output().exists())

    def test_existing_nonempty_output_is_never_overwritten(self):
        output = self.directory / "existing-output"
        output.mkdir()
        sentinel = output / "keep-me"
        sentinel.write_text("existing user data\n")
        self.run_builder("--version", "2.7.1", "--output-dir", str(output),
                         "--prepare-only", success=False)
        self.assertEqual(sentinel.read_text(), "existing user data\n")
        self.assertEqual(list(output.iterdir()), [sentinel])

    def test_existing_empty_output_is_accepted(self):
        output = self.directory / "empty-output"
        output.mkdir()
        self.run_builder("--version", "2.7.1", "--output-dir", str(output), "--prepare-only")
        self.assertEqual(self.manifest(output)["packaging_commit"], self.latest_old_commit)

    def test_prepare_exports_workflow_outputs(self):
        workflow_output = self.directory / "github-output"
        workflow_output.write_text("existing_key=existing_value\n")
        environment = dict(self.environment, GITHUB_OUTPUT=str(workflow_output))
        self.run_builder("--version", "2.7.1", "--format", "arch", "--prepare-only",
                         environment=environment)
        outputs = dict(line.split("=", 1) for line in workflow_output.read_text().splitlines())
        self.assertEqual(outputs["existing_key"], "existing_value")
        self.assertEqual(outputs["source_directory"], str(self.output() / "source"))
        self.assertEqual(outputs["output_directory"], str(self.output()))
        self.assertEqual(outputs["package_version"], "2.7.1")
        self.assertEqual(outputs["package_revision"], "2.7.1-2")
        self.assertEqual(outputs["packaging_commit"], self.latest_old_commit)
        self.assertEqual(outputs["upstream_commit"], UPSTREAM_COMMIT)
        self.assertEqual(self.manifest()["format"], "arch")

    def test_srcinfo_must_match_the_selected_recipe(self):
        self.write(".SRCINFO", (self.repository / ".SRCINFO").read_text().replace("2.8.0", "2.7.1"))
        self.commit("Broken generated metadata")
        result = self.run_builder("--version", "2.8.0", "--prepare-only", success=False)
        self.assertIn("SRCINFO", result.stderr)

    def test_upstream_source_must_be_pinned(self):
        self.write("PKGBUILD", (self.repository / "PKGBUILD").read_text().replace(UPSTREAM_COMMIT, "main"))
        self.commit("Unpinned recipe")
        self.run_builder("--version", "2.8.0", "--prepare-only", success=False)

    @unittest.skipIf(os.geteuid() == 0, "Actual builds intentionally reject root")
    def test_build_uses_selected_scripts_and_requested_formats(self):
        for format_name in ("arch", "appimage", "both"):
            with self.subTest(format=format_name):
                log = self.directory / "build-log.jsonl"
                log.unlink(missing_ok=True)
                output = self.directory / ("build-" + format_name)
                self.run_builder("--version", "2.7.1", "--format", format_name,
                                 "--output-dir", str(output))
                calls = [json.loads(line) for line in log.read_text().splitlines()]
                self.assertEqual(len(calls), 1 if format_name == "arch" else 2)
                for call in calls:
                    self.assertEqual(Path(call["script"]).parents[1], output / "source")
                    self.assertEqual(call["marker"], "latest older patch\n")
                archive_directory = output / ("intermediate" if format_name == "appimage" else "artifacts")
                self.assertEqual(Path(calls[0]["script"]).name, "build-arch-package.sh")
                self.assertEqual(calls[0]["args"], [str(archive_directory)])
                archive = archive_directory / "vortex-linux-2.7.1-x86_64.pkg.tar.zst"
                self.assertTrue(archive.exists())
                if format_name != "arch":
                    self.assertEqual(Path(calls[1]["script"]).name, "build-appimage.sh")
                    self.assertEqual(calls[1]["args"], [str(archive), str(output / "artifacts")])
                    self.assertTrue((output / "artifacts/Vortex-2.7.1-x86_64.AppImage").exists())
                self.assertEqual(self.manifest(output)["format"], format_name)


if __name__ == "__main__":
    unittest.main()
