#!/system/bin/sh
##########################################################################################
#
# Custos Anti-Forensic Defense Module
# Post-FS-Data Script
#
# This script runs before Zygote starts - critical for early boot defense
#
##########################################################################################

MODDIR="${0%/*}"
DATA_DIR="/data/adb/custos"
STATE_FILE="${DATA_DIR}/state.db"
LOG_TAG="CUSTOS"

# Early logging (before functions.sh is available)
early_log() {
    log -t "$LOG_TAG" -p i "$1" 2>/dev/null
}

early_log "Post-fs-data script starting..."

# Ensure data directory exists
mkdir -p "$DATA_DIR" 2>/dev/null
chmod 700 "$DATA_DIR" 2>/dev/null

##########################################################################################
# BOOT ANOMALY DETECTION
##########################################################################################

detect_abnormal_boot() {
    # Returns:
    #   0 = normal boot
    #   1 = weak anomaly (ALERT)
    #   2 = strong anomaly (HOSTILE)
    
    local weak_anomaly=0
    local strong_anomaly=0
    local weak_reasons=""
    local strong_reasons=""
    
    ####################################################################################
    # STRONG ANOMALIES → Immediate HOSTILE mode
    # These are high-confidence indicators of forensic attack
    ####################################################################################
    
    # 1. Recovery binary present (definite recovery boot)
    if [ -f "/sbin/recovery" ]; then
        strong_anomaly=1
        strong_reasons="${strong_reasons}recovery_binary_present;"
    fi
    
    # 2. Recovery bootmode property
    if [ "$(getprop ro.bootmode)" = "recovery" ]; then
        strong_anomaly=1
        strong_reasons="${strong_reasons}recovery_bootmode;"
    fi
    
    # 3. EDL (Emergency Download) mode - used by Cellebrite for physical extraction
    if [ "$(getprop ro.boot.mode)" = "edl" ]; then
        strong_anomaly=1
        strong_reasons="${strong_reasons}edl_mode;"
    fi
    
    # 4. Known forensic tool files (Cellebrite, Oxygen, etc.)
    FORENSIC_FILES=(
        "/data/local/tmp/mtk_su"
        "/data/local/tmp/magisk"
        "/data/local/tmp/.cellebrite"
        "/data/local/tmp/ufed"
        "/data/local/tmp/oxygen"
        "/data/local/tmp/mobiledit"
        "/data/local/tmp/adb_keys"
    )
    for file in "${FORENSIC_FILES[@]}"; do
        if [ -f "$file" ]; then
            strong_anomaly=1
            strong_reasons="${strong_reasons}forensic_file_${file};"
        fi
    done
    
    # 5. Forensic tool properties (definitely injected)
    FORENSIC_PROPS=(
        "ro.cellebrite"
        "ro.oxygen"
        "ro.mobiledit"
        "sys.forensic"
    )
    for prop in "${FORENSIC_PROPS[@]}"; do
        if [ -n "$(getprop $prop 2>/dev/null)" ]; then
            strong_anomaly=1
            strong_reasons="${strong_reasons}forensic_prop_${prop};"
        fi
    done
    
    # 6. Magisk injection (not installed but binary present)
    if [ ! -f "/data/adb/magisk/magisk64" ] && [ ! -f "/data/adb/magisk/magisk32" ]; then
        if [ -f "/system/bin/magisk" ] || [ -f "/sbin/magisk" ]; then
            strong_anomaly=1
            strong_reasons="${strong_reasons}magisk_injection_detected;"
        fi
    fi
    
    # 7. Verified boot state RED (compromised)
    VBSTATE=$(getprop ro.boot.verifiedbootstate)
    if [ "$VBSTATE" = "red" ]; then
        strong_anomaly=1
        strong_reasons="${strong_reasons}vb_state_red;"
    fi
    
    ####################################################################################
    # WEAK ANOMALIES → ALERT mode (could be legitimate)
    # These may be caused by OTAs, user modifications, or carrier quirks
    ####################################################################################
    
    # 1. Boot hash mismatch (could be OTA update)
    if [ -f "${MODDIR}/config/boot_hash.txt" ]; then
        EXPECTED_HASH=$(cat "${MODDIR}/config/boot_hash.txt" 2>/dev/null)
        if [ "$EXPECTED_HASH" != "UNKNOWN" ] && [ -n "$EXPECTED_HASH" ]; then
            BOOT_HASH=""
            for boot_path in "/dev/block/by-name/boot" "/dev/block/bootdevice/by-name/boot" "/dev/block/platform/*/by-name/boot"; do
                if [ -e "$boot_path" ]; then
                    BOOT_HASH=$(sha256sum "$boot_path" 2>/dev/null | cut -d' ' -f1)
                    break
                fi
            done
            
            if [ -n "$BOOT_HASH" ] && [ "$BOOT_HASH" != "$EXPECTED_HASH" ]; then
                # This is WEAK because OTAs legitimately change boot hash
                weak_anomaly=1
                weak_reasons="${weak_reasons}boot_hash_mismatch;"
                
                # Update the hash to prevent repeated alerts after OTA
                # Only if we're not in hostile mode
                if [ ! -f "${DATA_DIR}/state.db" ] || ! grep -q "HOSTILE" "${DATA_DIR}/state.db"; then
                    echo "$BOOT_HASH" > "${MODDIR}/config/boot_hash.txt"
                    early_log "Boot hash updated (possible OTA): $BOOT_HASH"
                fi
            fi
        fi
    fi
    
    # 2. Unexpected ADB enabled at boot (could be user-enabled)
    if [ "$(getprop persist.sys.usb.config)" = "adb" ]; then
        if [ "$(getprop ro.debuggable)" = "1" ]; then
            if [ ! -f "${DATA_DIR}/.user_adb_enabled" ]; then
                weak_anomaly=1
                weak_reasons="${weak_reasons}unexpected_adb_enabled;"
            fi
        fi
    fi
    
    # 3. USB debugging forced on via boot
    if [ "$(getprop sys.usb.configfs)" = "1" ]; then
        USB_CONFIG=$(cat /config/usb_gadget/g1/configs/b.1/strings/0x409/configuration 2>/dev/null)
        if echo "$USB_CONFIG" | grep -qi "adb"; then
            if [ ! -f "${DATA_DIR}/.user_adb_enabled" ]; then
                weak_anomaly=1
                weak_reasons="${weak_reasons}forced_adb_gadget;"
            fi
        fi
    fi
    
    # 4. Hardware mismatch (could be legitimate hardware change)
    BOOT_SOURCE=$(getprop ro.boot.hardware)
    EXPECTED_HARDWARE=$(cat "${MODDIR}/config/hardware.txt" 2>/dev/null)
    if [ -n "$EXPECTED_HARDWARE" ] && [ "$BOOT_SOURCE" != "$EXPECTED_HARDWARE" ]; then
        weak_anomaly=1
        weak_reasons="${weak_reasons}hardware_mismatch;"
    fi
    
    # 5. Debug tracing enabled (could be developer setting)
    if [ -n "$(getprop debug.atrace.tags.enableflags 2>/dev/null)" ]; then
        weak_anomaly=1
        weak_reasons="${weak_reasons}debug_tracing_enabled;"
    fi
    
    ####################################################################################
    # DETERMINE RESULT
    ####################################################################################
    
    if [ $strong_anomaly -eq 1 ]; then
        early_log "STRONG BOOT ANOMALY DETECTED: $strong_reasons"
        echo "STRONG:${strong_reasons}" > "${DATA_DIR}/boot_anomaly.log"
        return 2
    elif [ $weak_anomaly -eq 1 ]; then
        early_log "WEAK BOOT ANOMALY DETECTED: $weak_reasons"
        echo "WEAK:${weak_reasons}" > "${DATA_DIR}/boot_anomaly.log"
        return 1
    fi
    
    return 0
}

