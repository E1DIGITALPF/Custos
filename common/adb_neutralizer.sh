#!/system/bin/sh
##########################################################################################
#
# Custos Anti-Forensic Defense Module
# ADB Neutralizer Component
#
# Completely neutralizes the Android Debug Bridge even when externally forced
# Defeats: All forensic tools that rely on ADB for extraction
#
##########################################################################################

MODDIR="${0%/*}/.."
. "${MODDIR}/common/functions.sh"

# Known adbd binary paths across different Android versions
ADBD_PATHS=(
    "/system/bin/adbd"
    "/apex/com.android.adbd/bin/adbd"
    "/sbin/adbd"
    "/system/xbin/adbd"
    "/vendor/bin/adbd"
)

# ADB socket paths
ADB_SOCKET_PATHS=(
    "/dev/socket/adbd"
    "/dev/usb-ffs/adb"
    "/dev/android_adb"
    "/sys/class/android_usb/android0/f_adb"
)

# Lock file
LOCK_FILE="/data/adb/custos/.adb_lock"

##########################################################################################
# BINARY IMMOBILIZATION
##########################################################################################

immobilize_adbd_binaries() {
    # IMPORTANT: Bind mount is a LAST RESORT measure
    # Only used in HOSTILE mode to prevent forensic tool injection
    # This can break OTAs and cause subtle issues - use sparingly
    
    if ! is_hostile_mode; then
        log_debug "Skipping binary immobilization - not in hostile mode"
        return 0
    fi
    
    log_info "Immobilizing adbd binaries (HOSTILE mode only)"
    
    for path in "${ADBD_PATHS[@]}"; do
        if [ -f "$path" ]; then
            # Check if already mounted over
            if ! mount | grep -q "$path"; then
                # Bind mount /dev/null over the binary
                mount --bind /dev/null "$path" 2>/dev/null
                if [ $? -eq 0 ]; then
                    log_debug "Immobilized: $path"
                else
                    log_warn "Failed to immobilize: $path"
                fi
            fi
        fi
    done
    
    # Immobilize adb daemon socket (HOSTILE only)
    for socket_path in "${ADB_SOCKET_PATHS[@]}"; do
        if [ -e "$socket_path" ]; then
            umount "$socket_path" 2>/dev/null
            rm -f "$socket_path" 2>/dev/null
        fi
    done
}

##########################################################################################
# PROCESS KILLING
##########################################################################################

kill_adbd_process() {
    local killed=0
    
    # Kill by exact name
    if pkill -9 -x "adbd" 2>/dev/null; then
        killed=1
    fi
    
    # Kill by pattern (catches renamed processes)
    if pkill -9 -f "^adbd" 2>/dev/null; then
        killed=1
    fi
    
    # Kill via PID file if exists
    if [ -f "/dev/.adbd.pid" ]; then
        local pid=$(cat /dev/.adbd.pid 2>/dev/null)
        if [ -n "$pid" ]; then
            kill -9 "$pid" 2>/dev/null && killed=1
        fi
        rm -f /dev/.adbd.pid 2>/dev/null
    fi
    
    # Find and kill any process with adb in cmdline
    for pid in $(ps -A -o pid,args 2>/dev/null | grep -i "adb" | grep -v grep | awk '{print $1}'); do
        kill -9 "$pid" 2>/dev/null && killed=1
    done
    
    return $killed
}

##########################################################################################
# PROPERTY LOCKDOWN
##########################################################################################

lockdown_adb_properties() {
    log_debug "Locking down ADB properties"
    
    # Disable ADB
    safe_resetprop persist.sys.usb.config "charging"
    safe_resetprop sys.usb.config "charging"
    safe_resetprop sys.usb.state "charging"
    
    # Secure ADB
    safe_resetprop ro.adb.secure "1"
    safe_resetprop ro.debuggable "0"
    safe_resetprop ro.secure "1"
    
    # Disable ADB over network
    safe_resetprop persist.adb.tcp.port ""
    safe_resetprop service.adb.tcp.port ""
    safe_resetprop service.adb.tcp.enable "0"
    
    # Disable USB debugging authorization
    safe_resetprop persist.sys.usb.debug "0"
    safe_resetprop persist.service.adb.enable "0"
    safe_resetprop persist.service.debuggable "0"
    
    # ADB authorization
    safe_resetprop ro.adb.nonblocking_ffs "0"
    safe_resetprop sys.usb.ffs.ready "0"
    
    # Disable developer options
    settings put global development_settings_enabled 0 2>/dev/null
    settings put global adb_enabled 0 2>/dev/null
    settings put secure adb_enabled 0 2>/dev/null
    
    # Clear ADB keys to prevent authorized devices from connecting
    rm -f /data/misc/adb/adb_keys 2>/dev/null
    rm -f /data/misc/adb/adb_temp_keys.xml 2>/dev/null
}

