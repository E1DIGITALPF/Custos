# Custos - Anti-Forensic Defense Module

A paranoid-level defensive Magisk module designed to neutralize forensic extraction vectors used by commercial tools such as **Cellebrite UFED**, **Oxygen Forensic Detective**, and **MOBILedit Forensic**.

> **DISCLAIMER**: This module is intended for legitimate privacy protection and security research. Use responsibly and in accordance with applicable laws.

---

## Table of Contents

1. [Features](#features)
2. [Threat Analysis](#threat-analysis)
3. [Installation](#installation)
4. [Configuration](#configuration)
5. [Usage](#usage)
6. [Recovery](#recovery)
7. [Technical Details](#technical-details)
8. [Architecture](#architecture)
9. [SELinux Policies](#selinux-policies)
10. [Troubleshooting](#troubleshooting)
11. [FAQ](#faq)

---

## Features

### Core Defensive Capabilities

| Feature | Description |
|---------|-------------|
| **USB Lockdown** | Enforces charge-only mode, preventing data negotiation |
| **ADB Neutralization** | Persistently kills and blocks Android Debug Bridge |
| **Key Eviction** | Removes encryption keys from memory on hostile events |
| **Boot Anomaly Detection** | Detects recovery mode, EDL, and tampered boot images |
| **Hostile Custody Mode** | Panic mode for border/arrest scenarios |
| **State Machine** | Managed transitions between security states |
| **Failsafe Timer** | Prevents permanent self-lockout |

### What Gets Blocked

- ✅ USB data transfer (MTP, PTP, ADB)
- ✅ Logical extraction via content providers
- ✅ Physical extraction via ADB root
- ✅ File system extraction
- ✅ Cloud token extraction
- ✅ Memory forensics (key eviction)
- ✅ Recovery mode exploitation

---

## Threat Analysis

### Cellebrite UFED

| Attack Vector | Method | Status |
|--------------|--------|--------|
| Logical Extraction | ADB backup, content providers | **BLOCKED** |
| Physical Extraction | Bootloader exploits, EDL mode | **BLOCKED** |
| File System Extraction | Custom recovery | **BLOCKED** |
| JTAG/Chip-off | Physical memory access | **MITIGATED** (key eviction) |

**Why Cellebrite Fails**: Without USB data negotiation, UFED cannot establish any communication channel. The device appears as a "dumb charger" with no enumerable interfaces.

### Oxygen Forensic Detective

| Attack Vector | Method | Status |
|--------------|--------|--------|
| Cloud Extraction | Session tokens | **BLOCKED** (token purge) |
| Logical Plus | ADB root shell | **BLOCKED** |
| Physical Extraction | Chipset exploits | **BLOCKED** |

**Why Oxygen Fails**: Oxygen relies heavily on ADB for Android extraction. With persistent ADB neutralization and USB lockdown, no extraction path is available. Cloud extraction is defeated by session token purge.

### MOBILedit Forensic

| Attack Vector | Method | Status |
|--------------|--------|--------|
| MTP/PTP Access | USB transfer protocols | **BLOCKED** |
| ADB Extraction | Debug bridge | **BLOCKED** |
| SIM Clone Detection | ICCID reading | **BLOCKED** |

**Why MOBILedit Fails**: MOBILedit is entirely dependent on USB connectivity. With charge-only enforcement and ADB neutralization, the tool cannot interact with the device at all.

---

## Installation

### Requirements

- Android 8.0+ (API 26+)
- Magisk 20.4+ installed
- ARM64 device (recommended)

### Steps

1. Download the latest release ZIP
2. Open Magisk Manager
3. Go to Modules → Install from storage
4. Select the ZIP file
5. Reboot when prompted

### First Boot

On first boot after installation:

1. The module initializes with a **default recovery phrase**: `custos_recovery_2025`
2. **IMMEDIATELY** change this phrase:
   ```bash
   su -c 'sh /data/adb/modules/custos/common/recovery_validator.sh set "your_secret_phrase"'
   ```
3. **MEMORIZE** your recovery phrase - it's the only way to exit hostile mode

---

## Configuration

### Trigger Configuration

Edit `/data/adb/custos/triggers.conf`:

```ini
# Hostile mode triggers (immediate activation)
volume_down:5:3:enabled       # Vol- 5x in 3 seconds
sim_removed:enabled           # SIM card removal
lockscreen_fail:5:enabled     # 5 failed unlock attempts
usb_data_attempt:enabled      # USB data mode detection
boot_anomaly:enabled          # Abnormal boot detection

# Alert mode triggers (warning level)
airplane_toggle:3:alert       # Airplane toggle 3x
power_button:7:5:alert        # Power 7x in 5 seconds

# Timing configuration
alert_timeout:30              # Seconds in alert before normal
hostile_min_duration:60       # Minimum hostile mode duration
failsafe_hours:72            # Auto-exit hostile after 72h
```

### Disabling Specific Triggers

To disable a trigger, comment it out or change `enabled` to `disabled`:

```ini
# sim_removed:disabled
```

---

## Usage

### State Overview

```
┌─────────┐     suspicious      ┌─────────┐
│ NORMAL  │ ─────────────────── │  ALERT  │
└────┬────┘                     └────┬────┘
     │                               │
     │ immediate threat              │ confirmed
     │                               │
     ▼                               ▼
┌─────────────────────────────────────────┐
│              HOSTILE MODE               │
│  • USB locked to charge-only            │
│  • ADB completely neutralized           │
│  • Encryption keys evicted              │
│  • Biometrics disabled                  │
│  • Airplane mode enabled                │
└────────────────────┬────────────────────┘
                     │
                     │ valid recovery phrase
                     ▼
                ┌──────────┐
                │ RECOVERY │ ──── ► NORMAL
                └──────────┘
```

### Manual Hostile Mode Activation

**Panic Trigger (recommended)**: Press Volume Down 5 times within 3 seconds

**Alternative methods**:
- Remove SIM card
- Toggle airplane mode 3 times quickly
- Via terminal (if accessible):
  ```bash
  su -c 'sh /data/adb/modules/custos/common/hostile_mode.sh activate'
  ```

### Checking Status

```bash
su -c 'sh /data/adb/modules/custos/common/hostile_mode.sh status'
```

---

## Recovery

### Exiting Hostile Mode

1. **Via Terminal** (if you have shell access):
   ```bash
   su -c 'sh /data/adb/modules/custos/common/recovery_validator.sh interactive'
   ```
   Enter your recovery phrase when prompted.

2. **Via Failsafe Timer**: After 72 hours (configurable), hostile mode automatically deactivates.

3. **Via Magisk Manager**: If you can access Magisk, disable the module and reboot.

### Recovery Phrase Management

**Change phrase**:
```bash
su -c 'sh /data/adb/modules/custos/common/recovery_validator.sh set "new_phrase"'
```

**Check status**:
```bash
su -c 'sh /data/adb/modules/custos/common/recovery_validator.sh status'
```

### Failsafe Timer

The failsafe timer prevents permanent lockout:

- Default: 72 hours
- Check remaining time:
  ```bash
  su -c 'sh /data/adb/modules/custos/common/failsafe_timer.sh remaining'
  ```

**WARNING**: Disabling failsafe can lead to permanent lockout:
```bash
su -c 'sh /data/adb/modules/custos/common/failsafe_timer.sh disable --confirm-disable'
```

---

## Technical Details

### USB Defense Mechanism

The module sabotages USB data negotiation at multiple levels:

1. **Android USB Gadget** (`/sys/class/android_usb/android0`)
   - Disables gadget enable
   - Clears function list
   - Removes device identifiers

2. **ConfigFS Gadget** (`/config/usb_gadget/g1`)
   - Detaches from UDC
   - Removes function symlinks (adb, mtp, ptp)
   - Clears configuration strings

3. **USB Role Switch** (`/sys/class/usb_role/`)
   - Forces device mode
   - Disables data role

4. **System Properties**
   - `sys.usb.config=charging`
   - `ro.debuggable=0`
   - `ro.adb.secure=1`

### Key Eviction Process

When hostile mode activates:

1. **Kernel Keyring Invalidation**
   - Clears user keyring (`@u`)
   - Clears session keyring (`@s`)
   - Revokes individual keys

2. **FBE Key Removal**
   - Signals vold to lock crypto
   - Invalidates CE/DE keys

3. **Keystore Flush**
   - Signals keystore daemon
   - Locks credential storage

4. **Session Token Purge**
   - Clears auth tokens from apps
   - Removes session databases
   - Clears OAuth tokens

### Boot Anomaly Detection

Checked in `post-fs-data.sh` (before Zygote):

- Recovery mode indicators
- Verified boot state (red/yellow)
- EDL mode detection
- Boot partition hash verification
- Forensic tool file detection
- Unexpected ADB enabled at boot

---

## Architecture

```
custos/
├── module.prop                 # Module metadata
├── customize.sh                # Installation script
├── service.sh                  # Late-start service (main)
├── post-fs-data.sh            # Early boot defense
├── sepolicy.rule              # SELinux policies
├── uninstall.sh               # Clean uninstallation
├── common/
│   ├── functions.sh           # Shared utilities
│   ├── usb_defense.sh         # USB lockdown
│   ├── adb_neutralizer.sh     # ADB blocking
│   ├── key_eviction.sh        # Key management
│   ├── hostile_mode.sh        # Panic mode logic
│   ├── state_machine.sh       # State transitions
│   ├── recovery_validator.sh  # Phrase validation
│   └── failsafe_timer.sh      # Auto-recovery timer
└── config/
    ├── triggers.conf          # Trigger configuration
    └── boot_hash.txt          # Reference boot hash
```

### Process Architecture

```
                    ┌──────────────────┐
                    │   service.sh     │
                    │  (main service)  │
                    └────────┬─────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
         ▼                   ▼                   ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│  usb_defense.sh │ │adb_neutralizer  │ │ hostile_mode.sh │
│    (monitor)    │ │    (monitor)    │ │    (monitor)    │
└─────────────────┘ └─────────────────┘ └─────────────────┘
         │                   │                   │
         └───────────────────┴───────────────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │ state_machine   │
                    │  (controller)   │
                    └─────────────────┘
```

---

## SELinux Policies

The module includes comprehensive SELinux policies:

### Permissions Granted

- Module daemon: keyring access, USB gadget control, input monitoring
- Property modification for USB/ADB settings
- Signal delivery to adbd process

### Restrictions Applied

- adbd: blocked from content providers, DAC override, devpts
- untrusted_app: blocked from USB gadget modification
- shell: blocked from USB gadget modification
- Forensic protection: blocks access to device identifiers

---

## Troubleshooting

### Device Won't Boot

1. Boot to recovery
2. Access Magisk menu
3. Disable Custos module
4. Reboot

### Forgot Recovery Phrase

Wait for failsafe timer (default 72h) or:

1. Boot to recovery
2. Navigate to Magisk modules
3. Remove `/data/adb/modules/custos`
4. Reboot

### USB Not Working After Disabling Module

```bash
# Restore USB manually
su -c 'sh /data/adb/modules/custos/common/usb_defense.sh restore --force'
```

### Module Not Activating on Boot

Check Magisk logs:
```bash
su -c 'cat /cache/magisk.log | grep -i custos'
```

---

## FAQ

**Q: Will this brick my phone?**
A: No. The failsafe timer ensures you can always recover after 72 hours. Additionally, you can always disable the module via Magisk Manager or recovery.

**Q: Does this work against all forensic tools?**
A: It effectively blocks all USB-based extraction methods. Hardware-level attacks (JTAG, chip-off) are mitigated by key eviction but cannot be completely prevented.

**Q: Can law enforcement still access my data?**
A: With properly implemented encryption (FBE) and this module, data extraction becomes technically impractical. However, legal compulsion may apply in your jurisdiction.

**Q: Will I lose my data?**
A: No. The module does not destroy data - it prevents unauthorized access. Your data remains intact and accessible after recovery.

**Q: How do I test if it's working?**
A: Connect to a computer - it should only appear as a charging device, not show up in ADB or file explorers.

**Q: Can I use ADB while the module is installed?**
A: Yes, but only in normal mode. Hostile mode completely blocks ADB. Use the recovery phrase to exit hostile mode first.

---

## Legal Notice

This software is provided for educational and legitimate security research purposes. The authors are not responsible for any misuse or legal consequences arising from the use of this software.

Always comply with local laws and regulations regarding device security and law enforcement cooperation.

---

## Version History

### v1.0.0
- Initial release
- USB lockdown (charge-only enforcement)
- ADB neutralization
- Key eviction on hostile events
- Boot anomaly detection
- Hostile custody mode with configurable triggers
- Failsafe recovery mechanism
- SELinux policy integration

---

## Credits

- Magisk by topjohnwu
- Android security research community
- Mobile forensics defense research

---

## License

This project is released under the GNU General Public License v3.0.

