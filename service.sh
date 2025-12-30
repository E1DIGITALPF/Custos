#!/system/bin/sh
##########################################################################################
#
# Custos Anti-Forensic Defense Module
# Main Service Script (late_start service)
#
# This script is executed after boot is completed
#
##########################################################################################

MODDIR="${0%/*}"
. "${MODDIR}/common/functions.sh"

# Wait for system to fully boot
wait_for_boot_complete 180

log_info "Custos service starting..."

# Verify module integrity
if ! verify_module_integrity; then
    log_error "Module integrity check failed - possible tampering detected"
    set_state "HOSTILE"
fi

# Load current state
CURRENT_STATE=$(get_current_state)
log_info "Current state: $CURRENT_STATE"

# If we were in hostile mode before reboot, re-enforce it
if [ "$CURRENT_STATE" = "HOSTILE" ]; then
    log_warn "Hostile mode persisted from previous session - enforcing defenses"
    sh "${MODDIR}/common/hostile_mode.sh" enforce &
fi

# Always start USB defense monitor (even in normal mode, we monitor for attempts)
log_info "Starting USB defense monitor..."
sh "${MODDIR}/common/usb_defense.sh" monitor &

# Start ADB neutralizer (persistent background process)
log_info "Starting ADB neutralizer..."
sh "${MODDIR}/common/adb_neutralizer.sh" monitor &

# Start hostile mode trigger monitors
log_info "Starting hostile mode trigger monitors..."
sh "${MODDIR}/common/hostile_mode.sh" monitor &

# Start failsafe timer checker
log_info "Starting failsafe timer..."
sh "${MODDIR}/common/failsafe_timer.sh" monitor &

# Start recovery validator service
log_info "Starting recovery validator..."
sh "${MODDIR}/common/recovery_validator.sh" service &

# Initial USB lockdown enforcement
if is_hostile_mode; then
    log_info "Enforcing USB lockdown due to hostile state"
    sh "${MODDIR}/common/usb_defense.sh" enforce
fi

# Monitor for SIM state changes (with compound trigger support)
log_info "Starting SIM state monitor..."
(
    while true; do
        # Check for SIM removal via property
        SIM_STATE=$(getprop gsm.sim.state)
        if [ "$SIM_STATE" = "ABSENT" ] || [ "$SIM_STATE" = "NOT_READY" ]; then
            if [ -f "${DATA_DIR}/.sim_was_present" ]; then
                log_warn "SIM removal detected"
                rm -f "${DATA_DIR}/.sim_was_present"
                
                # Use improved handler with compound trigger support
                # This now enters ALERT first, escalates to HOSTILE if USB connected
                sh "${MODDIR}/common/hostile_mode.sh" handle_sim_trigger
            fi
        else
            # Mark SIM as present
            touch "${DATA_DIR}/.sim_was_present" 2>/dev/null
        fi
        sleep 2
    done
) &

# Monitor for USB connection during ALERT (compound trigger escalation)
log_info "Starting compound trigger monitor..."
(
    while true; do
        if is_alert_mode; then
            # Check if USB was just connected during alert
            USB_ONLINE=$(cat /sys/class/power_supply/usb/online 2>/dev/null)
            if [ "$USB_ONLINE" = "1" ]; then
                log_warn "USB connected during ALERT mode - checking compound triggers"
                sh "${MODDIR}/common/hostile_mode.sh" handle_compound_check
            fi
        fi
        sleep 1
    done
) &

# Monitor for screen lock failures (lockscreen fail counter)
log_info "Starting lockscreen monitor..."
(
    FAIL_COUNT=0
    LAST_CHECK=$(date +%s)
    
    while true; do
        # Check logcat for failed unlock attempts
        CURRENT_FAILS=$(logcat -d -s "LockPatternUtils" 2>/dev/null | grep -c "pattern/password incorrect")
        
        if [ "$CURRENT_FAILS" -gt "$FAIL_COUNT" ]; then
            FAIL_DIFF=$((CURRENT_FAILS - FAIL_COUNT))
            FAIL_COUNT=$CURRENT_FAILS
            
            # Check if we've exceeded threshold (5 failures)
            if [ "$FAIL_DIFF" -ge 5 ]; then
                log_warn "Multiple unlock failures detected - activating hostile mode"
                sh "${MODDIR}/common/hostile_mode.sh" activate
            fi
        fi
        
        # Reset counter every hour
        NOW=$(date +%s)
        if [ $((NOW - LAST_CHECK)) -ge 3600 ]; then
            FAIL_COUNT=0
            LAST_CHECK=$NOW
            logcat -c 2>/dev/null  # Clear logcat buffer
        fi
        
        sleep 5
    done
) &

# Watchdog process - ensures critical processes stay running
log_info "Starting watchdog..."
(
    while true; do
        sleep 30
        
        # Check if USB defense is running
        if ! pgrep -f "usb_defense.sh" >/dev/null 2>&1; then
            log_warn "USB defense process died - restarting"
            sh "${MODDIR}/common/usb_defense.sh" monitor &
        fi
        
        # Check if ADB neutralizer is running
        if ! pgrep -f "adb_neutralizer.sh" >/dev/null 2>&1; then
            log_warn "ADB neutralizer process died - restarting"
            sh "${MODDIR}/common/adb_neutralizer.sh" monitor &
        fi
        
        # Check if hostile mode monitor is running
        if ! pgrep -f "hostile_mode.sh" >/dev/null 2>&1; then
            log_warn "Hostile mode monitor died - restarting"
            sh "${MODDIR}/common/hostile_mode.sh" monitor &
        fi
        
        # Re-enforce hostile mode if active
        if is_hostile_mode; then
            sh "${MODDIR}/common/usb_defense.sh" enforce
        fi
    done
) &

log_info "Custos service initialized successfully"
log_info "All defensive monitors active"