##########################################################################################
# EARLY DEFENSE ACTIVATION
##########################################################################################

activate_early_defense() {
    early_log "Activating early boot defense..."
    
    # Set hostile state
    echo "HOSTILE:$(date +%s)" > "$STATE_FILE"
    chmod 600 "$STATE_FILE"
    
    # Immediately disable USB data functions at kernel level
    # This happens before any userspace can enable them
    
    # Android USB Gadget (legacy)
    if [ -d "/sys/class/android_usb/android0" ]; then
        echo "0" > /sys/class/android_usb/android0/enable 2>/dev/null
        echo "" > /sys/class/android_usb/android0/functions 2>/dev/null
    fi
    
    # ConfigFS USB Gadget (modern)
    if [ -d "/config/usb_gadget/g1" ]; then
        echo "" > /config/usb_gadget/g1/UDC 2>/dev/null
        rm -f /config/usb_gadget/g1/configs/b.1/ffs.adb 2>/dev/null
        rm -f /config/usb_gadget/g1/configs/b.1/ffs.mtp 2>/dev/null
        rm -f /config/usb_gadget/g1/configs/b.1/ffs.ptp 2>/dev/null
        rm -f /config/usb_gadget/g1/configs/b.1/function* 2>/dev/null
    fi
    
    # Set USB properties to charging only
    resetprop persist.sys.usb.config "charging" 2>/dev/null
    resetprop sys.usb.config "charging" 2>/dev/null
    resetprop sys.usb.state "charging" 2>/dev/null
    resetprop ro.adb.secure "1" 2>/dev/null
    resetprop ro.debuggable "0" 2>/dev/null
    
    # Disable ADB at property level
    resetprop persist.adb.tcp.port "" 2>/dev/null
    resetprop service.adb.tcp.port "" 2>/dev/null
    
    # Bind mount /dev/null over adbd binary
    for adbd_path in "/system/bin/adbd" "/apex/com.android.adbd/bin/adbd" "/sbin/adbd"; do
        if [ -f "$adbd_path" ]; then
            mount --bind /dev/null "$adbd_path" 2>/dev/null
        fi
    done
    
    early_log "Early boot defense activated"
}

