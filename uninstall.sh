#!/system/bin/sh
##########################################################################################
#
# Custos Anti-Forensic Defense Module
# Uninstallation Script
#
# Safely removes the module and restores normal functionality
#
##########################################################################################

LOG_TAG="CUSTOS"
DATA_DIR="/data/adb/custos"

log_info() {
    log -t "$LOG_TAG" -p i "$1" 2>/dev/null
}

log_info "Custos module uninstallation starting..."

##########################################################################################
# STOP ALL RUNNING PROCESSES
##########################################################################################

log_info "Stopping defensive processes..."

# Kill all module-related processes
pkill -9 -f "usb_defense.sh" 2>/dev/null
pkill -9 -f "adb_neutralizer.sh" 2>/dev/null
pkill -9 -f "hostile_mode.sh" 2>/dev/null
pkill -9 -f "failsafe_timer.sh" 2>/dev/null
pkill -9 -f "recovery_validator.sh" 2>/dev/null
pkill -9 -f "custos" 2>/dev/null

# Give processes time to terminate
sleep 2

##########################################################################################
# RESTORE USB FUNCTIONALITY
##########################################################################################

log_info "Restoring USB functionality..."

# Unmount any bind mounts over adbd
for adbd_path in "/system/bin/adbd" "/apex/com.android.adbd/bin/adbd" "/sbin/adbd"; do
    if [ -f "$adbd_path" ]; then
        umount "$adbd_path" 2>/dev/null
    fi
done

# Unmount USB socket if mounted
umount /dev/socket/adbd 2>/dev/null

# Restore USB properties
if command -v resetprop >/dev/null 2>&1; then
    resetprop --delete persist.sys.usb.config 2>/dev/null
    resetprop --delete sys.usb.config 2>/dev/null
    resetprop --delete sys.usb.state 2>/dev/null
fi

# Re-enable USB gadget
if [ -d "/sys/class/android_usb/android0" ]; then
    echo "mtp,adb" > /sys/class/android_usb/android0/functions 2>/dev/null
    echo "1" > /sys/class/android_usb/android0/enable 2>/dev/null
fi

if [ -d "/config/usb_gadget/g1" ]; then
    # Re-link functions
    UDC=$(ls /sys/class/udc/ 2>/dev/null | head -1)
    if [ -n "$UDC" ]; then
        echo "$UDC" > /config/usb_gadget/g1/UDC 2>/dev/null
    fi
fi

##########################################################################################
# RESTORE ADB FUNCTIONALITY
##########################################################################################

log_info "Restoring ADB functionality..."

# Re-enable development settings
settings put global development_settings_enabled 1 2>/dev/null
settings put global adb_enabled 1 2>/dev/null

# Start adbd service
start adbd 2>/dev/null

##########################################################################################
# RESTORE CONNECTIVITY
##########################################################################################

log_info "Restoring connectivity..."

# Disable airplane mode if it was enabled by hostile mode
settings put global airplane_mode_on 0 2>/dev/null
am broadcast -a android.intent.action.AIRPLANE_MODE --ez state false 2>/dev/null

# Re-enable biometrics
settings put secure fingerprint_enabled 1 2>/dev/null

##########################################################################################
# CLEANUP DATA (OPTIONAL - PRESERVE BY DEFAULT)
##########################################################################################

# We preserve the data directory by default to maintain the recovery phrase
# and state history. Uncomment below to fully clean up.

# rm -rf "$DATA_DIR"

# Instead, just clear the state
log_info "Clearing module state..."
rm -f "${DATA_DIR}/state.db" 2>/dev/null
rm -f "${DATA_DIR}/boot_anomaly.log" 2>/dev/null
rm -f "${DATA_DIR}/.sim_was_present" 2>/dev/null

##########################################################################################
# FINAL NOTIFICATION
##########################################################################################

log_info "Custos module uninstallation completed"
log_info "USB and ADB functionality restored"
log_info "Recovery phrase preserved in ${DATA_DIR}/"

# Show notification to user
am start -a android.intent.action.VIEW \
    -d "content://settings/system" \
    --es android.intent.extra.TEXT "Custos module removed. USB/ADB restored." \
    2>/dev/null

exit 0

