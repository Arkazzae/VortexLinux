#!/usr/bin/env python3
"""Read and update CHANGELOG.md for the release workflow.

The changelog keeps one ``## <package revision> - <date>`` section per release,
newest first, below an optional ``## Unreleased`` section. ``notes`` prints a
section for the GitHub release body and ``add-upstream-update`` writes the entry
for an automatic Vortex update, which has no hand-written notes.
"""

import argparse
import datetime as dt
from pathlib import Path
import re
import sys


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PATH = REPOSITORY_ROOT / 'CHANGELOG.md'
REVISION_PATTERN = r'\d+(?:\.\d+){1,3}-\d+'
HEADING = re.compile(rf'^## (?P<revision>{REVISION_PATTERN})(?: - (?P<date>\d{{4}}-\d{{2}}-\d{{2}}))?\s*$')
UNRELEASED = re.compile(r'^## Unreleased\s*$')


class ChangelogError(Exception):
    pass


def sections(text):
    """Yield (revision, date, body) for every release section, in file order."""
    revision = date = None
    body = []
    for line in text.splitlines():
        match = HEADING.match(line)
        if match or line.startswith('## ') or line.startswith('# '):
            if revision is not None:
                yield revision, date, '\n'.join(body).strip()
            revision = match.group('revision') if match else None
            date = match.group('date') if match else None
            body = []
            continue
        body.append(line)
    if revision is not None:
        yield revision, date, '\n'.join(body).strip()


def release_notes(text, revision):
    for found, _date, body in sections(text):
        if found == revision:
            if not body:
                raise ChangelogError(f'The CHANGELOG.md section for {revision} is empty')
            return body
    raise ChangelogError(f'CHANGELOG.md has no "## {revision}" section')


def upstream_update_entry(revision, vortex_version, upstream_commit, previous):
    unchanged = (
        f'The Linux patches and packaging are unchanged since {previous}.'
        if previous
        else 'The Linux patches and packaging are unchanged.'
    )
    return (
        f'Automatic update to Vortex {vortex_version}, published after the usual checks passed. '
        f'{unchanged} Upstream commit `{upstream_commit}`.'
    )


def add_upstream_update(text, revision, vortex_version, upstream_commit, date):
    if not re.fullmatch(REVISION_PATTERN, revision):
        raise ChangelogError(f'Not a package revision: {revision}')
    if not re.fullmatch(r'[0-9a-f]{40}', upstream_commit):
        raise ChangelogError(f'Not a full lowercase commit SHA: {upstream_commit}')
    for found, _date, body in sections(text):
        if found == revision:
            if not body:
                raise ChangelogError(f'The existing "## {revision}" section in CHANGELOG.md is empty')
            # Hand-written notes for this revision win over the generated entry.
            return text
    releases = [found for found, _date, _body in sections(text)]
    entry = upstream_update_entry(
        revision, vortex_version, upstream_commit, releases[0] if releases else None
    )
    section = f'## {revision} - {date}\n\n{entry}\n'

    lines = text.splitlines(keepends=True)
    for index, line in enumerate(lines):
        if UNRELEASED.match(line):
            # Keep the Unreleased notes, insert the automatic release below them.
            end = next(
                (i for i in range(index + 1, len(lines)) if lines[i].startswith('## ')),
                len(lines),
            )
            return ''.join(lines[:end]).rstrip('\n') + '\n\n' + section + '\n' + ''.join(lines[end:])
    for index, line in enumerate(lines):
        if HEADING.match(line):
            return ''.join(lines[:index]) + section + '\n' + ''.join(lines[index:])
    return text.rstrip('\n') + '\n\n' + section


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--path', type=Path, default=DEFAULT_PATH, help='changelog file')
    commands = parser.add_subparsers(dest='command', required=True)

    notes = commands.add_parser('notes', help='print the release notes for a package revision')
    notes.add_argument('revision', help='package revision such as 2.8.2-3')

    update = commands.add_parser(
        'add-upstream-update', help='add the entry for an automatic Vortex update'
    )
    update.add_argument('--revision', required=True, help='new package revision')
    update.add_argument('--vortex', required=True, help='new Vortex version')
    update.add_argument('--commit', required=True, help='full upstream commit SHA')
    update.add_argument(
        '--date', default=dt.date.today().isoformat(), help='release date (YYYY-MM-DD)'
    )

    args = parser.parse_args(argv)
    text = args.path.read_text(encoding='utf-8')
    try:
        if args.command == 'notes':
            print(release_notes(text, args.revision))
        else:
            updated = add_upstream_update(text, args.revision, args.vortex, args.commit, args.date)
            if updated == text:
                print(f'Keeping the existing {args.revision} section in {args.path}')
            else:
                args.path.write_text(updated, encoding='utf-8')
                print(f'Added the automatic update entry for {args.revision} to {args.path}')
    except ChangelogError as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
