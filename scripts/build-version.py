#!/usr/bin/env python3
"""Build a Vortex version using its own committed Linux packaging recipe."""

import argparse
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tarfile
import tempfile


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
VERSION_PATTERN = r"[0-9]+(?:\.[0-9]+){1,3}"


class BuildError(Exception):
    pass


def git(*arguments):
    result = subprocess.run(
        ["git", "-C", str(REPOSITORY_ROOT), *arguments],
        capture_output=True, text=True, check=False,
    )
    if result.returncode:
        raise BuildError(result.stderr.strip() or "Git command failed")
    return result.stdout.strip()


def assignment(contents, name):
    # Read static packaging metadata without executing historical shell code.
    match = re.search(
        rf"^{re.escape(name)}=(?:'([^'\n]*)'|\"([^\"\n]*)\"|([^\s'\"]+))[ \t]*$",
        contents, re.MULTILINE,
    )
    if not match:
        raise BuildError(f"PKGBUILD must contain a literal {name} assignment")
    return next(value for value in match.groups() if value is not None)


def recipe_at(commit, version):
    """Find a self-contained version recipe, otherwise use the root recipe."""
    recipe_path = f"recipes/{version}"
    if not git("ls-tree", "--name-only", commit, "--", f"{recipe_path}/PKGBUILD"):
        recipe_path = "."
    contents = git("show", f"{commit}:{Path(recipe_path) / 'PKGBUILD'}")
    return contents, recipe_path


def recipes():
    """Prefer maintained version recipes, then releases, then branch history."""
    seen = set()
    head = git("rev-parse", "HEAD")
    for path in git("ls-tree", "-r", "--name-only", head, "--", "recipes").splitlines():
        match = re.fullmatch(rf"recipes/({VERSION_PATTERN})/PKGBUILD", path)
        if not match:
            continue
        version = match[1]
        contents, recipe_path = recipe_at(head, version)
        if assignment(contents, "pkgver") != version:
            raise BuildError(f"{path} does not match its version directory {version}")
        seen.add(version)
        yield version, head, contents, recipe_path

    tags = []
    for ref in git("for-each-ref", "--format=%(refname)", "refs/tags").splitlines():
        match = re.fullmatch(rf"refs/tags/v({VERSION_PATTERN})-([1-9][0-9]*)", ref)
        if match:
            tags.append((int(match[2]), match[1], ref))
    for release, version, ref in sorted(tags, reverse=True):
        if version in seen:
            continue
        commit = git("rev-parse", "--verify", f"{ref}^{{commit}}")
        contents, recipe_path = recipe_at(commit, version)
        if (assignment(contents, "pkgver"), assignment(contents, "pkgrel")) != (version, str(release)):
            raise BuildError(f"Release tag {ref} does not match its PKGBUILD version/revision")
        seen.add(version)
        yield version, commit, contents, recipe_path

    for commit in git("rev-list", "--first-parent", "HEAD").splitlines():
        try:
            contents = git("show", f"{commit}:PKGBUILD")
        except BuildError:
            continue  # History before packaging was introduced.
        version = assignment(contents, "pkgver")
        if version not in seen:
            seen.add(version)
            yield version, commit, contents, "."


def select_recipe(version, packaging_ref):
    if packaging_ref:
        commit = git("rev-parse", "--verify", "--end-of-options", f"{packaging_ref}^{{commit}}")
        contents, recipe_path = recipe_at(commit, version)
        actual_version = assignment(contents, "pkgver")
        if actual_version != version:
            raise BuildError(
                f"Packaging ref {packaging_ref} builds Vortex {actual_version}, not {version}. "
                "Use a ref containing a Linux port for the requested version."
            )
        return commit, contents, recipe_path

    for candidate_version, commit, contents, recipe_path in recipes():
        if candidate_version == version:
            return commit, contents, recipe_path
    if git("rev-parse", "--is-shallow-repository") == "true":
        raise BuildError(
            f"No Linux recipe for Vortex {version} in this shallow checkout. "
            "Run git fetch --unshallow --tags, then retry."
        )
    raise BuildError(
        f"No Linux packaging recipe for Vortex {version} in committed recipes/, "
        "local release tags or this branch's history. "
        "Use --list to see available versions, or --packaging-ref REF to select "
        "a committed Linux port on another branch/tag. An upstream tag alone is "
        "not a Linux port; older source layouts need their own patches and build recipe."
    )


def validate_recipe(commit, contents, version, build_format, recipe_path="."):
    if assignment(contents, "pkgname") != "vortex-linux":
        raise BuildError("The selected recipe is not a vortex-linux package")
    release = assignment(contents, "pkgrel")
    upstream = assignment(contents, "_upstream_commit")
    if not re.fullmatch(r"[1-9][0-9]*", release):
        raise BuildError("The selected recipe must have a positive integer pkgrel")
    if not re.fullmatch(r"[0-9a-fA-F]{40}", upstream):
        raise BuildError("The selected recipe must pin a full upstream Git commit")

    srcinfo = git("show", f"{commit}:{Path(recipe_path) / '.SRCINFO'}")
    for field, expected in (("pkgver", version), ("pkgrel", release)):
        values = re.findall(rf"^\s*{field} = (.+)$", srcinfo, re.MULTILINE)
        if values != [expected]:
            raise BuildError(f"The selected .SRCINFO {field} does not match PKGBUILD")
    sources = re.findall(r"^\s*source = (.+)$", srcinfo, re.MULTILINE)
    expected_source = f"vortex::git+https://github.com/Nexus-Mods/Vortex.git#commit={upstream}"
    if expected_source not in sources:
        raise BuildError("The selected .SRCINFO does not match the pinned upstream commit")

    required = ["scripts/build-arch-package.sh"]
    if build_format != "arch":
        required.append("scripts/build-appimage.sh")
    for path in required:
        if git("cat-file", "-t", f"{commit}:{Path(recipe_path) / path}") != "blob":
            raise BuildError(f"The selected recipe is missing {path}")
    return release, upstream


