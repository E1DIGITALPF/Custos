#!/system/bin/sh
##########################################################################################
#
# Custos Anti-Forensic Defense Module
# Common Functions Library
#
##########################################################################################

# Configuration paths
MODDIR="${MODDIR:-/data/adb/modules/custos}"
DATA_DIR="/data/adb/custos"
STATE_FILE="${DATA_DIR}/state.db"
LOG_TAG="CUSTOS"

# Logging functions
log_info() {
    log -t "$LOG_TAG" -p i "$1"
}

log_warn() {
    log -t "$LOG_TAG" -p w "$1"
}

log_error() {
    log -t "$LOG_TAG" -p e "$1"
}

log_debug() {
    [ "$DEBUG" = "1" ] && log -t "$LOG_TAG" -p d "$1"
}

# State management
get_current_state() {
    if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE" 2>/dev/null | cut -d':' -f1
    else
        echo "UNKNOWN"
    fi
}

get_state_timestamp() {
    if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE" 2>/dev/null | cut -d':' -f2
    else
        echo "0"
    fi
}

set_state() {
    local new_state="$1"
    local timestamp=$(date +%s)
    echo "${new_state}:${timestamp}" > "$STATE_FILE"
    chmod 600 "$STATE_FILE"
    log_info "State changed to: $new_state"
}

is_hostile_mode() {
    [ "$(get_current_state)" = "HOSTILE" ]
}

is_alert_mode() {
    [ "$(get_current_state)" = "ALERT" ]
}

is_normal_mode() {
    [ "$(get_current_state)" = "NORMAL" ]
}

# Property manipulation (Magisk resetprop)
safe_resetprop() {
    local prop="$1"
    local value="$2"
    
    if command -v resetprop >/dev/null 2>&1; then
        resetprop "$prop" "$value" 2>/dev/null
        return $?
    else
        setprop "$prop" "$value" 2>/dev/null
        return $?
    fi
}

safe_resetprop_delete() {
    local prop="$1"
    
    if command -v resetprop >/dev/null 2>&1; then
        resetprop --delete "$prop" 2>/dev/null
        return $?
    fi
    return 1
}

# USB state helpers
get_usb_state_path() {
    if [ -d "/sys/class/android_usb/android0" ]; then
        echo "/sys/class/android_usb/android0"
    elif [ -d "/config/usb_gadget/g1" ]; then
        echo "/config/usb_gadget/g1"
    else
        echo ""
    fi
}

is_usb_connected() {
    local usb_state=$(cat /sys/class/power_supply/usb/online 2>/dev/null)
    [ "$usb_state" = "1" ]
}

get_usb_mode() {
    local path=$(get_usb_state_path)
    if [ -n "$path" ] && [ -f "${path}/functions" ]; then
        cat "${path}/functions" 2>/dev/null
    else
        echo "unknown"
    fi
}

# Screen state helpers
is_screen_on() {
    local state=$(dumpsys power 2>/dev/null | grep "Display Power" | grep -c "ON")
    [ "$state" -gt 0 ]
}

is_device_locked() {
    local locked=$(dumpsys window 2>/dev/null | grep -c "mDreamingLockscreen=true")
    [ "$locked" -gt 0 ]
}

lock_screen_now() {
    input keyevent 26  # KEYCODE_POWER
}

# Process management
is_process_running() {
    local process_name="$1"
    pgrep -f "$process_name" >/dev/null 2>&1
}

kill_process_tree() {
    local process_name="$1"
    pkill -9 -f "$process_name" 2>/dev/null
}

# File operations with security
secure_write() {
    local file="$1"
    local content="$2"
    
    echo "$content" > "$file" 2>/dev/null
    chmod 600 "$file" 2>/dev/null
    chown 0:0 "$file" 2>/dev/null
}

secure_delete() {
    local file="$1"
    
    if [ -f "$file" ]; then
        # Overwrite with zeros before deletion
        dd if=/dev/zero of="$file" bs=1 count=$(stat -c%s "$file" 2>/dev/null) conv=notrunc 2>/dev/null
        sync
        rm -f "$file" 2>/dev/null
    fi
}

# Cryptographic helpers
compute_sha512() {
    echo -n "$1" | sha512sum | cut -d' ' -f1
}

compute_sha256() {
    echo -n "$1" | sha256sum | cut -d' ' -f1
}

# System information
get_android_version() {
    getprop ro.build.version.release
}

get_security_patch() {
    getprop ro.build.version.security_patch
}

get_boot_mode() {
    getprop ro.bootmode
}

is_device_encrypted() {
    local state=$(getprop ro.crypto.state)
    [ "$state" = "encrypted" ]
}

# Network control
enable_airplane_mode() {
    settings put global airplane_mode_on 1 2>/dev/null
    am broadcast -a android.intent.action.AIRPLANE_MODE --ez state true 2>/dev/null
    log_info "Airplane mode enabled"
}

disable_airplane_mode() {
    settings put global airplane_mode_on 0 2>/dev/null
    am broadcast -a android.intent.action.AIRPLANE_MODE --ez state false 2>/dev/null
    log_info "Airplane mode disabled"
}

# Biometric control
disable_biometrics() {
    # Cancel any ongoing fingerprint authentication
    cmd fingerprint cancel 2>/dev/null
    
    # Disable fingerprint unlock temporarily
    settings put secure fingerprint_enabled 0 2>/dev/null
    
    log_info "Biometrics disabled"
}

enable_biometrics() {
    settings put secure fingerprint_enabled 1 2>/dev/null
    log_info "Biometrics enabled"
}

# Wait for system boot
wait_for_boot_complete() {
    local timeout=${1:-120}
    local elapsed=0
    
    while [ "$(getprop sys.boot_completed)" != "1" ]; do
        sleep 1
        elapsed=$((elapsed + 1))
        if [ $elapsed -ge $timeout ]; then
            log_warn "Boot wait timeout after ${timeout}s"
            return 1
        fi
    done
    
    log_info "System boot completed"
    return 0
}

# Verify module integrity
verify_module_integrity() {
    local critical_files=(
        "${MODDIR}/service.sh"
        "${MODDIR}/post-fs-data.sh"
        "${MODDIR}/common/usb_defense.sh"
        "${MODDIR}/common/adb_neutralizer.sh"
        "${MODDIR}/common/hostile_mode.sh"
    )
    
    for file in "${critical_files[@]}"; do
        if [ ! -f "$file" ]; then
            log_error "Critical file missing: $file"
            return 1
        fi
    done
    
    return 0
}

