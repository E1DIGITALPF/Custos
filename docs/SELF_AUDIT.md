# Self-Audit Guide

This guide helps you verify that Custos is properly installed, configured, and functioning. Regular self-audits ensure your device is actually protected, not just theoretically protected.

---

## Table of Contents

1. [Quick Health Check](#quick-health-check)
2. [Detailed Verification Checklist](#detailed-verification-checklist)
3. [Automated Audit Script](#automated-audit-script)
4. [Manual Verification Procedures](#manual-verification-procedures)
5. [Troubleshooting Common Issues](#troubleshooting-common-issues)
6. [Audit Schedule Recommendations](#audit-schedule-recommendations)

---

## Quick Health Check

Run this command for an instant status overview:

```bash
su -c 'sh /data/adb/modules/custos/common/audit.sh quick'
```

**Expected Output (Healthy System):**
```
=== Custos Quick Health Check ===
[OK] Module installed and active
[OK] Current state: NORMAL
[OK] USB defense monitor running
[OK] ADB neutralizer ready
[OK] Recovery phrase configured
[OK] Failsafe timer: 72h
[OK] Device profile: google_pixel
=== Health Check: PASSED ===
```

---

## Detailed Verification Checklist

### Module Installation

| Check | How to Verify | Expected Result |
|-------|---------------|-----------------|
| Module installed | `ls /data/adb/modules/custos/` | Directory exists with files |
| Module enabled | Check Magisk Manager | Module shows as enabled |
| Service running | `pgrep -f "custos"` | Process IDs returned |
| No errors in log | `logcat -d \| grep CUSTOS` | No ERROR level messages |

### USB Defense

| Check | How to Verify | Expected Result |
|-------|---------------|-----------------|
| USB monitor active | `pgrep -f "usb_defense.sh"` | Process running |
| Charge-only enforced | Connect to PC | PC sees "Charging" only |
| No MTP/PTP | File manager on PC | No device appears |
| No ADB | `adb devices` from PC | Device not listed |

### Trigger System

| Check | How to Verify | Expected Result |
|-------|---------------|-----------------|
| Config file exists | `cat /data/adb/custos/triggers.conf` | Configuration displayed |
| Volume panic works | Press Vol- 5x in 3s | HOSTILE mode activates |
| SIM trigger works | Remove SIM card | ALERT or HOSTILE activates |
| Recovery works | Enter recovery phrase | Normal mode restored |

### Key Eviction

| Check | How to Verify | Expected Result |
|-------|---------------|-----------------|
| Script exists | `ls .../common/key_eviction.sh` | File present |
| Can execute | `sh .../key_eviction.sh status` | Status displayed |
| Eviction logged | Check eviction.log | Entries present |

### Recovery System

| Check | How to Verify | Expected Result |
|-------|---------------|-----------------|
| Phrase configured | Check for recovery_phrase.enc | File exists |
| Validator works | `sh .../recovery_validator.sh status` | Status shown |
| Failsafe active | `sh .../failsafe_timer.sh status` | Timer configured |

---

## Automated Audit Script

The audit script performs comprehensive verification automatically.

### Running Full Audit

```bash
su -c 'sh /data/adb/modules/custos/common/audit.sh full'
```

### Audit Options

```bash
# Quick health check (30 seconds)
su -c 'sh .../audit.sh quick'

# Full audit (2-3 minutes)
su -c 'sh .../audit.sh full'

# USB-specific test
su -c 'sh .../audit.sh usb'

# Trigger test (WARNING: activates HOSTILE)
su -c 'sh .../audit.sh triggers'

# Generate audit report
su -c 'sh .../audit.sh report'
```

### Understanding Audit Results

**Status Indicators:**
- `[OK]` - Check passed
- `[WARN]` - Potential issue, investigate
- `[FAIL]` - Critical failure, action required
- `[SKIP]` - Check skipped (e.g., not applicable)

**Exit Codes:**
- `0` - All checks passed
- `1` - Warnings present
- `2` - Failures present

---

## Manual Verification Procedures

### Test 1: USB Lockdown Verification

**Purpose:** Verify that USB data transfer is blocked.

**Procedure:**
1. Ensure device is in NORMAL or TRAVELER state
2. Connect device to computer via USB
3. Check what appears on computer

**Expected Results:**

| Computer OS | Expected Behavior |
|-------------|-------------------|
| Windows | "Charging" in notification area, no drive in Explorer |
| macOS | Nothing in Finder, no device in System Information > USB |
| Linux | `lsusb` shows device, but no /dev/sd* or MTP mount |

**If Failed:**
- Check USB defense monitor is running
- Verify USB state: `cat /sys/class/android_usb/android0/functions`
- Should be empty or "charging"

### Test 2: ADB Neutralization Verification

**Purpose:** Verify that ADB is completely blocked.

**Procedure:**
1. Enable USB debugging in Developer Options
2. Connect to computer with ADB installed
3. Run: `adb devices`

**Expected Results:**
- Device should NOT appear in device list
- If device briefly appears, should show "unauthorized" then disappear

**If Failed:**
- Check ADB neutralizer: `pgrep -f adb_neutralizer`
- Check ADB state: `getprop sys.usb.config`
- Should NOT contain "adb"

### Test 3: Panic Trigger Test

**WARNING:** This test activates HOSTILE mode. Have your recovery phrase ready.

**Purpose:** Verify panic trigger works.

**Procedure:**
1. Ensure you know your recovery phrase
2. Press Volume Down 5 times within 3 seconds
3. Observe device behavior

**Expected Results:**
- Screen should lock immediately
- Device should vibrate (confirmation pattern)
- State should change to HOSTILE

**Verification:**
```bash
su -c 'sh .../state_machine.sh status'
# Should show: Current state: HOSTILE
```

**Recovery:**
```bash
su -c 'sh .../recovery_validator.sh interactive'
# Enter your recovery phrase
```

### Test 4: Recovery Phrase Verification

**Purpose:** Verify recovery phrase works before you need it.

**Procedure:**
1. Activate HOSTILE mode (via test 3 or command)
2. Attempt recovery with your phrase

**Expected Results:**
- Correct phrase: Normal mode restored
- Incorrect phrase: Failure message, attempts counted

**If Failed:**
- Verify phrase file exists: `ls /data/adb/custos/recovery_phrase.enc`
- Reset phrase if needed: `sh .../recovery_validator.sh set "new_phrase"`

### Test 5: Device Profile Verification

**Purpose:** Verify correct device profile is loaded.

**Procedure:**
```bash
su -c 'sh .../device_profiles.sh detect'
```

**Expected Results:**
- Manufacturer correctly identified
- Appropriate profile selected (e.g., google_pixel, samsung, xiaomi)

**If Wrong Profile:**
- Check device properties: `getprop ro.product.brand`
- Verify profile file exists in config/devices/

---

## Troubleshooting Common Issues

### Issue: USB Still Shows as MTP Device

**Symptoms:**
- Computer shows device as file storage
- Files visible in file manager

**Causes:**
- USB defense monitor not running
- USB state not enforced
- System overriding settings

**Solutions:**
1. Check monitor: `pgrep -f usb_defense`
2. Force enforcement: `sh .../usb_defense.sh enforce`
3. Check for conflicting apps that manage USB

### Issue: ADB Still Accessible

**Symptoms:**
- `adb devices` shows device
- ADB shell works

**Causes:**
- ADB neutralizer not running
- Development settings re-enabled
- System restarted adbd

**Solutions:**
1. Check neutralizer: `pgrep -f adb_neutralizer`
2. Manual neutralize: `sh .../adb_neutralizer.sh neutralize`
3. Check settings: `settings get global adb_enabled`

### Issue: Panic Trigger Not Working

**Symptoms:**
- Volume Down x5 does nothing
- HOSTILE mode not activated

**Causes:**
- Trigger monitor not running
- Wrong key detection
- Input device not found

**Solutions:**
1. Check trigger monitor: `pgrep -f hostile_mode`
2. Verify config: `cat /data/adb/custos/triggers.conf | grep volume`
3. Test manually: `sh .../hostile_mode.sh activate test`

### Issue: Recovery Phrase Rejected

**Symptoms:**
- Correct phrase shows as incorrect
- Cannot exit HOSTILE mode

**Causes:**
- Phrase changed
- Encoding issue
- Hash mismatch

**Solutions:**
1. Wait for failsafe timer (check: `sh .../failsafe_timer.sh remaining`)
2. Use Magisk Manager to disable module and reboot
3. If phrase unknown, failsafe will restore after 72h

### Issue: False Positives

**Symptoms:**
- ALERT/HOSTILE activates unexpectedly
- Normal activities trigger defense

**Causes:**
- Trigger sensitivity too high
- SIM slot issues (dual SIM)
- Boot hash changed by OTA

**Solutions:**
1. Check recent triggers: `cat /data/adb/custos/hostile_activations.log`
2. Adjust trigger sensitivity in triggers.conf
3. Update boot hash after OTA: handled automatically for weak anomalies

---

## Audit Schedule Recommendations

### Weekly Quick Check

```bash
su -c 'sh .../audit.sh quick'
```
- Verify monitors running
- Check current state
- Confirm no errors

### Monthly Full Audit

```bash
su -c 'sh .../audit.sh full'
```
- Complete system verification
- USB test with computer
- Recovery phrase test

### After System Updates

```bash
su -c 'sh .../audit.sh full'
su -c 'sh .../device_profiles.sh detect'
```
- Verify module still active
- Check for false boot anomaly
- Confirm profile still correct

### Before High-Risk Travel

```bash
su -c 'sh .../audit.sh full'
# Test panic trigger
# Test recovery phrase
# Verify TRAVELER mode works
```
- Complete all manual tests
- Confirm recovery phrase memorized
- Practice activation/recovery

---

## Audit Report Generation

Generate a comprehensive report for documentation:

```bash
su -c 'sh .../audit.sh report' > /sdcard/custos_audit_$(date +%Y%m%d).txt
```

**Report Contents:**
- System information
- Module status
- All check results
- Configuration summary
- Recent logs

**Note:** Review report for sensitive information before sharing.

---

## Verification Matrix

Use this matrix to track your audit results:

| Category | Check | Status | Date | Notes |
|----------|-------|--------|------|-------|
| Install | Module active | | | |
| Install | Service running | | | |
| USB | Charge-only enforced | | | |
| USB | No MTP visible | | | |
| ADB | Neutralizer running | | | |
| ADB | ADB disabled | | | |
| Triggers | Config valid | | | |
| Triggers | Panic trigger works | | | |
| Recovery | Phrase set | | | |
| Recovery | Phrase works | | | |
| Recovery | Failsafe active | | | |
| Device | Profile correct | | | |

---

*Regular auditing is the difference between "I think I'm protected" and "I know I'm protected."*

