# Improvement Notes

These are follow-up improvements for the Sidecar and BetterDisplay sync script.
They are not required for the current working behavior, but would make the
automation safer to operate and easier to debug.

## Priority: Immediate

### Add stale Sidecar-state expiry or consecutive-miss tracking

Logs confirm this is actively occurring: `external-sidecar` was last confirmed
at 16:38, and every sync since then (391 consecutive misses over 66 minutes)
has printed:

```text
External display detected during sync; Sidecar probe missed, preserving remembered Sidecar state
```

Preserving `external-sidecar` is useful when macOS temporarily fails to report
Sidecar, but keeping it forever is wrong. If Sidecar was later disconnected
manually and the probe keeps missing, the next external-display disconnect will
incorrectly trigger an automatic Sidecar reconnect.

Suggested direction:

- Record a miss count alongside `external-sidecar` in the state file (e.g.
  `external-sidecar:3`).
- Clear the remembered Sidecar state only after several consecutive misses
  (e.g. 5–10).
- Reset the miss count whenever `is_sidecar_connected` confirms Sidecar again.
- Cover the behavior with tests for transient misses and real disconnects.

### Reduce steady-state log noise

The log has grown to 10 MB / 160,776 lines over five days. Every 10-second
sync cycle produces five identical lines even when nothing changes:

```text
Display sync requested
External display detected from BetterDisplay DDC
External display detected during sync; Sidecar probe missed, preserving remembered Sidecar state
External display detected during sync; disconnecting BetterDisplay virtual display
BetterDisplay virtual display target already connected=off; skipping set
```

Suggested direction:

- Log state transitions, not every steady-state confirmation.
- Keep important events such as external display `present -> absent`, virtual
  display `off -> on`, Sidecar recovery, and probe errors.
- Suppress repeated messages like `target already connected=off` and
  `Sidecar probe missed` unless debug logging is enabled; or deduplicate them
  by only logging on the first occurrence and after a state change.
- Add simple log rotation, or document how to rely on macOS log rotation if
  the file remains in `~/Library/Logs`.

## Priority: Near-term

### Cache or streamline repeated display probes

Logs show the BetterDisplay DDC path is triggered on **every** sync cycle, not
occasionally. The current monitor keeps ioreg data present but with active
timing of 0 (likely a power-state or sleep quirk), so the code always falls
through from ioreg to BetterDisplay DDC — meaning two BetterDisplay CLI calls
(`get --identifiers` + `get --ddcCapabilitiesString`) every 10 seconds.

Additionally, `ioreg_has_display_data` and `has_external_display_from_ioreg`
each invoke `ioreg` separately within a single probe cycle. The output could
be captured once and shared between them.

Suggested direction:

- Cache the last BetterDisplay DDC probe result with a short TTL (e.g. 30
  seconds), and rerun it only when the ioreg result changes or becomes
  inconclusive.
- Capture ioreg output once per probe cycle and pass it to both
  `ioreg_has_display_data` and `has_external_display_from_ioreg`.
- Keep the current conservative behavior around `unknown` results.

### Make launchd stderr easier to interpret

`sidecar-display-sync.launchd.err.log` shows a May 2 error from a `cleanup`
typo that was fixed on May 5, but the log was never cleared. Anyone looking at
it today would think the script is still broken. The mtime must be checked
against the script's own mtime to judge whether an error is current.

Suggested direction:

- Clear launchd stdout/stderr logs during reinstall.
- Or add a note to the README explaining that launchd stderr should be judged
  together with its modification time and the main `sidecar-toggle.log`.

## Priority: When time allows

### Make BetterDisplay failure handling more precise

`set_virtual_display_connection` treats any BetterDisplay output containing
`Failed.` as an idempotent "already in this state" result. Two issues:

1. The match is too broad — any BetterDisplay error mentioning `Failed.` is
   silently swallowed, masking real failures.
2. After a `Failed.` result is treated as success, `ensure_virtual_display_connection`
   still writes the target state to `.sidecar-toggle-virtual-state`. The actual
   display state is unconfirmed, but future sync cycles will skip the set
   command because the cached state appears current.

Suggested direction:

- Match only the known idempotent BetterDisplay failure text if it is stable.
- Or, after a `Failed.` result, verify the current virtual display state before
  treating the command as successful.
- Only write `.sidecar-toggle-virtual-state` when the set command clearly
  succeeded or the state is confirmed.

### Avoid repeated `probe_external_display` calls in toggle

`main()` calls `probe_external_display` twice during a single toggle operation:
once inside `prepare_virtual_display_for_sidecar` and once after
`connect_preferred_device` to decide which state to write. The display
topology could theoretically change between the two calls. The first result
should be saved and reused.

### Guard against stale lock after SIGKILL

The lock is a directory at `/tmp/sidecar-toggle.${UID}.lock`. The `trap`
catches `EXIT INT TERM` but not `SIGKILL`. On macOS, `/private/tmp` survives
reboots, so a crash or `kill -9` leaves the lock directory permanently,
preventing any future invocation until it is manually deleted.

Suggested direction:

- Include the PID in the lock path and validate that the owning process is
  still alive before treating the lock as held.
- Or document the manual recovery step (`rmdir /tmp/sidecar-toggle.*.lock`).

### Clarify whether `sync_main` should respect the trigger file device priority

`main()` (toggle) calls `load_trigger_device_priority`, but `sync_main` does
not. When sync triggers a Sidecar reconnect (the external-sidecar recovery
path), it will not honor the trigger file's device priority. This is likely
intentional — the trigger file is written by an external SSH trigger and
targets a single toggle — but it is worth a comment to make the asymmetry
explicit.