##########################################################################################
# MAIN EXECUTION
##########################################################################################

# Check for existing hostile state (persisted from previous boot)
if [ -f "$STATE_FILE" ]; then
    CURRENT_STATE=$(cat "$STATE_FILE" 2>/dev/null | cut -d':' -f1)
    if [ "$CURRENT_STATE" = "HOSTILE" ]; then
        early_log "Hostile state persisted from previous boot - enforcing early defense"
        activate_early_defense
    fi
fi

# Run boot anomaly detection
detect_abnormal_boot
BOOT_RESULT=$?

case $BOOT_RESULT in
    2)
        # STRONG anomaly → immediate HOSTILE
        early_log "Strong boot anomaly triggered hostile mode"
        activate_early_defense
        ;;
    1)
        # WEAK anomaly → ALERT mode (less invasive)
        early_log "Weak boot anomaly detected - entering alert mode"
        echo "ALERT:$(date +%s)" > "$STATE_FILE"
        chmod 600 "$STATE_FILE"
        # Don't activate full defense, just heightened monitoring
        ;;
    0)
        early_log "Boot appears normal"
        
        # Record hardware fingerprint on clean boot (for future comparison)
        HARDWARE=$(getprop ro.boot.hardware)
        if [ -n "$HARDWARE" ]; then
            echo "$HARDWARE" > "${MODDIR}/config/hardware.txt" 2>/dev/null
        fi
        ;;
esac

# Always ensure some baseline protections even in normal mode
# This prevents forensic tools from enabling ADB before our service starts

# Ensure development settings are disabled by default
settings put global development_settings_enabled 0 2>/dev/null
settings put global adb_enabled 0 2>/dev/null

# Set strict USB default
resetprop sys.usb.config "charging" 2>/dev/null

early_log "Post-fs-data script completed"

