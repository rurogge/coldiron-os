# keys/ — your trusted signing keys

**Nothing in this directory is fetched automatically, ever.** The build
(`scripts/fetch-binaries.sh`) refuses to verify third-party binaries unless
you have imported their signing keys here **out-of-band**. This is
deliberate: the security model starts from trust you established yourself,
not from keys downloaded over the same channel as the binaries.

## Sparrow Wallet → `keys/sparrow.gpg`

Signing key fingerprint (published on the official download page,
"Verifying the Release" section):

    D4D0 D320 2FC0 6849 A257 B38D E946 1833 4C67 4B40

Import it and create this project's keyring:

```sh
gpg --keyserver keyserver.ubuntu.com --recv-keys D4D0D3202FC06849A257B38DE94618334C674B40
gpg --export D4D0D3202FC06849A257B38DE94618334C674B40 \
  | gpg --no-default-keyring --keyring keys/sparrow.gpg --import
gpg --no-default-keyring --keyring keys/sparrow.gpg --fingerprint
```

**Confirm the fingerprint matches the official page before building:**
https://sparrowwallet.com/download/ → "Verifying the Release".

The build script then verifies the release **manifest** (`sparrow-2.5.3-manifest.txt`,
detached `.asc` signature) with this keyring and cross-checks the archive's
sha256 against the manifest, exactly as the official instructions describe.

## Bitcoin Core

The v0.1 ISO installs Bitcoin Core CLI tools from the Debian package
`bitcoin-core` (reproducible via apt, no manual keyring needed). The
upstream-tarball mode with manual `SHA256SUMS.asc` verification is on the
roadmap — when it lands, its keyring will live here too.

## Security rule

If you ever see a script in this project downloading a key, that is a bug.
Report it.
