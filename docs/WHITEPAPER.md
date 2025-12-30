# Custos: A Defensive Framework for Mobile Privacy Protection

**Technical Whitepaper v1.0**

**Authors:** E1DIGITAL
**Date:** December 2025  
**Classification:** Public

---

## Abstract

This document presents Custos, a defensive software framework designed to protect mobile device users from unauthorized data extraction through commercial forensic tools. The framework implements multiple layers of defense that leverage existing Android security mechanisms to ensure data remains encrypted and inaccessible during hostile custody scenarios, without destroying or modifying user data.

This whitepaper establishes the technical foundation, threat model, architectural decisions, and ethical considerations underlying the Custos framework.

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Threat Model](#2-threat-model)
3. [Commercial Forensic Tool Analysis](#3-commercial-forensic-tool-analysis)
4. [Defensive Architecture](#4-defensive-architecture)
5. [Key Eviction as Legitimate Defense](#5-key-eviction-as-legitimate-defense)
6. [Security vs Usability Tradeoffs](#6-security-vs-usability-tradeoffs)
7. [Legal and Ethical Considerations](#7-legal-and-ethical-considerations)
8. [Known Limitations](#8-known-limitations)
9. [Conclusion](#9-conclusion)
10. [References](#10-references)

---

## 1. Executive Summary

### 1.1 The Problem

Commercial mobile forensic tools have become widely accessible beyond their intended law enforcement use cases. Products such as Cellebrite UFED, Oxygen Forensic Detective, and MOBILedit Forensic are now available to:

- Corporate security departments
- Private investigation firms
- Border control agencies worldwide
- Malicious actors through secondary markets

These tools exploit standard USB interfaces and operating system cooperation mechanisms—not cryptographic vulnerabilities—to extract sensitive personal data including messages, contacts, photos, location history, and authentication tokens.

### 1.2 The Risk

The average mobile device user faces potential data extraction in scenarios including:

- **Border crossings:** Devices may be seized and analyzed during international travel
- **Device theft:** Sophisticated thieves may attempt data extraction before resale
- **Corporate espionage:** Competitors may target employee devices
- **Administrative seizure:** Devices confiscated in civil or administrative proceedings

In each scenario, the user's encrypted data becomes vulnerable if encryption keys remain accessible in device memory.

### 1.3 Our Approach

Custos implements **proportional, non-destructive defense** that:

1. **Prevents USB data channel negotiation** — Device appears as charge-only
2. **Neutralizes debug interfaces** — ADB becomes non-functional
3. **Evicts encryption keys from memory** — Data remains encrypted without accessible keys
4. **Preserves all user data** — No deletion, wiping, or modification occurs

The framework ensures that users retain full access to their data after authenticating with their recovery credentials, while making extraction technically impractical for unauthorized parties.

---

## 2. Threat Model

### 2.1 In-Scope Threat Actors

Custos is designed to defend against the following actors and scenarios:

| Actor | Scenario | Capabilities | Goal |
|-------|----------|--------------|------|
| **Opportunistic Thief** | Device theft | Physical access, commodity tools | Data monetization, identity theft |
| **Border Agent** | Port of entry inspection | Physical access, commercial forensic tools, time-limited | Intelligence gathering, compliance verification |
| **Corporate Adversary** | Device seizure during employment dispute | Physical access, professional forensic services | Competitive intelligence, evidence gathering |
| **Administrative Authority** | Civil proceeding seizure | Physical access, court-authorized forensics | Evidence extraction without criminal warrant |

**Common characteristics of in-scope threats:**
- Rely on USB-based extraction methods
- Use commercial forensic tools (not custom exploits)
- Operate within time constraints
- Expect device cooperation (unlocked or exploitable state)

### 2.2 Out-of-Scope Threats

The following threats are **explicitly outside** the defensive scope of Custos:

| Threat | Reason |
|--------|--------|
| **Chip-off attacks** | Physical removal of storage chips bypasses all software defenses |
| **Advanced JTAG** | Direct hardware debugging interfaces cannot be blocked by software |
| **Implanted hardware** | Pre-installed surveillance hardware operates below OS level |
| **Legal compulsion** | Court orders compelling password disclosure are legal matters, not technical |
| **Nation-state actors** | Zero-day exploits and unlimited resources exceed defensive scope |
| **Device unlocking by user** | If the user unlocks the device, extraction becomes trivial |

### 2.3 Security Assumptions

Custos assumes:

1. **File-Based Encryption (FBE) is enabled** — Android 7.0+ with properly configured encryption
2. **Secure lock screen is configured** — PIN, password, or pattern (not "none" or "swipe")
3. **Bootloader state is known** — The framework operates with both locked and unlocked bootloaders, but behavior differs
4. **User does not cooperate** — The user does not voluntarily unlock the device or provide credentials

---

## 3. Commercial Forensic Tool Analysis

### 3.1 Methodology

This analysis examines the extraction capabilities of major commercial forensic tools based on publicly available documentation, training materials, and technical specifications. No proprietary systems were reverse-engineered.

### 3.2 Cellebrite UFED

**Vendor:** Cellebrite DI Ltd.  
**Primary Market:** Law enforcement, government agencies

#### Extraction Methods

| Method | Mechanism | Custos Defense |
|--------|-----------|---------------------|
| Logical Extraction | ADB backup, content provider queries | ADB neutralization, USB lockdown |
| File System Extraction | ADB root shell, file copying | ADB neutralization, key eviction |
| Physical Extraction | Bootloader exploits, custom recovery | Boot anomaly detection, key eviction |
| Advanced Logical | Agent app installation via ADB | ADB neutralization, USB lockdown |

#### Technical Observations

UFED's extraction capabilities rely fundamentally on **USB data negotiation** and **operating system cooperation**. The tool does not break cryptographic protections; rather, it accesses data that the operating system makes available through standard interfaces.

When USB data channels are unavailable, UFED cannot establish the communication necessary for any extraction method.

### 3.3 Oxygen Forensic Detective

**Vendor:** Oxygen Forensics  
**Primary Market:** Law enforcement, corporate security

#### Extraction Methods

| Method | Mechanism | Custos Defense |
|--------|-----------|---------------------|
| Android Logical | ADB shell commands | ADB neutralization |
| Android Physical | Chipset-specific exploits | Boot anomaly detection, key eviction |
| Cloud Extraction | Stored authentication tokens | Token purge on hostile events |
| Logical Plus | Root-level file access | ADB neutralization, key eviction |

#### Technical Observations

Oxygen Forensic Detective emphasizes **cloud extraction** using cached authentication tokens. This represents a significant threat vector as tokens may persist even when local data is protected.

Custos addresses this through **session token purge** during hostile mode activation, invalidating cached OAuth tokens, session cookies, and authentication credentials.

### 3.4 MOBILedit Forensic

**Vendor:** Compelson Labs  
**Primary Market:** Law enforcement, forensic laboratories

#### Extraction Methods

| Method | Mechanism | Custos Defense |
|--------|-----------|---------------------|
| Logical Extraction | ADB, MTP/PTP protocols | ADB neutralization, USB lockdown |
| Physical Extraction | Rooted device file access | ADB neutralization, key eviction |
| Application Analysis | APK and app data extraction | USB lockdown, content provider protection |

#### Technical Observations

MOBILedit is **entirely dependent** on USB connectivity for Android extraction. Without successful USB data negotiation, the tool cannot interact with the device in any meaningful way.

### 3.5 Common Vulnerability

All analyzed tools share a fundamental dependency:

> **They rely on USB data negotiation and OS cooperation rather than cryptographic breaks.**

This architectural dependency creates the defensive opportunity that Custos exploits.

---

## 4. Defensive Architecture

### 4.1 Design Principles

Custos is built on four core principles:

1. **Defense in Depth** — Multiple independent layers, each providing protection
2. **Fail-Secure** — Default to maximum protection when state is uncertain
3. **Non-Destructive** — Never delete, modify, or corrupt user data
4. **Recoverable** — User always retains path to normal operation

### 4.2 State Machine

The framework operates through a formal state machine ensuring consistent, predictable behavior:

```
┌─────────┐                              ┌──────────┐
│ NORMAL  │ ─── suspicious event ──────► │  ALERT   │
└────┬────┘                              └────┬─────┘
     │                                        │
     │ confirmed threat                       │ escalation
     │                                        │
     ▼                                        ▼
┌────────────────────────────────────────────────────┐
│                    HOSTILE                          │
│  • USB charge-only         • Keys evicted          │
│  • ADB neutralized         • Biometrics disabled   │
│  • Network isolated        • Screen locked         │
└──────────────────────┬─────────────────────────────┘
                       │
                       │ valid recovery phrase
                       ▼
                 ┌──────────┐
                 │ RECOVERY │ ───────► NORMAL
                 └──────────┘
```

### 4.3 Defensive Layers

#### Layer 1: USB Defense

**Objective:** Prevent data channel establishment

**Mechanism:**
- Clear USB gadget functions (MTP, PTP, ADB)
- Disable USB device controller (UDC)
- Set USB mode properties to "charging"
- Monitor for re-enablement attempts

**Result:** Device enumerates as charging-only; no data interface available

#### Layer 2: ADB Neutralization

**Objective:** Eliminate debug bridge as extraction vector

**Mechanism:**
- Terminate adbd process continuously
- Clear ADB socket and FunctionFS endpoints
- Disable development settings and ADB properties
- Remove authorized ADB keys

**Result:** ADB commands return "device not found"

#### Layer 3: Key Eviction

**Objective:** Ensure encrypted data remains inaccessible

**Mechanism:**
- Invalidate kernel keyring entries (FBE keys)
- Signal vold to lock cryptographic state
- Clear biometric authentication cache
- Purge session tokens and OAuth credentials

**Result:** Encrypted partitions become inaccessible without re-authentication

#### Layer 4: Policy Enforcement

**Objective:** Provide kernel-level protection baseline

**Mechanism:**
- SELinux policies restricting adbd capabilities
- Block content provider access from debug contexts
- Prevent USB gadget modification by non-init processes

**Result:** Defense persists even if userspace mechanisms are bypassed

### 4.4 Trigger System

Hostile mode activation occurs through:

| Trigger Type | Example | Confidence | Response |
|--------------|---------|------------|----------|
| Manual | Volume down x5 in 3s | High | HOSTILE |
| Compound | SIM removal + USB | High | HOSTILE |
| Single suspicious | SIM removal alone | Medium | ALERT |
| Boot anomaly (strong) | Recovery mode, forensic files | High | HOSTILE |
| Boot anomaly (weak) | Hash mismatch | Low | ALERT |

Compound triggers reduce false positives while maintaining security against genuine threats.

---

## 5. Key Eviction as Legitimate Defense

### 5.1 Understanding Key Eviction

Key eviction is the process of removing cryptographic keys from memory, rendering encrypted data inaccessible until re-authentication occurs.

**This is not data destruction.** The encrypted data remains intact; only the means to decrypt it is temporarily removed.

### 5.2 Android's Native Key Eviction

Android already implements key eviction in several scenarios:

| Scenario | Android Behavior |
|----------|------------------|
| Screen lock timeout | CE (Credential Encrypted) keys may be evicted |
| User logout (work profile) | Work profile keys evicted |
| Device reboot | All runtime keys cleared |
| Failed authentication limit | Key access locked |

Custos extends this native behavior to **hostile custody scenarios** where the user cannot manually lock their device.

### 5.3 What Custos Evicts

| Key Type | Source | Effect |
|----------|--------|--------|
| FBE CE keys | Kernel keyring | User data partition inaccessible |
| Session keys | Keystore daemon | App credentials invalidated |
| OAuth tokens | App storage | Cloud services require re-auth |
| Biometric keys | TEE cache | Fingerprint/face unlock disabled |

### 5.4 What Remains Intact

| Data Type | Status |
|-----------|--------|
| Encrypted files | Unchanged (still encrypted) |
| System partition | Unchanged |
| App binaries | Unchanged |
| User configuration | Unchanged |

### 5.5 Recovery Path

After key eviction, the user recovers access by:

1. Entering their lock screen PIN/password/pattern
2. Entering their Custos recovery phrase (if in hostile mode)
3. Waiting for failsafe timer expiration (72h default)

No data is lost. The device returns to normal operation.

---

## 6. Security vs Usability Tradeoffs

### 6.1 Design Philosophy

Maximum security and maximum usability are opposing forces. Custos explicitly prioritizes usability within security constraints:

> **Security that users disable is no security at all.**

### 6.2 Tradeoff Decisions

#### SIM Removal → ALERT (not HOSTILE)

**Rationale:**
- Dual-SIM devices generate SIM events during normal operation
- eSIM transitions cause false positives
- Travel scenarios involve legitimate SIM changes

**Decision:** Single SIM removal triggers ALERT; HOSTILE requires compound trigger (SIM + USB).

#### Boot Hash Mismatch → ALERT (not HOSTILE)

**Rationale:**
- OTA updates legitimately change boot partition
- Users should not be locked out after system updates

**Decision:** Weak boot anomalies trigger ALERT with automatic hash update; only strong anomalies (recovery mode, forensic files) trigger HOSTILE.

#### Failsafe Timer (72 hours)

**Rationale:**
- Users may forget recovery phrase
- Legitimate scenarios may require extended hostile mode
- Permanent lockout serves no one

**Decision:** Configurable failsafe timer (default 72h) automatically restores normal mode.

#### Bind Mounts (HOSTILE only)

**Rationale:**
- Bind mounting over binaries can break OTA updates
- Aggressive techniques should be reserved for confirmed threats

**Decision:** Invasive measures like bind mounts apply only in HOSTILE state, not NORMAL or ALERT.

### 6.3 State-Appropriate Responses

| State | USB | ADB | Keys | Usability |
|-------|-----|-----|------|-----------|
| NORMAL | Full function | User setting | Normal | Full |
| TRAVELER | Restricted | Disabled | Locked | Normal phone use |
| ALERT | Monitored | Monitored | Normal | Full |
| HOSTILE | Charge-only | Neutralized | Evicted | Lock screen only |

---

## 7. Legal and Ethical Considerations

### 7.1 Fundamental Position

Custos is a **privacy protection tool**, not an evidence destruction tool.

| What Custos Does | What Custos Does NOT Do |
|----------------------|------------------------------|
| Prevents unauthorized access | Destroy data |
| Maintains encryption state | Modify files |
| Evicts session keys | Delete evidence |
| Locks device | Obstruct lawful court orders |

### 7.2 Data Preservation

At no point does Custos:

- Delete user files
- Modify file contents
- Corrupt databases
- Wipe storage partitions
- Overwrite sectors

All data remains intact and accessible after recovery authentication.

### 7.3 User Authority

The device owner retains full authority:

- Recovery phrase provides immediate access
- Failsafe timer ensures eventual access
- Magisk manager can disable module
- Factory reset remains available

### 7.4 Lawful Access Considerations

Custos does not prevent lawful access:

1. **With user cooperation:** User can enter credentials
2. **With court order compelling disclosure:** Legal remedy exists
3. **After failsafe expiration:** Device returns to normal

The framework protects against **unauthorized** extraction, not **all** extraction.

### 7.5 Jurisdictional Awareness

Users are responsible for understanding their legal obligations. In some jurisdictions:

- Failure to provide passwords may be an offense
- Device encryption itself is restricted
- Border agents have broad device access authority

Custos is a technical tool; legal compliance remains the user's responsibility.

---

## 8. Known Limitations

### 8.1 Hardware-Level Attacks

| Attack | Status |
|--------|--------|
| Chip-off | NOT DEFENDED — Physical memory extraction bypasses all software |
| JTAG | NOT DEFENDED — Hardware debug interfaces operate below OS |
| Cold boot | PARTIALLY DEFENDED — Key eviction reduces window, but not eliminated |
| ISP (In-System Programming) | NOT DEFENDED — Direct chip communication bypasses OS |

### 8.2 Advanced Software Attacks

| Attack | Status |
|--------|--------|
| Zero-day kernel exploits | NOT DEFENDED — Unknown vulnerabilities cannot be predicted |
| Bootloader exploits | PARTIALLY DEFENDED — Boot anomaly detection may trigger, but sophisticated exploits may evade |
| Pre-installed malware | NOT DEFENDED — Malware with system privileges can disable module |

### 8.3 Operational Limitations

| Limitation | Mitigation |
|------------|------------|
| User forgets recovery phrase | Failsafe timer provides eventual recovery |
| OTA updates may fail | Bind mounts only in HOSTILE; normal updates unaffected |
| Battery drain in HOSTILE | Aggressive monitoring uses additional power |
| False positives | Compound triggers and ALERT state reduce impact |

### 8.4 Scope Boundaries

Custos protects **data at rest** when the device is locked. It does not protect:

- Data transmitted over network
- Data displayed on unlocked screen
- Data shared with cloud services
- Data on external storage without encryption

---

## 9. Conclusion

Custos provides meaningful defense against the practical extraction vectors employed by commercial forensic tools. By understanding that these tools depend on USB cooperation and accessible encryption keys—not cryptographic breaks—the framework implements targeted countermeasures that:

1. Render USB extraction technically impractical
2. Ensure encryption keys are unavailable during hostile custody
3. Preserve all user data for recovery after authentication
4. Balance security with operational usability

The framework is neither perfect nor comprehensive. Advanced hardware attacks and sophisticated adversaries may succeed. However, for the defined threat model—commercial forensic tools in time-limited custody scenarios—Custos significantly raises the technical barrier to unauthorized data extraction.

Privacy is a fundamental right. Custos provides technical means to exercise that right.

---

## 10. References

### Standards and Specifications

1. Android Security Bulletin — source.android.com/security
2. File-Based Encryption (FBE) — source.android.com/security/encryption
3. Android Keystore System — developer.android.com/training/articles/keystore
4. USB Gadget ConfigFS — kernel.org/doc/Documentation/usb/gadget_configfs.txt
5. SELinux on Android — source.android.com/security/selinux

### Forensic Tool Documentation

6. Cellebrite UFED Product Documentation (public materials)
7. Oxygen Forensic Detective Technical Specifications (public materials)
8. MOBILedit Forensic Feature Overview (public materials)

### Academic Research

9. "Security Analysis of Mobile Device Forensics" — Various academic papers
10. "Key Management in Mobile Devices" — IEEE Security & Privacy
11. "USB Security Mechanisms" — USENIX Security Symposium

### Legal References

12. Electronic Frontier Foundation — Border Search Resources
13. ACLU — Rights at the Border
14. GDPR Article 32 — Security of Processing

---

## Document History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | December 2025 | Initial release |

---

## License

This document is released under Creative Commons Attribution 4.0 International (CC BY 4.0).

You are free to share and adapt this material for any purpose, including commercial, with appropriate attribution.

---

*Custos Framework — Defending Privacy Through Engineering*

