#!/system/bin/sh
##########################################################################################
#
# Custos Anti-Forensic Defense Module
# USB Defense Component
#
# Sabotages USB data negotiation and enforces charge-only mode
# Defeats: Cellebrite UFED, Oxygen Forensic, MOBILedit USB-based extractions
#
##########################################################################################

MODDIR="${0%/*}/.."
. "${MODDIR}/common/functions.sh"

# USB paths for different Android versions/devices
USB_ANDROID="/sys/class/android_usb/android0"
USB_CONFIGFS="/config/usb_gadget/g1"
USB_ROLE_PATH="/sys/class/usb_role"
USB_TYPEC_PATH="/sys/class/typec"

# Lock file to prevent race conditions
LOCK_FILE="/data/adb/custos/.usb_lock"

##########################################################################################
# CHARGE-ONLY ENFORCEMENT
##########################################################################################

enforce_charge_only() {
    log_info "Enforcing charge-only USB mode"
    
    # Acquire lock
    exec 200>"$LOCK_FILE"
    flock -n 200 || return 1
    
    # ==========================================
    # METHOD 1: Android USB Gadget (Legacy)
    # ==========================================
    if [ -d "$USB_ANDROID" ]; then
        # Disable USB gadget
        echo "0" > "${USB_ANDROID}/enable" 2>/dev/null
        
        # Clear all functions
        echo "" > "${USB_ANDROID}/functions" 2>/dev/null
        
        # Set charging mode
        echo "charging" > "${USB_ANDROID}/f_accessory/mode" 2>/dev/null
        
        # Clear product/vendor info to prevent enumeration
        echo "" > "${USB_ANDROID}/iProduct" 2>/dev/null
        echo "" > "${USB_ANDROID}/iManufacturer" 2>/dev/null
        echo "" > "${USB_ANDROID}/iSerial" 2>/dev/null
        
        log_debug "Android USB gadget disabled"
    fi
    
    # ==========================================
    # METHOD 2: ConfigFS USB Gadget (Modern)
    # ==========================================
    if [ -d "$USB_CONFIGFS" ]; then
        # Detach from UDC (USB Device Controller)
        echo "" > "${USB_CONFIGFS}/UDC" 2>/dev/null
        
        # Remove all function symlinks
        rm -f "${USB_CONFIGFS}/configs/b.1/ffs.adb" 2>/dev/null
        rm -f "${USB_CONFIGFS}/configs/b.1/ffs.mtp" 2>/dev/null
        rm -f "${USB_CONFIGFS}/configs/b.1/ffs.ptp" 2>/dev/null
        rm -f "${USB_CONFIGFS}/configs/b.1/ffs.accessory" 2>/dev/null
        rm -f "${USB_CONFIGFS}/configs/b.1/ffs.audio_source" 2>/dev/null
        rm -f "${USB_CONFIGFS}/configs/b.1/ffs.midi" 2>/dev/null
        rm -f "${USB_CONFIGFS}/configs/b.1/rndis.gs4" 2>/dev/null
        rm -f "${USB_CONFIGFS}/configs/b.1/ncm.gs6" 2>/dev/null
        rm -f "${USB_CONFIGFS}/configs/b.1/function"* 2>/dev/null
        rm -f "${USB_CONFIGFS}/configs/b.1/f"* 2>/dev/null
        
        # Clear configuration string
        echo "" > "${USB_CONFIGFS}/configs/b.1/strings/0x409/configuration" 2>/dev/null
        
        # Optionally clear device strings to further obscure device
        echo "" > "${USB_CONFIGFS}/strings/0x409/serialnumber" 2>/dev/null
        echo "Unknown" > "${USB_CONFIGFS}/strings/0x409/manufacturer" 2>/dev/null
        echo "Charging Device" > "${USB_CONFIGFS}/strings/0x409/product" 2>/dev/null
        
        log_debug "ConfigFS USB gadget disabled"
    fi
    
    # ==========================================
    # METHOD 3: USB Role Switch Control
    # ==========================================
    if [ -d "$USB_ROLE_PATH" ]; then
        for role_dev in "${USB_ROLE_PATH}"/*; do
            if [ -f "${role_dev}/role" ]; then
                echo "none" > "${role_dev}/role" 2>/dev/null
            fi
        done
        log_debug "USB role switch disabled"
    fi
    
    # ==========================================
    # METHOD 4: USB Type-C Controller
    # ==========================================
    if [ -d "$USB_TYPEC_PATH" ]; then
        for typec_port in "${USB_TYPEC_PATH}"/port*; do
            if [ -f "${typec_port}/data_role" ]; then
                # Force sink (device) role with no data
                echo "sink" > "${typec_port}/power_role" 2>/dev/null
                echo "device" > "${typec_port}/data_role" 2>/dev/null
            fi
        done
        log_debug "Type-C data role restricted"
    fi
    
    # ==========================================
    # METHOD 5: System Properties
    # ==========================================
    safe_resetprop persist.sys.usb.config "charging"
    safe_resetprop sys.usb.config "charging"
    safe_resetprop sys.usb.state "charging"
    safe_resetprop sys.usb.controller ""
    safe_resetprop sys.usb.configfs "0"
    safe_resetprop sys.usb.ffs.ready "0"
    
    # Disable MTP specifically
    safe_resetprop sys.usb.mtp.device_type "0"
    
    # Disable ADB-related properties
    safe_resetprop ro.adb.secure "1"
    safe_resetprop ro.debuggable "0"
    safe_resetprop persist.adb.tcp.port ""
    safe_resetprop service.adb.tcp.port ""
    
    # ==========================================
    # METHOD 6: Settings Database
    # ==========================================
    settings put global adb_enabled 0 2>/dev/null
    settings put global development_settings_enabled 0 2>/dev/null
    settings put secure usb_mass_storage_enabled 0 2>/dev/null
    
    # Release lock
    flock -u 200
    
    log_info "Charge-only mode enforced successfully"
    return 0
}

##########################################################################################
# USB STATE MONITORING
##########################################################################################

monitor_usb_state() {
    log_info "Starting USB state monitor"
    
    local check_interval=1
    local last_functions=""
    local data_attempt_count=0
    
    while true; do
        # Check if hostile mode is active
        if is_hostile_mode; then
            # Aggressive enforcement in hostile mode
            enforce_charge_only
            check_interval=0.5
        else
            check_interval=2
        fi
        
        # Monitor for USB function changes
        current_functions=""
        
        # Check legacy path
        if [ -f "${USB_ANDROID}/functions" ]; then
            current_functions=$(cat "${USB_ANDROID}/functions" 2>/dev/null)
        fi
        
        # Check configfs path
        if [ -d "${USB_CONFIGFS}/configs/b.1" ]; then
            configfs_funcs=$(ls -1 "${USB_CONFIGFS}/configs/b.1/" 2>/dev/null | grep -E "^(ffs|f[0-9])" | tr '\n' ',')
            current_functions="${current_functions}${configfs_funcs}"
        fi
        
        # Detect data mode attempts
        if echo "$current_functions" | grep -qiE "(adb|mtp|ptp|rndis|ncm|mass_storage|accessory)"; then
            log_warn "USB data mode attempt detected: $current_functions"
            data_attempt_count=$((data_attempt_count + 1))
            
            # Immediately block
            enforce_charge_only
            
            # If multiple attempts, escalate to hostile mode
            if [ $data_attempt_count -ge 3 ] && ! is_hostile_mode; then
                log_warn "Multiple USB data attempts - activating hostile mode"
                sh "${MODDIR}/common/hostile_mode.sh" activate
            fi
        fi
        
        # Monitor USB properties for changes
        current_config=$(getprop sys.usb.config)
        if [ "$current_config" != "charging" ] && [ -n "$current_config" ]; then
            log_warn "USB config property changed to: $current_config"
            enforce_charge_only
        fi
        
        # Check if adbd is trying to run
        if pgrep -x "adbd" >/dev/null 2>&1; then
            log_warn "adbd process detected - killing"
            pkill -9 -x "adbd" 2>/dev/null
        fi
        
        sleep $check_interval
    done
}

##########################################################################################
# INOTIFY-BASED MONITORING (MORE RESPONSIVE)
##########################################################################################

monitor_usb_inotify() {
    log_info "Starting inotify-based USB monitor"
    
    # Monitor USB state files for changes
    WATCH_PATHS=""
    
    [ -d "$USB_ANDROID" ] && WATCH_PATHS="${WATCH_PATHS} ${USB_ANDROID}/functions ${USB_ANDROID}/enable"
    [ -d "$USB_CONFIGFS" ] && WATCH_PATHS="${WATCH_PATHS} ${USB_CONFIGFS}/UDC"
    
    if [ -n "$WATCH_PATHS" ] && command -v inotifywait >/dev/null 2>&1; then
        inotifywait -m -e modify -e create $WATCH_PATHS 2>/dev/null | while read -r directory event filename; do
            log_warn "USB change detected: $directory $event $filename"
            enforce_charge_only
            
            # Check for escalation to hostile mode
            if ! is_hostile_mode && is_alert_mode; then
                sh "${MODDIR}/common/hostile_mode.sh" activate
            fi
        done
    else
        # Fallback to polling if inotifywait not available
        log_info "inotifywait not available, using polling mode"
        monitor_usb_state
    fi
}

##########################################################################################
# CABLE DETECTION
##########################################################################################

detect_usb_cable() {
    # Check if USB cable is connected
    local usb_online=$(cat /sys/class/power_supply/usb/online 2>/dev/null)
    
    if [ "$usb_online" = "1" ]; then
        log_info "USB cable connected"
        
        # Check screen state - suspicious if USB connected with screen off
        if ! is_screen_on; then
            log_warn "USB connected while screen off - suspicious"
            
            # Enter alert mode if not already hostile
            if is_normal_mode; then
                set_state "ALERT"
            fi
        fi
        
        # Enforce charge-only whenever cable is connected
        enforce_charge_only
        
        return 0
    fi
    
    return 1
}

##########################################################################################
# USB EVENT HANDLER
##########################################################################################

handle_usb_event() {
    local event_type="$1"
    
    case "$event_type" in
        "connected")
            log_info "USB cable connected event"
            detect_usb_cable
            ;;
        "disconnected")
            log_info "USB cable disconnected event"
            ;;
        "data_attempt")
            log_warn "USB data negotiation attempt blocked"
            enforce_charge_only
            ;;
        *)
            log_debug "Unknown USB event: $event_type"
            ;;
    esac
}

##########################################################################################
# RESTORE USB FUNCTION (FOR RECOVERY)
##########################################################################################

restore_usb_function() {
    log_info "Restoring USB functionality"
    
    # Only allow if recovery phrase validated
    if [ "$1" != "--force" ] && [ ! -f "/data/adb/custos/.recovery_validated" ]; then
        log_error "Recovery not validated - USB restore denied"
        return 1
    fi
    
    # Re-enable USB gadget
    if [ -d "$USB_ANDROID" ]; then
        echo "mtp,adb" > "${USB_ANDROID}/functions" 2>/dev/null
        echo "1" > "${USB_ANDROID}/enable" 2>/dev/null
    fi
    
    if [ -d "$USB_CONFIGFS" ]; then
        # Find UDC
        UDC=$(ls /sys/class/udc/ 2>/dev/null | head -1)
        if [ -n "$UDC" ]; then
            echo "$UDC" > "${USB_CONFIGFS}/UDC" 2>/dev/null
        fi
    fi
    
    # Restore properties
    safe_resetprop persist.sys.usb.config "mtp,adb"
    safe_resetprop sys.usb.config "mtp,adb"
    
    # Re-enable ADB
    settings put global adb_enabled 1 2>/dev/null
    settings put global development_settings_enabled 1 2>/dev/null
    
    log_info "USB functionality restored"
    return 0
}

##########################################################################################
# MAIN EXECUTION
##########################################################################################

case "$1" in
    "enforce")
        enforce_charge_only
        ;;
    "monitor")
        # Start monitoring (prefer inotify if available)
        if command -v inotifywait >/dev/null 2>&1; then
            monitor_usb_inotify &
        fi
        # Also run polling monitor for redundancy
        monitor_usb_state
        ;;
    "restore")
        restore_usb_function "$2"
        ;;
    "status")
        echo "USB Functions: $(cat ${USB_ANDROID}/functions 2>/dev/null || echo 'N/A')"
        echo "USB Enable: $(cat ${USB_ANDROID}/enable 2>/dev/null || echo 'N/A')"
        echo "USB Config: $(getprop sys.usb.config)"
        echo "USB State: $(getprop sys.usb.state)"
        ;;
    *)
        echo "Usage: $0 {enforce|monitor|restore|status}"
        exit 1
        ;;
esac

