# Hostile Custody Profile (HCP)

## Overview

The Hostile Custody Profile (HCP) is the **maximum security posture** activated when a confirmed threat is detected. This profile assumes the device is being actively targeted for forensic extraction and applies all defensive measures at maximum intensity.

---

## When HCP Activates

### Automatic Triggers

| Trigger | Description |
|---------|-------------|
| Volume Panic | Volume Down pressed 5 times in 3 seconds |
| SIM + USB Compound | SIM removed AND USB connected |
| Strong Boot Anomaly | Recovery mode, forensic files detected |
| Lockscreen Fail | 5+ failed unlock attempts |

### Manual Activation

```bash
su -c 'sh /data/adb/modules/custos/common/profiles.sh activate hostile_custody'
```

Or via panic button (Volume Down x5).

---

## What HCP Does

### Immediate Actions (< 1 second)

1. **Screen Lock** — Device locks immediately
2. **Key Eviction** — Encryption keys removed from memory
3. **USB Lockdown** — Charge-only mode enforced
4. **ADB Kill** — Debug bridge terminated

### Sustained Defense

| Component | Action |
|-----------|--------|
| USB | Charge-only, monitored every 500ms |
| ADB | Killed continuously, bind mounts applied |
| Network | Airplane mode forced |
| Biometrics | Completely disabled |
| Screen | Locked, no notifications visible |
| Keys | Re-evicted every 60 seconds |

---

## Defense Layers

```
┌─────────────────────────────────────────────────────────────┐
│                    HOSTILE CUSTODY MODE                      │
├─────────────────────────────────────────────────────────────┤
│  Layer 5: SELinux Policy Enforcement                        │
│  ─────────────────────────────────────────────────────────  │
│  Layer 4: Bind Mounts (adbd → /dev/null)                    │
│  ─────────────────────────────────────────────────────────  │
│  Layer 3: Socket/FunctionFS Blocking                        │
│  ─────────────────────────────────────────────────────────  │
│  Layer 2: Service/Process Termination                       │
│  ─────────────────────────────────────────────────────────  │
│  Layer 1: Properties & Settings                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Recovery Options

### Option 1: Recovery Phrase

```bash
su -c 'sh /data/adb/modules/custos/common/recovery_validator.sh interactive'
```

Enter your recovery phrase to exit HCP and restore normal operation.

**Limits:**
- 3 attempts before lockout
- 5-minute lockout after failures
- 3 lockouts triggers permanent lockdown

### Option 2: Failsafe Timer

Default: **72 hours**

If you cannot enter your recovery phrase, HCP automatically deactivates after the failsafe period.

Check remaining time:
```bash
su -c 'sh /data/adb/modules/custos/common/failsafe_timer.sh remaining'
```

### Option 3: Magisk Manager

If accessible, disable the Custos module via Magisk Manager and reboot.

---

## Configuration

### Profile File

`/data/adb/modules/custos/config/profiles/hostile_custody.conf`

### Key Settings

```ini
[key_eviction]
immediate=true              # Evict keys on activation
recurring_interval_seconds=60  # Re-evict periodically

[adb]
use_bind_mounts=true        # Most aggressive ADB blocking

[recovery]
failsafe_hours=72           # Auto-exit after 72h
max_attempts=3              # Phrase attempts before lockout
```

---

## Comparison with Traveler Mode

| Aspect | Traveler | Hostile Custody |
|--------|----------|-----------------|
| Activation | Manual, preemptive | Auto or panic |
| Phone use | Normal | Lock screen only |
| USB | Restricted | Charge-only |
| ADB | Disabled | Neutralized (bind mount) |
| Keys | Lock on screen off | Immediate eviction |
| Network | Restricted | Airplane mode |
| Recovery | Easy deactivation | Phrase required |

---

## Operational Scenarios

### Scenario: Border Crossing

1. Approaching checkpoint, anticipate inspection
2. Activate HCP manually OR let triggers activate if device seized
3. Device becomes extraction-resistant
4. After crossing, enter recovery phrase
5. Resume normal operation

### Scenario: Device Theft

1. Thief powers on device
2. Boot anomaly detection may trigger if tampered
3. Failed unlock attempts trigger HCP
4. Thief cannot extract data via USB tools
5. Data remains encrypted and inaccessible

### Scenario: Arrest

1. Device seized by authority
2. SIM removal + USB connection triggers HCP
3. Keys evicted before forensic tool connects
4. Forensic extraction fails
5. User can recover device after release with phrase

---

## Security Guarantees

### What HCP Protects Against

- ✅ Cellebrite UFED (all extraction modes)
- ✅ Oxygen Forensic Detective (all extraction modes)
- ✅ MOBILedit Forensic (all extraction modes)
- ✅ Generic ADB-based extraction
- ✅ MTP/PTP file browsing
- ✅ Cloud token theft
- ✅ Session hijacking

### What HCP Does NOT Protect Against

- ❌ Chip-off (physical memory removal)
- ❌ JTAG debugging
- ❌ Court-ordered password disclosure
- ❌ User voluntarily unlocking
- ❌ Pre-installed malware with root

---

## Logging

HCP activation is logged to:
```
/data/adb/custos/hostile_activations.log
```

Format:
```
<timestamp>:<trigger_source>
```

Example:
```
1703347200:volume_panic
1703348100:sim_usb_compound
```

---

## Testing

**WARNING:** Testing HCP will lock your device and require recovery phrase.

```bash
# Confirm you have your recovery phrase ready
su -c 'sh /data/adb/modules/custos/common/recovery_validator.sh status'

# Test activation (will lock device)
su -c 'sh /data/adb/modules/custos/common/hostile_mode.sh test'
```

---

## Important Notes

1. **Memorize your recovery phrase.** It is the primary recovery method.

2. **Failsafe timer is your backup.** Don't disable it unless absolutely necessary.

3. **HCP is not stealth mode.** The device will appear locked and unresponsive. This is intentional—appearing "broken" discourages further attempts.

4. **Data is preserved.** HCP never deletes your data. Everything is recoverable after authentication.

