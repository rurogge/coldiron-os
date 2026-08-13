# Contributing to COLDIRON OS

Thanks for wanting to help. This is a small, security-focused project —
the bar for merging is deliberately high, because every change ships in a
tool people may trust with real bitcoin.

## Ground rules

- **Security first.** A change that weakens the threat model — even
  cosmetically — will not merge. When in doubt, make the change *more*
  conservative.
- **Honesty in docs.** The README and `docs/` are the project's contract
  with its users. If you add a feature, update the docs in the same PR.
  Never claim something is "verified" unless the test suite proves it.
- **≤76 columns** for anything shown in the console menu/tips — a wrapped
  line is a bug.
- **English only** in the image UI and docs (approved product decision).
- **No binary blobs** committed to the repo unless produced and verified
  by `scripts/fetch-binaries.sh` (and even those live under
  `config/includes.chroot/opt/` which is gitignored).

## Development workflow

1. **Open an issue first** for anything non-trivial — the maintainer
   (and the threat model) may change the approach.
2. Branch from `main`, keep changes small and reviewable.
3. Every change to `config/includes.chroot/`, `config/hooks/`, or the
   `coldiron-*` scripts **must** come with a test update. The existing
   host test suite (`scripts/host-tests.sh`) and the QEMU E2E harness
   (`scripts/e2e/run-all.sh`, smoke test: `scripts/qemu-test.sh`) — see
   `docs/TESTING.md` — must pass before merge. New behavior gets new
   test vectors.
4. Run `bash -n` on every changed script and `python3 -m py_compile` on
   any embedded Python.
5. Reference the issue in the commit message (`fixes #NN`).

## Build & test (quick reference)

```sh
sudo ./build-root.sh        # install prereqs + import Sparrow key + build
./scripts/qemu-test.sh      # headless smoke test of the ISO in QEMU
```

See `docs/BUILD.md` and `docs/TESTING.md` for the full procedure,
including the reproducible-build and networkless-kernel checks.

## Reviewing

If you are asked to review a PR, read `docs/THREAT-MODEL.md` first and
review the change *against the threat model*, not just against the code:
"does this still hold when the attacker has a root shell in the VM?"

## Reporting security issues

See [SECURITY.md](SECURITY.md) — do **not** file public issues for
vulnerabilities.
