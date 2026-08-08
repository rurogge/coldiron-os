# keys/ — your trusted signing keys

**Nothing in this directory is fetched automatically, ever.** The build
(`scripts/fetch-binaries.sh`) refuses to verify third-party binaries unless
you have imported their signing keys here **out-of-band**. This is
deliberate: the security model starts from trust you established yourself,
not from keys downloaded over the same channel as the binaries.

## Sparrow Wallet → `keys/sparrow.gpg`

Import Craig Raw's signing key by following the official instructions:

    https://sparrowwallet.com/docs/verifying-signatures.html

Then create this project's keyring:

```sh
gpg --no-default-keyring --keyring keys/sparrow.gpg --import <sparrow-signing-key.asc>
gpg --no-default-keyring --keyring keys/sparrow.gpg --fingerprint
```

Confirm the fingerprint against the official page **before** building. The
build script verifies the release tarball's detached `.asc` signature with
this keyring and aborts on any mismatch.

## Bitcoin Core

The v0.1 ISO installs Bitcoin Core CLI tools from the Debian package
`bitcoin-core` (reproducible via apt, no manual keyring needed). The
upstream-tarball mode with manual `SHA256SUMS.asc` verification is on the
roadmap — when it lands, its keyring will live here too.

## Security rule

If you ever see a script in this project downloading a key, that is a bug.
Report it.
