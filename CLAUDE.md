# CLAUDE.md

Instructions for Claude Code when working in this repository.

## Releases and changelog

- Releases are cut **only when explicitly requested**. Never bump the
  version, tag, or publish a release on your own initiative.
- Every release must have a section in [`CHANGELOG.md`](./CHANGELOG.md)
  ([Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format):
  `## [X.Y.Z] - YYYY-MM-DD` with `Added` / `Changed` / `Fixed` / `Removed`
  subsections as relevant, plus the matching link reference at the bottom
  of the file.
- Write the entry from what actually changed since the previous tag
  (`git log vPREV..HEAD`), in user-facing terms.
- When cutting a release:
  1. Bump `CFBundleShortVersionString` (and increment `CFBundleVersion`) in
     `Resources/Info.plist`.
  2. Add the `CHANGELOG.md` section for that version.
  3. Ship both in the release PR, merge it, then run
     `scripts/release.sh vX.Y.Z --upload` from an up-to-date `main`.
     The script uses the changelog section as the GitHub release notes and
     refuses to run if the section is missing.
