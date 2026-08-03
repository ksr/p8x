---
name: reference_p8x_runsh_disk_reuse
description: os/run.sh reuses an existing disk image; a true rebuild needs rm of the img first
metadata: 
  node_type: memory
  type: reference
  originSessionId: df90e3f3-8668-416d-bc7b-83f2952ba723
---

`os/run.sh` creates and populates the disk (install OS via `p8xfs.py boot`, lay
down /bin, /src, etc.) only inside `if [ ! -f "$disk" ]`. On a REUSED image it
skips that block, so the on-disk OS (LBA 1) and shipped files stay STALE — a
"rebuild everything" on an existing img does NOT update the on-disk OS. The
monitor rides in `eeprom.bin`, which IS rebuilt every run, so BIOS/monitor fixes
propagate regardless; OS-on-disk fixes do not.

For a genuine full rebuild: `rm -f os/run-disk.img os/run-disk1.img` first, then
`P8X_BUILD_ONLY=1 sh os/run.sh os/run-disk.img os/run-disk1.img` (build-only skips
launching the emulator). See [[feedback_p8x_src_tree_upkeep]]. The opctab shipping
in run.sh is idempotent (tolerates "already exists" on a reused disk) as of commit
8ee4793.
