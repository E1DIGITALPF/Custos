# Operational Scenarios Guide

This document provides scenario-specific guidance for using Custos in real-world situations. Each scenario includes threat assessment, recommended configuration, and step-by-step operational procedures.

---

## Table of Contents

1. [Scenario Matrix Overview](#scenario-matrix-overview)
2. [Scenario 1: Device Theft](#scenario-1-device-theft)
3. [Scenario 2: Border Crossing](#scenario-2-border-crossing)
4. [Scenario 3: Administrative Seizure](#scenario-3-administrative-seizure)
5. [Scenario 4: Extended Custody](#scenario-4-extended-custody)
6. [Quick Reference Card](#quick-reference-card)

---

## Scenario Matrix Overview

| Scenario | Time Window | Likely Tools | Recommended Profile | Critical Defense |
|----------|-------------|--------------|---------------------|------------------|
| **Device Theft** | Seconds | None / Basic | Automatic triggers | Immediate key eviction |
| **Border Crossing** | Minutes to hours | Cellebrite UFED, Oxygen | TRAVELER → HOSTILE | USB lockdown + token purge |
| **Administrative Seizure** | Hours | Oxygen, MOBILedit | HOSTILE | Full lockdown |
| **Extended Custody** | Days to weeks | Forensic laboratory | HOSTILE | Failsafe timer management |

### Threat Actor Comparison

| Actor | Resources | Time | Expertise | USB Tools | Physical Access |
|-------|-----------|------|-----------|-----------|-----------------|
| Opportunistic Thief | Low | Minutes | Low | Unlikely | Full |
| Border Agent | Medium | Hours | Medium | Cellebrite Touch | Supervised |
| Corporate Security | Medium-High | Hours-Days | Medium-High | Oxygen, MOBILedit | Controlled |
| Forensic Laboratory | High | Weeks | High | All commercial | Full |

---

## Scenario 1: Device Theft

### Threat Profile

```
Actor:           Opportunistic thief
Goal:            Device resale, identity theft, data monetization
Time available:  Seconds to minutes
Tools:           None initially, possibly basic tools later
Physical access: Full, unsupervised
```

### Risk Assessment

| Risk | Level | Mitigation |
|------|-------|------------|
| Immediate data access | HIGH | Auto-triggers on failed unlock |
| USB extraction later | MEDIUM | Persistent USB lockdown |
| SIM swap attacks | MEDIUM | SIM removal trigger |
| Device resale with data | LOW | Key eviction makes data inaccessible |

### Recommended Configuration

**Trigger Configuration:**
```ini
# Automatic protection - no manual action needed
lockscreen_fail:5:enabled      # 5 failed attempts → HOSTILE
sim_removed:alert              # SIM removal → ALERT
sim_removed_plus_usb:enabled   # SIM + USB → HOSTILE
boot_anomaly_strong:enabled    # Recovery/EDL → HOSTILE
```

**Key Settings:**
```ini
[key_eviction]
immediate=true
recurring_enabled=true
recurring_interval_seconds=30

[screen]
lock_mode=paranoid
```

### Operational Procedure

**Before (Prevention):**
1. Ensure strong lock screen (6+ digit PIN or password)
2. Enable biometric + PIN (not biometric only)
3. Verify Custos is active: `su -c 'sh .../state_machine.sh status'`

**During (Automatic):**
- Device handles protection automatically
- Failed unlock attempts trigger HOSTILE mode
- SIM removal + USB triggers HOSTILE mode

**After (Recovery):**
1. Remote locate device (if available)
2. If recovered, use recovery phrase to restore
3. Change critical passwords regardless

### What Happens

```
[Theft occurs]
     ↓
[Thief attempts unlock]
     ↓
[5 failed attempts]
     ↓
[HOSTILE MODE ACTIVATES]
• Screen locked
• Keys evicted
• USB charge-only
• ADB neutralized
     ↓
[Thief connects to PC]
     ↓
[PC sees: "Charging device" - no data access]
     ↓
[Thief gives up or sells device without data]
```

---

## Scenario 2: Border Crossing

### Threat Profile

```
Actor:           Border/customs agent
Goal:            Device inspection, intelligence gathering
Time available:  Minutes to hours
Tools:           Cellebrite UFED Touch, Oxygen Forensic
Physical access: Supervised, may be out of sight
Legal authority: Varies by jurisdiction
```

### Risk Assessment

| Risk | Level | Mitigation |
|------|-------|------------|
| USB extraction attempt | HIGH | TRAVELER mode before crossing |
| Forced unlock request | MEDIUM | Legal, not technical issue |
| Extended detention | LOW-MEDIUM | Failsafe timer |
| Device not returned | LOW | Key eviction protects data |

### Recommended Configuration

**Pre-Travel Setup:**
```ini
[traveler]
# Activate before reaching border
usb_mode=restrict
adb_enabled=false
session_tokens=clear
cloud_sync=pause
```

**Escalation Settings:**
```ini
[escalation]
allow_escalation=true
escalation_triggers=sim_removed_plus_usb,usb_data_attempt
skip_alert=true    # Go directly to HOSTILE if triggered in TRAVELER
```

### Operational Procedure

**Before Travel (24-48 hours):**
1. Backup critical data to secure location
2. Log out of sensitive apps (banking, email)
3. Clear browser history and cached credentials
4. Review what data is on device

**Approaching Border (1-2 hours before):**
1. Activate TRAVELER mode:
   ```bash
   su -c 'sh .../profiles.sh activate traveler'
   ```
2. Verify activation:
   ```bash
   su -c 'sh .../state_machine.sh status'
   # Should show: Current state: TRAVELER
   ```
3. Consider logging out of remaining apps

**At Border:**
- Device appears normal but has reduced attack surface
- If device is taken, triggers will activate HOSTILE if USB connected
- You cannot be compelled to provide what you don't have (evicted keys)

**After Crossing (secure location):**
1. Deactivate TRAVELER mode:
   ```bash
   su -c 'sh .../profiles.sh deactivate'
   ```
2. Re-authenticate apps as needed
3. Resume normal operation

### Country-Specific Considerations

| Region | Legal Environment | Recommendation |
|--------|-------------------|----------------|
| USA | 4th Amendment limited at border | TRAVELER minimum |
| UK | May compel passwords (RIPA) | Know your legal rights |
| Australia | Can compel passwords | Consult legal counsel |
| EU/Schengen | Generally strong privacy | TRAVELER recommended |
| China/Russia | Extensive inspection powers | Maximum precaution |

### What Happens

```
[Approaching border]
     ↓
[Activate TRAVELER mode]
• ADB disabled
• Session tokens cleared
• USB restricted
• Phone still usable
     ↓
[Agent requests device]
     ↓
[Device taken for inspection]
     ↓
[Agent connects to Cellebrite]
     ↓
[USB in restricted mode - no data]
     ↓
[Agent attempts ADB]
     ↓
[ADB disabled - fails]
     ↓
[SIM removed + USB detected]
     ↓
[HOSTILE MODE ACTIVATES]
• Keys evicted
• Full lockdown
     ↓
[Cellebrite shows: "Extraction failed"]
```

---

## Scenario 3: Administrative Seizure

### Threat Profile

```
Actor:           Corporate security, civil authority, non-criminal investigation
Goal:            Evidence gathering for civil/administrative proceedings
Time available:  Hours to days
Tools:           Oxygen Forensic, MOBILedit, professional services
Physical access: Full, controlled environment
Legal authority: Civil order, employment agreement, not criminal warrant
```

### Risk Assessment

| Risk | Level | Mitigation |
|------|-------|------------|
| Professional extraction attempt | HIGH | HOSTILE mode immediately |
| Cloud data access via tokens | HIGH | Token purge critical |
| Extended analysis time | MEDIUM | Recurring key eviction |
| Legal compulsion | VARIES | Legal matter, not technical |

### Recommended Configuration

**Immediate HOSTILE Activation:**
```ini
[activation]
manual_only=false
auto_triggers=volume_panic,sim_usb_compound

[key_eviction]
immediate=true
purge_tokens=true
recurring_enabled=true
recurring_interval_seconds=30
```

### Operational Procedure

**If Seizure is Anticipated:**
1. Activate HOSTILE mode immediately:
   ```bash
   su -c 'sh .../hostile_mode.sh activate manual'
   ```
   Or use panic trigger: **Volume Down x5 in 3 seconds**

2. Do NOT unlock device
3. Do NOT provide passwords unless legally compelled
4. Request legal representation

**If Seizure is Sudden:**
1. Use panic trigger if possible: **Volume Down x5**
2. Device will auto-protect on SIM removal + USB

**During Seizure:**
- Device is in HOSTILE mode
- Keys are evicted and re-evicted every 30 seconds
- All extraction attempts will fail

**After Return:**
1. Enter recovery phrase to restore
2. Change all passwords
3. Review what access may have been attempted

### Legal Considerations

**Know BEFORE you need it:**
- Can you be compelled to provide passwords in your jurisdiction?
- What are the penalties for non-compliance?
- At what point should you request legal counsel?

**Custos's Position:**
- Does NOT help you break the law
- Does NOT destroy evidence
- DOES protect against unauthorized access
- You retain full access with recovery phrase

---

## Scenario 4: Extended Custody

### Threat Profile

```
Actor:           Forensic laboratory, extended investigation
Goal:            Complete data extraction, thorough analysis
Time available:  Days to weeks
Tools:           Full forensic laboratory, all commercial tools, possible hardware
Physical access: Full, indefinite
Expertise:       High - professional forensic examiners
```

### Risk Assessment

| Risk | Level | Mitigation |
|------|-------|------------|
| Advanced software attacks | HIGH | Full HOSTILE lockdown |
| Hardware attacks (chip-off) | OUT OF SCOPE | Not software-preventable |
| Extended time analysis | HIGH | Failsafe timer critical |
| Key extraction from memory | MEDIUM | Continuous key eviction |

### Recommended Configuration

**Maximum Defense:**
```ini
[key_eviction]
immediate=true
evict_fbe=true
evict_keystore=true
purge_tokens=true
memory_scrub=true
recurring_enabled=true
recurring_interval_seconds=30

[adb]
use_bind_mounts=true

[recovery]
failsafe_enabled=true
failsafe_hours=72
```

### Critical: Failsafe Timer

The failsafe timer is crucial in extended custody:

**Configuration:**
```ini
failsafe_hours=72    # Default: 72 hours
```

**Considerations:**
- **Too short:** May expire before you regain access
- **Too long:** Extended period without recovery option
- **Disabled:** Risk of permanent lockout if you forget phrase

**Recommendation:** Keep at 72 hours unless you have specific reason to change.

### Operational Procedure

**If Extended Custody is Possible:**
1. Memorize recovery phrase (do NOT write it down on device)
2. Store recovery phrase in secure external location
3. Consider trusted person who knows phrase

**During Extended Custody:**
- Device maintains HOSTILE mode
- Keys continuously evicted
- All extraction attempts fail
- Failsafe timer counts down

**Recovery Options:**

| Method | Time | Notes |
|--------|------|-------|
| Recovery phrase | Immediate | Primary method |
| Failsafe timer | 72 hours | Automatic if phrase unavailable |
| Magisk disable | Varies | Requires device access |

### Hardware Attack Limitations

**What Custos CANNOT prevent:**
- Physical chip removal (chip-off)
- JTAG debugging
- Hardware implants
- Side-channel attacks

**What this means:**
- A determined adversary with unlimited resources and time may eventually succeed
- Custos significantly raises the bar, making extraction impractical in most scenarios
- For hardware-level threats, consider device destruction (outside Custos's scope)

---

## Quick Reference Card

### Activation Commands

```bash
# Traveler Mode (preemptive)
su -c 'sh /data/adb/modules/custos/common/profiles.sh activate traveler'

# Hostile Mode (immediate)
su -c 'sh /data/adb/modules/custos/common/hostile_mode.sh activate'

# Or use panic trigger: Volume Down x5 in 3 seconds
```

### Status Check

```bash
su -c 'sh /data/adb/modules/custos/common/state_machine.sh status'
```

### Recovery

```bash
su -c 'sh /data/adb/modules/custos/common/recovery_validator.sh interactive'
```

### Scenario Quick Guide

| Situation | Action |
|-----------|--------|
| Leaving for international travel | Activate TRAVELER 1-2 hours before border |
| Approaching checkpoint | Verify TRAVELER active |
| Device being taken | Do nothing (auto-triggers protect) |
| About to be searched | Volume Down x5 for immediate HOSTILE |
| Device returned | Enter recovery phrase in secure location |
| Forgot recovery phrase | Wait for failsafe (72h default) |

### Emergency Contacts

*Add your own emergency contacts here:*

- Legal counsel: _______________
- Trusted person with phrase: _______________
- Emergency contact: _______________

---

## Document History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | December 2025 | Initial release |

---

*Remember: Technical protection is one layer. Know your legal rights and have a plan.*

