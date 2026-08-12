# COLDIRON OS — Hardware Wallets & Smartcards

COLDIRON OS ships `pcscd`, OpenSC and libusb, so hardware wallets and
smartcards work inside the air-gapped environment. This page documents
what is supported and how to test it.

## Status

- **Software present**: `pcscd` (PC/SC daemon), `opensc` (PKCS#11),
  `usbutils`. Sparrow Wallet ships with hardware-wallet support built in.
- **Tested end-to-end**: not yet on physical hardware — the QEMU harness
  cannot attach real devices. This is an open validation item for the
  product release (Phase 4, hardware matrix).

## What should work (in principle)

| Device | Path in Sparrow | Notes |
|---|---|---|
| Ledger (Nano S/X) | "Connect to Hardware Wallet" | USB HID; no driver needed, pcscd sees it |
| Trezor (One/T) | "Connect to Hardware Wallet" | USB HID |
| Generic smartcard (PKCS#11) | OpenSC via Sparrow | insert + PIN |

The workflow: the hardware wallet holds the keys; COLDIRON signs PSBTs
with it inside the air gap; the online machine only broadcasts.

## Manual test checklist (run on REAL hardware)

1. Boot COLDIRON OS, option 8 — security check all green.
2. Plug in the device. In a shell: `pcsc_scan` (from `pcsc-tools`, not
   installed by default — or `lsusb` + `systemctl status pcscd`) — the
   device must be enumerated.
3. Option 5 (Sparrow) → File → "Connect to Hardware Wallet" → select the
   device → verify the fingerprint matches what the device shows.
4. Create a wallet on the device (or import a descriptor), generate a
   receive address, compare with the device screen.
5. Sign a test PSBT: create an unsigned PSBT on your ONLINE machine,
   transfer via QR/USB, load it in Sparrow, sign, export, broadcast a
   tiny test transaction.
6. Re-run option 8 — still all green (no state persisted).

Report results (device model + firmware, pass/fail per step) in the
issue tracker; the goal is a supported-devices table.

## Known limits

- No firmware update capability inside the air gap (by design — updates
  happen on an online machine).
- Device-specific quirks may need additional packages; add them to
  `config/package-lists/coldiron.list.chroot` if a device requires it.