def export_source(commit, destination, recipe_path="."):
    # Export the whole snapshot: old recipes keep patches at the root, newer
    # ones stage patches/ themselves. Version directories are standalone trees
    # and must never inherit scripts, patches or assets from the modern root.
    # Local-file checksums must stay intact.
    tree = commit if recipe_path == "." else f"{commit}:{recipe_path}"
    with tempfile.TemporaryFile() as archive_file:
        subprocess.run(
            ["git", "-C", str(REPOSITORY_ROOT), "archive", "--format=tar", tree],
            stdout=archive_file, check=True,
        )
        archive_file.seek(0)
        with tarfile.open(fileobj=archive_file) as archive:
            archive.extractall(destination, filter="data")


def run_build(source, output, version, build_format):
    artifacts = output / "artifacts"
    artifacts.mkdir()
    package_directory = output / "intermediate" if build_format == "appimage" else artifacts
    package_directory.mkdir(exist_ok=True)

    def run(*arguments):
        print(f"Running: {shlex.join(str(argument) for argument in arguments)}", flush=True)
        subprocess.run([str(argument) for argument in arguments], cwd=source, check=True)

    run("bash", source / "scripts/build-arch-package.sh", package_directory)
    packages = [
        path for path in package_directory.glob(f"vortex-linux-{version}-x86_64.pkg.tar.*")
        if path.is_file() and not path.name.endswith(".sha256")
    ]
    if len(packages) != 1:
        raise BuildError(f"Expected one Vortex {version} package in {package_directory}")
    if build_format != "arch":
        run("bash", source / "scripts/build-appimage.sh", packages[0], artifacts)
    print(f"Build artifacts: {artifacts}")


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Build an older Vortex using its matching Linux recipe, patches and scripts.",
        epilog="Requires Python 3.12+ and Git; building requires Arch Linux and the selected "
               "recipe's dependencies. Only committed files are used. No release is published.",
    )
    parser.add_argument("--version", help="Exact Vortex version, e.g. 2.7.1 or v2.7.1")
    parser.add_argument("--packaging-ref", help="Select recipes/VERSION or the root recipe at a local Git ref")
    parser.add_argument("--format", choices=("arch", "appimage", "both"), default="both")
    parser.add_argument("--output-dir", type=Path, help="Empty output directory (default: dist/versions/VERSION)")
    parser.add_argument("--prepare-only", action="store_true", help="Export the recipe without downloading or building")
    parser.add_argument("--list", action="store_true", help="List committed version recipes, local releases and historical ports")
    args = parser.parse_args(argv)

    if args.list:
        if args.version or args.packaging_ref or args.output_dir or args.prepare_only:
            parser.error("--list cannot be combined with build options")
        print("Vortex version\tPackage revision\tPackaging commit\tRecipe path")
        for version, commit, contents, recipe_path in sorted(
            recipes(), key=lambda recipe: tuple(int(part) for part in recipe[0].split(".")), reverse=True,
        ):
            print(f"{version}\t{version}-{assignment(contents, 'pkgrel')}\t{commit}\t{recipe_path}")
        if git("rev-parse", "--is-shallow-repository") == "true":
            print("History is shallow; run git fetch --unshallow --tags for older recipes.", file=sys.stderr)
        return 0

    if not args.version:
        parser.error("--version is required unless using --list")
    version = args.version.removeprefix("v")
    if not re.fullmatch(VERSION_PATTERN, version):
        parser.error("--version must be a stable numeric version, e.g. 2.7.1")
    if not args.prepare_only and os.geteuid() == 0:
        raise BuildError("Build as an unprivileged user; makepkg cannot run as root")

    commit, contents, recipe_path = select_recipe(version, args.packaging_ref)
    release, upstream = validate_recipe(commit, contents, version, args.format, recipe_path)
    output = (args.output_dir or REPOSITORY_ROOT / "dist/versions" / version).absolute()
    if any(character in str(output) for character in "\r\n"):
        raise BuildError("Output directory cannot contain line breaks")
    if output.is_symlink() or (output.exists() and (not output.is_dir() or any(output.iterdir()))):
        raise BuildError(f"Output directory must be empty: {output}")
    output.mkdir(parents=True, exist_ok=True)
    output = output.resolve()
    source = output / "source"
    export_source(commit, source, recipe_path)

    manifest = {
        "package_version": version,
        "package_revision": f"{version}-{release}",
        "packaging_commit": commit,
        "recipe_path": recipe_path,
        "upstream_commit": upstream,
        "format": args.format,
    }
    (output / "build-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    if os.environ.get("GITHUB_OUTPUT"):
        values = {**manifest, "source_directory": str(source), "output_directory": str(output)}
        with open(os.environ["GITHUB_OUTPUT"], "a") as stream:
            for name, value in values.items():
                stream.write(f"{name}={value}\n")

    print(f"Prepared Vortex {version}-{release} from packaging commit {commit}")
    print(f"Upstream commit: {upstream}")
    print(f"Recipe path: {recipe_path}")
    print(f"Packaging source: {source}")
    print(f"Build manifest: {output / 'build-manifest.json'}", flush=True)
    if args.prepare_only:
        print("Preparation only; patch compatibility and build success have not been checked.")
    else:
        run_build(source, output, version, args.format)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (BuildError, OSError, subprocess.CalledProcessError, tarfile.TarError) as error:
        print(f"Error: {error}", file=sys.stderr)
        sys.exit(1)