##########################################################################################
# SERVICE CONTROL
##########################################################################################

stop_adb_services() {
    log_debug "Stopping ADB services"
    
    # Stop via init
    stop adbd 2>/dev/null
    stop adb 2>/dev/null
    
    # Disable via setprop
    setprop ctl.stop adbd 2>/dev/null
    
    # For newer Android versions with APEX
    if [ -d "/apex/com.android.adbd" ]; then
        # Try to disable the APEX (may not work without remount)
        pm disable com.android.adbd 2>/dev/null
    fi
    
    # Disable USB debugging notification listener
    pm disable-user --user 0 com.android.systemui/.usb.UsbDebuggingActivity 2>/dev/null
}

##########################################################################################
# SOCKET PROTECTION
##########################################################################################

protect_adb_sockets() {
    log_debug "Protecting ADB sockets"
    
    # Remove and recreate socket directory with restricted permissions
    for socket_path in "${ADB_SOCKET_PATHS[@]}"; do
        if [ -e "$socket_path" ]; then
            umount "$socket_path" 2>/dev/null
            rm -rf "$socket_path" 2>/dev/null
        fi
        
        # Create a dummy file to prevent recreation
        touch "$socket_path" 2>/dev/null
        chmod 000 "$socket_path" 2>/dev/null
        chown root:root "$socket_path" 2>/dev/null
        chattr +i "$socket_path" 2>/dev/null  # Make immutable if available
    done
    
    # Protect FunctionFS for ADB
    if [ -d "/dev/usb-ffs/adb" ]; then
        rm -rf /dev/usb-ffs/adb/* 2>/dev/null
        chmod 000 /dev/usb-ffs/adb 2>/dev/null
    fi
}

##########################################################################################
# FULL ADB NEUTRALIZATION
##########################################################################################

neutralize_adb() {
    log_info "Executing ADB neutralization"
    
    # Acquire lock
    exec 200>"$LOCK_FILE"
    flock -n 200 || {
        log_debug "Neutralization already in progress"
        return 0
    }
    
    # PRIORITY ORDER (least invasive to most invasive):
    # 1. Properties & settings (safest, reversible)
    # 2. Process killing (immediate effect)
    # 3. Service stopping (init-level)
    # 4. Socket protection (filesystem-level)
    # 5. Bind mount (ONLY in HOSTILE - can break OTAs)
    
    # Step 1: Lock properties (safest first)
    lockdown_adb_properties
    
    # Step 2: Stop services
    stop_adb_services
    
    # Step 3: Kill any running adbd
    kill_adbd_process
    
    # Step 4: Protect sockets
    protect_adb_sockets
    
    # Step 5: Bind mount over binaries (HOSTILE mode only - last resort)
    # This is invasive and can cause issues with OTAs
    immobilize_adbd_binaries
    
    # Release lock
    flock -u 200
    
    log_info "ADB neutralization complete"
}

##########################################################################################
# CONTINUOUS MONITORING
##########################################################################################

monitor_adb() {
    log_info "Starting ADB neutralizer monitor"
    
    # Initial neutralization
    neutralize_adb
    
    # Monitoring loop
    while true; do
        # Check if adbd is running
        if pgrep -x "adbd" >/dev/null 2>&1; then
            log_warn "adbd process detected - killing immediately"
            kill_adbd_process
            
            # Re-immobilize binaries (they may have been restored)
            immobilize_adbd_binaries
            
            # If this happens repeatedly in hostile mode, it's likely a forensic attack
            if is_hostile_mode; then
                log_warn "adbd respawn in hostile mode - possible forensic attack"
                # Additional defensive measures
                protect_adb_sockets
            fi
        fi
        
        # Check if ADB properties have been changed
        current_config=$(getprop sys.usb.config)
        if echo "$current_config" | grep -qi "adb"; then
            log_warn "ADB detected in USB config - resetting"
            lockdown_adb_properties
        fi
        
        # Check ADB enabled setting
        adb_enabled=$(settings get global adb_enabled 2>/dev/null)
        if [ "$adb_enabled" = "1" ]; then
            log_warn "ADB setting enabled - disabling"
            settings put global adb_enabled 0 2>/dev/null
        fi
        
        # Check for TCP ADB attempts
        tcp_port=$(getprop service.adb.tcp.port)
        if [ -n "$tcp_port" ] && [ "$tcp_port" != "0" ]; then
            log_warn "ADB TCP port detected: $tcp_port - disabling"
            safe_resetprop service.adb.tcp.port ""
            safe_resetprop persist.adb.tcp.port ""
        fi
        
        # Check socket existence
        for socket_path in "${ADB_SOCKET_PATHS[@]}"; do
            if [ -S "$socket_path" ]; then
                log_warn "ADB socket detected: $socket_path - removing"
                rm -f "$socket_path" 2>/dev/null
            fi
        done
        
        # Aggressive interval in hostile mode, relaxed otherwise
        if is_hostile_mode; then
            sleep 0.3
        else
            sleep 1
        fi
    done
}

##########################################################################################
# RESTORE ADB (FOR RECOVERY)
##########################################################################################

restore_adb() {
    log_info "Restoring ADB functionality"
    
    # Only allow if recovery phrase validated
    if [ "$1" != "--force" ] && [ ! -f "/data/adb/custos/.recovery_validated" ]; then
        log_error "Recovery not validated - ADB restore denied"
        return 1
    fi
    
    # Unmount binaries
    for path in "${ADBD_PATHS[@]}"; do
        if [ -f "$path" ]; then
            umount "$path" 2>/dev/null
        fi
    done
    
    # Restore properties
    safe_resetprop persist.sys.usb.config "mtp,adb"
    safe_resetprop sys.usb.config "mtp,adb"
    safe_resetprop ro.debuggable "1"
    
    # Enable settings
    settings put global development_settings_enabled 1 2>/dev/null
    settings put global adb_enabled 1 2>/dev/null
    
    # Start adbd
    start adbd 2>/dev/null
    
    log_info "ADB functionality restored"
    return 0
}

##########################################################################################
# MAIN EXECUTION
##########################################################################################

case "$1" in
    "neutralize")
        neutralize_adb
        ;;
    "monitor")
        monitor_adb
        ;;
    "restore")
        restore_adb "$2"
        ;;
    "kill")
        kill_adbd_process
        ;;
    "status")
        echo "=== ADB Status ==="
        echo "adbd running: $(pgrep -x adbd >/dev/null && echo 'YES' || echo 'NO')"
        echo "USB config: $(getprop sys.usb.config)"
        echo "ADB enabled: $(settings get global adb_enabled 2>/dev/null)"
        echo "Debuggable: $(getprop ro.debuggable)"
        echo "TCP port: $(getprop service.adb.tcp.port)"
        
        echo ""
        echo "=== Binary Status ==="
        for path in "${ADBD_PATHS[@]}"; do
            if [ -f "$path" ]; then
                mounted=$(mount | grep -c "$path")
                echo "$path: exists (mounted over: $mounted)"
            else
                echo "$path: not found"
            fi
        done
        
        echo ""
        echo "=== Socket Status ==="
        for socket_path in "${ADB_SOCKET_PATHS[@]}"; do
            if [ -e "$socket_path" ]; then
                echo "$socket_path: exists ($(stat -c %a "$socket_path" 2>/dev/null || echo 'unknown perms'))"
            else
                echo "$socket_path: not found"
            fi
        done
        ;;
    *)
        echo "Usage: $0 {neutralize|monitor|restore|kill|status}"
        exit 1
        ;;
esac

