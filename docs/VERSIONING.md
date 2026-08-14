# COLDIRON OS — Versioning & Release Policy

## Version scheme

`MAJOR.MINOR.PATCH`, following [Semantic Versioning](https://semver.org/)
with a security-project twist:

- **MAJOR** — a change in the threat model or a breaking trust change
  (e.g. new signing key, secure boot enrollment). Currently **0**;
  v0.3.0 was the first release to meet **all** product acceptance
  criteria in [THREAT-MODEL.md](THREAT-MODEL.md) — release signing and
  the reproducible byte-diff (criteria 2 and 3) were completed with the
  release on 2026-08-13 and the PROTOTYPE banner was lifted — but the
  version stays 0.x because the trust model is *strengthened*, not
  redefined. A breaking trust change (e.g. a new signing key) would be
  a MAJOR bump.
- **MINOR** — new user-facing functionality or a significant security
  hardening step (v0.2.0 = dice-seed wallet + guidance; v0.3.0 = security
  pass).
- **PATCH** — bug fixes and documentation corrections that do not change
  behavior in a user-visible way (v0.1.1 menu fix, v0.2.0-test fixes).

Pre-release tags (`-rc1`, `-alpha`) are allowed for release candidates;
release candidates must pass the full E2E suite before the final tag.

## The PROTOTYPE → PRODUCT rule

A release may drop the "PROTOTYPE" banner only when every item in
[docs/THREAT-MODEL.md → Product acceptance criteria](THREAT-MODEL.md)
is true and verified by the test suite. That is a hard rule, not a
marketing decision.

## Release process (v0.3.0 onward)

1. **Freeze** — branch `release/vX.Y.Z` from `main`; only bug fixes.
2. **Verify** — full host test suite + full QEMU E2E on the release
   candidate; reproducible-build check (local vs CI byte-diff).
3. **Sign** — the maintainer signs the tag and the release artifacts with
   the project signing key (see [docs/SIGNING.md](SIGNING.md) — offline
   ceremony, key never touches a networked machine).
4. **Tag & publish** — `vX.Y.Z` tag; CI builds the ISO, attaches
   `SHA256SUMS`; the maintainer attaches `SHA256SUMS.asc` and
   `SHA256SUMS.sig` (detached signatures) and the signed tag.
5. **Post-release** — README/docs updated to the new version, banner
   flipped (only if acceptance criteria met), changelog entry written.

## Supported versions

Only the latest stable release is supported for security fixes (see
SECURITY.md). Older releases are archived but not patched — users are
expected to run the current ISO.

## Changelog

Keep a `CHANGELOG.md` entry per release: user-visible changes, security
impact, test-suite status, and a link to the verifying release notes.
