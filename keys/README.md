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

## Bitcoin Core → `keys/bitcoin.gpg`

The ISO stages Bitcoin Core CLI tools from the official bitcoincore.org
tarball. Their `SHA256SUMS.asc` is verified against the Bitcoin Core
**release signing keys** — the same out-of-band trust model as Sparrow.

The keys that sign the current release (v31.x) — published on
bitcoincore.org and in the official `bitcoin-core/guix.sigs` repository
(`builder-keys/`):

```
1528 1230 0785 C964 44D3 334D 1756 5732 E08E 5E41   (achow101)
CFB1 6E21 C950 F67F A95E 558F 2EEB 9F5C C095 26C1   (fanquake)
D1DB F2C4 B96F 2DEB F4C1 6654 4101 0811 2E7E A81F   (hebasto)
0AD8 3877 C1F0 CD1E E9BD 660A D7CC 770B 81FD 22A8
F4FC 70F0 7310 0284 24EF C20A 8E42 5659 3F17 7720
5B28 6407 E1EA 6FE0 1CF9 AF48 BF13 1C2D 0536 F8AC
E617 73CD 6E01 040E 2F1B D78C E7E2 984B 6289 C93A
637D B1E2 3370 F84A FF88 CCE0 3152 347D 07DA 627C
A008 3660 F235 A270 00CD 3C81 CE6E C499 45C1 7EA6
ED9B DF7A D6A5 5E23 2E84 5242 57FF 9BDB CC30 1009
```

Import them and create this project's keyring:

```sh
gpg --keyserver keyserver.ubuntu.com --recv-keys \
  152812300785C96444D3334D17565732E08E5E41 \
  CFB16E21C950F67FA95E558F2EEB9F5CC09526C1 \
  D1DBF2C4B96F2DEBF4C16654410108112E7EA81F \
  0AD83877C1F0CD1EE9BD660AD7CC770B81FD22A8 \
  F4FC70F07310028424EFC20A8E4256593F177720 \
  5B286407E1EA6FE01CF9AF48BF131C2D0536F8AC \
  E61773CD6E01040E2F1BD78CE7E2984B6289C93A \
  637DB1E23370F84AFF88CCE03152347D07DA627C \
  A0083660F235A27000CD3C81CE6EC49945C17EA6 \
  ED9BDF7AD6A55E232E84524257FF9BDBCC301009
gpg --export \
  152812300785C96444D3334D17565732E08E5E41 \
  CFB16E21C950F67FA95E558F2EEB9F5CC09526C1 \
  D1DBF2C4B96F2DEBF4C16654410108112E7EA81F \
  0AD83877C1F0CD1EE9BD660AD7CC770B81FD22A8 \
  F4FC70F07310028424EFC20A8E4256593F177720 \
  5B286407E1EA6FE01CF9AF48BF131C2D0536F8AC \
  E61773CD6E01040E2F1BD78CE7E2984B6289C93A \
  637DB1E23370F84AFF88CCE03152347D07DA627C \
  A0083660F235A27000CD3C81CE6EC49945C17EA6 \
  ED9BDF7AD6A55E232E84524257FF9BDBCC301009 \
  | gpg --no-default-keyring --keyring keys/bitcoin.gpg --import
gpg --no-default-keyring --keyring keys/bitcoin.gpg --fingerprint
```

**Confirm the fingerprints match the official sources before building:**
bitcoincore.org download page and the `bitcoin-core/guix.sigs` repository.
The build script then verifies `SHA256SUMS.asc` with this keyring, and
additionally cross-checks the archive's sha256 against the pinned hash
inside `scripts/fetch-binaries.sh`.

## Security rule

If you ever see a script in this project downloading a key, that is a bug.
Report it.
