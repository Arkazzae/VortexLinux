#!/usr/bin/env python3
"""Read and update CHANGELOG.md for the release workflow.

Notes for pending changes go under ``## Unreleased``. Every release has a
``## <package revision> - <date>`` section below it, newest first. ``release``
moves the pending notes into the section for a package revision, ``notes``
prints a section for the GitHub release body, and ``add-upstream-update``
writes the section for an automatic Vortex update.
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


def _unreleased_span(lines):
    """Return (heading index, end index) of the Unreleased section, or None."""
    for index, line in enumerate(lines):
        if UNRELEASED.match(line):
            end = next(
                (i for i in range(index + 1, len(lines)) if lines[i].startswith('## ')),
                len(lines),
            )
            return index, end
    return None


def take_unreleased(text):
    """Return the text with an emptied Unreleased section and the notes it held."""
    lines = text.splitlines(keepends=True)
    span = _unreleased_span(lines)
    if span is None:
        return text, ''
    index, end = span
    notes = ''.join(lines[index + 1:end]).strip()
    kept = ''.join(lines[:index + 1]).rstrip('\n') + '\n\n' + ''.join(lines[end:])
    return kept, notes


def insert_section(text, section):
    """Insert a release section below Unreleased, or above the first release."""
    lines = text.splitlines(keepends=True)
    span = _unreleased_span(lines)
    if span is not None:
        _index, end = span
        return ''.join(lines[:end]).rstrip('\n') + '\n\n' + section + '\n' + ''.join(lines[end:])
    for index, line in enumerate(lines):
        if HEADING.match(line):
            return ''.join(lines[:index]) + section + '\n' + ''.join(lines[index:])
    return text.rstrip('\n') + '\n\n' + section


def _existing_body(text, revision):
    """Return the section body when the revision already has one, else None."""
    if not re.fullmatch(REVISION_PATTERN, revision):
        raise ChangelogError(f'Not a package revision: {revision}')
    for found, _date, body in sections(text):
        if found == revision:
            if not body:
                raise ChangelogError(f'The existing "## {revision}" section in CHANGELOG.md is empty')
            return body
    return None


def release(text, revision, date):
    """Move the Unreleased notes into the section for a package revision."""
    if _existing_body(text, revision) is not None:
        # Hand-written notes for this revision are already in place.
        return text
    kept, notes = take_unreleased(text)
    if not notes:
        raise ChangelogError(
            f'Nothing to release: CHANGELOG.md has no "## {revision}" section '
            'and no notes under "## Unreleased"'
        )
    return insert_section(kept, f'## {revision} - {date}\n\n{notes}\n')


def add_upstream_update(text, revision, vortex_version, upstream_commit, date):
    """Write the section for an automatic Vortex update, taking pending notes with it."""
    if not re.fullmatch(r'[0-9a-f]{40}', upstream_commit):
        raise ChangelogError(f'Not a full lowercase commit SHA: {upstream_commit}')
    if _existing_body(text, revision) is not None:
        return text
    previous = next((found for found, _date, _body in sections(text)), None)
    kept, notes = take_unreleased(text)
    entry = (
        f'Automatic update to Vortex {vortex_version}, published after the usual checks passed. '
        f'Upstream commit `{upstream_commit}`.'
    )
    if notes:
        entry += ' This release also includes the changes recorded below.\n\n' + notes
    elif previous:
        entry += f' The Linux patches and packaging are unchanged since {previous}.'
    else:
        entry += ' The Linux patches and packaging are unchanged.'
    return insert_section(kept, f'## {revision} - {date}\n\n{entry}\n')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--path', type=Path, default=DEFAULT_PATH, help='changelog file')
    commands = parser.add_subparsers(dest='command', required=True)
    today = dt.date.today().isoformat()

    notes = commands.add_parser('notes', help='print the release notes for a package revision')
    notes.add_argument('revision', help='package revision such as 2.8.2-3')

    released = commands.add_parser(
        'release', help='move the Unreleased notes into the section for a package revision'
    )
    released.add_argument('--revision', required=True, help='package revision such as 2.8.2-3')
    released.add_argument('--date', default=today, help='release date (YYYY-MM-DD)')

    update = commands.add_parser(
        'add-upstream-update', help='add the section for an automatic Vortex update'
    )
    update.add_argument('--revision', required=True, help='new package revision')
    update.add_argument('--vortex', required=True, help='new Vortex version')
    update.add_argument('--commit', required=True, help='full upstream commit SHA')
    update.add_argument('--date', default=today, help='release date (YYYY-MM-DD)')

    args = parser.parse_args(argv)
    text = args.path.read_text(encoding='utf-8')
    try:
        if args.command == 'notes':
            print(release_notes(text, args.revision))
            return 0
        if args.command == 'release':
            updated = release(text, args.revision, args.date)
            done = f'Released the Unreleased notes as {args.revision} in {args.path}'
        else:
            updated = add_upstream_update(text, args.revision, args.vortex, args.commit, args.date)
            done = f'Added the automatic update section for {args.revision} to {args.path}'
    except ChangelogError as error:
        print(error, file=sys.stderr)
        return 1
    if updated == text:
        print(f'Keeping the existing {args.revision} section in {args.path}')
    else:
        args.path.write_text(updated, encoding='utf-8')
        print(done)
    return 0


if __name__ == '__main__':
    sys.exit(main())
