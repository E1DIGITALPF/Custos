# Traveler Mode

## Overview

Traveler Mode is a **preemptive, manually-activated security posture** designed for scenarios where you anticipate potential device inspection, such as:

- International border crossings
- Airport security checkpoints
- High-risk business travel
- Conferences or events with security concerns

Unlike Hostile Mode (which activates reactively to threats), Traveler Mode is enabled **before** any threat materializes. It reduces your device's attack surface while maintaining full usability for calls, apps, and normal operation.

---

## Quick Start

### Activating Traveler Mode

**Via Terminal:**
```bash
su -c 'sh /data/adb/modules/custos/common/profiles.sh activate traveler'
```

**Via Quick Settings Tile:** Tap the "Traveler" tile (if configured)

**Via App Shortcut:** Long-press Custos icon → Traveler Mode

### Deactivating Traveler Mode

```bash
su -c 'sh /data/adb/modules/custos/common/profiles.sh deactivate'
```

---

## What Traveler Mode Does

### Security Measures Applied

| Feature | Traveler Mode | Normal | Hostile |
|---------|---------------|--------|---------|
| USB MTP/PTP | Disabled | Enabled | Charge-only |
| USB ADB | Disabled | User setting | Neutralized |
| Session tokens | Cleared | Intact | Purged |
| Cloud sync | Paused | Active | Disabled |
| Screen timeout | 30 seconds | User setting | Immediate |
| Lock notifications | Hidden | Visible | Hidden |
| Wi-Fi auto-connect | Disabled | User setting | N/A (airplane) |
| Clipboard | Cleared on lock | Persistent | Cleared |

### What Remains Functional

- Phone calls and SMS
- Installed apps (may need re-login)
- Camera and gallery
- Offline features
- Bluetooth devices (already paired)
- Mobile data

---

## Traveler vs Hostile

| Aspect | Traveler Mode | Hostile Mode |
|--------|---------------|--------------|
| **Activation** | Manual, preemptive | Automatic or panic |
| **Purpose** | Reduce attack surface | Defend against active threat |
| **Phone usability** | Full | Lock screen only |
| **ADB** | Disabled | Neutralized |
| **USB** | Restricted | Charge-only |
| **Bind mounts** | No | Yes |
| **Key eviction** | On screen off | Immediate |
| **Network** | Restricted | Airplane mode |
| **Recovery** | Easy deactivation | Recovery phrase required |

---

## State Transitions

```
                              ┌──────────────┐
                              │   TRAVELER   │
         activate manually    │              │   deactivate
    ┌────────────────────────►│ • USB restrict│◄──────────────┐
    │                         │ • ADB off     │               │
    │                         │ • Tokens clear│               │
    │                         └───────┬───────┘               │
    │                                 │                       │
┌───┴────┐                           │ trigger              ┌─┴──────┐
│ NORMAL │                           │ (SIM+USB, etc.)      │ NORMAL │
└────────┘                           ▼                      └────────┘
                              ┌──────────────┐
                              │   HOSTILE    │
                              │              │
                              │ • Full lockdown
                              │ • Key eviction│
                              │ • Recovery req│
                              └──────────────┘
```

---

## Use Case: International Travel

### Before Departure

1. **One day before:** Backup important data to secure location
2. **At airport:** Activate Traveler Mode
3. **Optional:** Log out of sensitive apps (banking, email)

### During Travel

- Device functions normally for calls, maps, boarding passes
- USB ports at airports cannot access your data
- Stolen device cannot be quickly exploited

### After Arrival

1. **In secure location:** Deactivate Traveler Mode
2. **Re-authenticate:** Log back into apps as needed
3. **Resume normal operation**

---

## Configuration

Edit `/data/adb/custos/config/profiles/traveler.conf` to customize:

### Example: More Restrictive

```ini
[usb]
mode=charge          # No data at all

[screen]
lock_mode=paranoid   # Immediate lock, no bio

[network]
mode=airplane        # Full network isolation
```

### Example: More Permissive

```ini
[usb]
mode=restrict        # No file transfer
mtp_enabled=false
adb_enabled=false

[biometrics]
state=enabled        # Keep fingerprint

[network]
mode=normal          # Keep all connections
```

---

## Escalation to Hostile

If a threat is detected while in Traveler Mode, the system can escalate directly to Hostile Mode:

**Escalation triggers (by default):**
- SIM removal + USB connection
- Strong boot anomaly detected
- Multiple failed unlock attempts

**Configuration:**
```ini
[escalation]
allow_escalation=true
escalation_triggers=sim_removed_plus_usb,boot_anomaly_strong,lockscreen_fail
skip_alert=true    # Skip ALERT, go directly to HOSTILE
```

---

## Frequently Asked Questions

### Does Traveler Mode delete my data?
No. It clears session tokens (requiring re-login) but does not delete any files, messages, or media.

### Can I still use my phone normally?
Yes. Calls, texts, apps, and camera all work normally. You may need to re-login to some apps.

### What if I forget to deactivate it?
Traveler Mode has no automatic timeout. You must manually deactivate. This is intentional—you control when it ends.

### Can someone tell my phone is in Traveler Mode?
A small notification indicates "Travel Security Active." This is configurable.

### Does it drain battery faster?
Slightly. The additional monitoring uses minimal power, comparable to having a security app running.

---

## Technical Details

### Activation Process

1. Verify user authentication (if configured)
2. Apply USB restrictions
3. Disable ADB and clear keys
4. Clear session tokens and clipboard
5. Pause cloud sync
6. Configure strict screen lock
7. Set network restrictions
8. Display persistent notification
9. Start escalation monitoring

### Stored State

State is persisted in `/data/adb/custos/state.db`:
```
TRAVELER:1703347200:traveler.conf
```

Format: `STATE:TIMESTAMP:PROFILE_FILE`

---

## Security Notes

1. **Traveler Mode is not Hostile Mode.** It reduces attack surface but does not provide the same level of protection against active forensic extraction.

2. **If you're detained, activate Hostile Mode.** Traveler Mode is for precaution; Hostile Mode is for active defense.

3. **Re-authenticating apps may leave traces.** Consider which apps you use while in Traveler Mode.

4. **USB charging is still possible.** Use trusted power sources or a USB data blocker for additional security.

