# COLDIRON OS — Release Signing Ceremony

This document describes how release artifacts get signed, and the
offline ceremony for the project's release key. **Follow it exactly.**

## The two keys (do not confuse them)

| Key | Purpose | Where it lives |
|---|---|---|
| **Release key** ("COLDIRON OS Release") | Signs tags, `SHA256SUMS.asc`, ISO. **The trust anchor.** | Offline / air-gapped only, paper backup |
| **Boot key** (`keys/boot/`) | Signs the kernel/initramfs inside the ISO for GRUB verification. A build component, NOT a trust anchor — its private half is public by design. | Repo (committed), see `keys/boot/README.md` |

## 1. Generate the release key (once, offline)

On a machine that has **never been and will never be networked** (the
COLDIRON OS ISO itself is perfect for this — boot it, exit to shell):

```sh
gpg --full-generate-key
#   kind: RSA and RSA (sign + encrypt)   — RSA required (GRUB/portability)
#   4096 bits, no expiry
#   real name: COLDIRON OS Release
#   email: release@coldiron-os.invalid (or a real one you control)
#   comment: leave empty
#   passphrase: LONG and random — write it on paper, split in two places
```

Then, still offline:

```sh
gpg --armor --export "COLDIRON OS Release" > coldiron-release.pub
gpg --armor --export-secret-keys "COLDIRON OS Release" > coldiron-release.sec
gpg --armor --gen-revoke "COLDIRON OS Release" > coldiron-release.revoke
gpg --fingerprint "COLDIRON OS Release"
```

- **Paper backup**: print the fingerprint, the revocation certificate and
  the passphrase; store in two separate physical locations.
- Copy `coldiron-release.pub` to a USB stick (air-gap crossing) and publish
  it in the repo under `keys/release.pub` + in the README.
- The `.sec` key file and the revocation cert go to cold storage (another
  USB), never online, never in the repo.

## 2. Signing a release (every release, offline)

On the air-gapped machine, with the ISO transferred in:

```sh
./scripts/sign-release.sh coldiron-os-X.Y.Z-amd64.iso
```

This writes `SHA256SUMS`, `SHA256SUMS.asc` and `<iso>.asc` next to the
ISO. Transfer all three files (ISO + the two `.asc` + SHA256SUMS) to the
online machine via USB.

## 3. Publishing (online machine)

1. Tag: `git tag -s vX.Y.Z -m "COLDIRON OS vX.Y.Z"` — **-s, signed**, using
   the release key (if you signed the tag on the offline machine, import
   the tag there and push; otherwise sign on the online machine with the
   key copied — see note below).
2. Push the tag — CI builds the ISO from the tag and attaches it to the
   release (workflow `build.yml`).
3. Attach `SHA256SUMS`, `SHA256SUMS.asc`, `<iso>.asc` to the release.
4. **Verify the CI-built ISO is byte-identical to your offline build**
   (reproducible-build check): `sha256sum` both — they must match. If they
   do not, do NOT sign the CI artifact; investigate.
5. Announce.

> **Note on tag signing**: the cleanest flow is to create and sign the tag
> offline, then `git push --tags` from the online machine. If the release
> key is on the online machine's keyring (some maintainers keep a signing
> subkey there), the tag can be signed at push time — but the private key
> material should still originate from the offline ceremony.

## 4. What the user verifies (the trust chain)

```sh
sha256sum -c SHA256SUMS
gpg --keyserver keyserver.ubuntu.com --recv-keys <RELEASE_FINGERPRINT>
gpg --verify SHA256SUMS.asc SHA256SUMS     # ✔ Good signature
sudo dd if=coldiron-os-X.Y.Z-amd64.iso of=/dev/sdX bs=4M status=progress
```

At boot, GRUB additionally verifies the kernel/initramfs against the
embedded boot key (see `keys/boot/README.md`). The release signature is
what proves the ISO is genuinely from the project.

## 5. Key compromise / rotation

- Publish the revocation cert from cold storage, revoke on keyservers,
  and re-key: new fingerprint, new README/SECURITY.md entries, and a note
  in the release announcement explaining the rotation and why.
- Rotate the **boot key** too (regenerate `keys/boot/`, update
  `config/includes.chroot/usr/share/coldiron/boot-key.pub`, commit both
  together — the release signature authenticates the new boot key).

## v0.3.0 note — one-shot signing key (deliberate compromise)

v0.3.0 was signed with a **one-shot** key to unblock the release without
a physical air-gapped ceremony. The key (RSA-4096, fingerprint
`63EA 0A22 C16A D051 8237 8B9B 7F53 97DF 4477 C2BD`, pubkey in
`keys/release.pub`) was generated inside an air-gapped QEMU VM
(`-net none`) booting the COLDIRON ISO itself, used to sign
`SHA256SUMS` + the ISO, and **revoked immediately after signing** via the
auto-generated revocation certificate. The VM was powered off; the key
existed only in VM RAM and is now destroyed.

Implications, by design:

- The signatures remain cryptographically **valid** — `gpg --verify`
  reports "Good signature" — but the key shows as revoked, so the trust
  anchor is the **fingerprint** published here and in the README,
  verified out-of-band.
- This key must **not** be reused for v0.4.0+. The next release signs
  with a fresh key (one-shot or the full offline ceremony above).
