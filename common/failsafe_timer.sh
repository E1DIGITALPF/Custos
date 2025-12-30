#!/system/bin/sh
##########################################################################################
#
# Custos Anti-Forensic Defense Module
# Failsafe Timer Component
#
# Prevents permanent lockout by auto-restoring after configurable duration
# This is a safety mechanism to prevent self-denial-of-service
#
##########################################################################################

MODDIR="${0%/*}/.."
. "${MODDIR}/common/functions.sh"

# Failsafe configuration
CONFIG_FILE="${DATA_DIR}/triggers.conf"
DEFAULT_FAILSAFE_HOURS=72

##########################################################################################
# CONFIGURATION
##########################################################################################

get_failsafe_hours() {
    local hours=$(grep "^failsafe_hours:" "$CONFIG_FILE" 2>/dev/null | cut -d':' -f2)
    
    if [ -z "$hours" ] || [ "$hours" = "0" ]; then
        # Failsafe disabled - return very large number
        echo "999999"
    else
        echo "$hours"
    fi
}

get_hostile_min_duration() {
    local seconds=$(grep "^hostile_min_duration:" "$CONFIG_FILE" 2>/dev/null | cut -d':' -f2)
    echo "${seconds:-60}"
}

##########################################################################################
# FAILSAFE CHECK
##########################################################################################

check_failsafe() {
    # Only applies to hostile mode
    if ! is_hostile_mode; then
        return 0
    fi
    
    local state_timestamp=$(get_state_timestamp)
    local now=$(date +%s)
    local elapsed_seconds=$((now - state_timestamp))
    local elapsed_hours=$((elapsed_seconds / 3600))
    
    local failsafe_hours=$(get_failsafe_hours)
    
    log_debug "Failsafe check: ${elapsed_hours}h elapsed, limit ${failsafe_hours}h"
    
    if [ "$elapsed_hours" -ge "$failsafe_hours" ]; then
        log_warn "Failsafe timer expired after ${elapsed_hours} hours"
        trigger_failsafe_recovery
        return 1
    fi
    
    return 0
}

##########################################################################################
# FAILSAFE RECOVERY
##########################################################################################

trigger_failsafe_recovery() {
    log_warn "=== FAILSAFE RECOVERY TRIGGERED ==="
    
    # Record failsafe event
    echo "$(date +%s):FAILSAFE_TRIGGERED" >> "${DATA_DIR}/failsafe.log"
    
    # Create validation flag to allow recovery
    touch "${DATA_DIR}/.recovery_validated"
    touch "${DATA_DIR}/.failsafe_recovery"
    
    # Notify user via vibration (SOS pattern)
    # S: ...
    for i in 1 2 3; do
        cmd vibrator vibrate 100 2>/dev/null
        sleep 0.2
    done
    sleep 0.3
    # O: ---
    for i in 1 2 3; do
        cmd vibrator vibrate 300 2>/dev/null
        sleep 0.2
    done
    sleep 0.3
    # S: ...
    for i in 1 2 3; do
        cmd vibrator vibrate 100 2>/dev/null
        sleep 0.2
    done
    
    # Restore normal mode
    sh "${MODDIR}/common/hostile_mode.sh" deactivate
    
    # Clear the failsafe flag
    rm -f "${DATA_DIR}/.failsafe_recovery"
    
    log_info "Failsafe recovery completed - normal mode restored"
}

##########################################################################################
# REMAINING TIME CALCULATION
##########################################################################################

get_remaining_time() {
    if ! is_hostile_mode; then
        echo "Not in hostile mode"
        return
    fi
    
    local state_timestamp=$(get_state_timestamp)
    local now=$(date +%s)
    local elapsed_seconds=$((now - state_timestamp))
    
    local failsafe_hours=$(get_failsafe_hours)
    local failsafe_seconds=$((failsafe_hours * 3600))
    
    local remaining_seconds=$((failsafe_seconds - elapsed_seconds))
    
    if [ "$remaining_seconds" -lt 0 ]; then
        remaining_seconds=0
    fi
    
    local remaining_hours=$((remaining_seconds / 3600))
    local remaining_minutes=$(((remaining_seconds % 3600) / 60))
    
    echo "${remaining_hours}h ${remaining_minutes}m"
}

##########################################################################################
# MONITORING LOOP
##########################################################################################

monitor_failsafe() {
    log_info "Failsafe timer monitor starting"
    
    local check_interval=300  # Check every 5 minutes
    
    while true; do
        if is_hostile_mode; then
            check_failsafe
            
            # Log remaining time periodically
            local remaining=$(get_remaining_time)
            log_debug "Failsafe remaining: $remaining"
        fi
        
        sleep $check_interval
    done
}

##########################################################################################
# COUNTDOWN DISPLAY
##########################################################################################

display_countdown() {
    if ! is_hostile_mode; then
        echo "Device is not in hostile mode"
        return
    fi
    
    echo "=== Failsafe Timer Countdown ==="
    echo ""
    
    local failsafe_hours=$(get_failsafe_hours)
    
    if [ "$failsafe_hours" = "999999" ]; then
        echo "Failsafe timer is DISABLED"
        echo "WARNING: Device will remain in hostile mode indefinitely"
        echo "Only recovery phrase can restore normal mode"
        return
    fi
    
    local state_timestamp=$(get_state_timestamp)
    local now=$(date +%s)
    local elapsed_seconds=$((now - state_timestamp))
    local elapsed_hours=$((elapsed_seconds / 3600))
    local elapsed_minutes=$(((elapsed_seconds % 3600) / 60))
    
    local failsafe_seconds=$((failsafe_hours * 3600))
    local remaining_seconds=$((failsafe_seconds - elapsed_seconds))
    local remaining_hours=$((remaining_seconds / 3600))
    local remaining_minutes=$(((remaining_seconds % 3600) / 60))
    
    echo "Hostile mode activated: $(date -d @$state_timestamp 2>/dev/null || echo $state_timestamp)"
    echo "Elapsed time: ${elapsed_hours}h ${elapsed_minutes}m"
    echo "Failsafe limit: ${failsafe_hours}h"
    echo ""
    echo "Time until automatic recovery: ${remaining_hours}h ${remaining_minutes}m"
    echo ""
    
    # Progress bar
    local progress=$((elapsed_seconds * 50 / failsafe_seconds))
    if [ $progress -gt 50 ]; then
        progress=50
    fi
    
    printf "["
    for i in $(seq 1 50); do
        if [ $i -le $progress ]; then
            printf "#"
        else
            printf "-"
        fi
    done
    printf "] %d%%\n" $((elapsed_seconds * 100 / failsafe_seconds))
}

##########################################################################################
# EXTEND FAILSAFE (for authorized extensions)
##########################################################################################

extend_failsafe() {
    local additional_hours="$1"
    
    if [ -z "$additional_hours" ]; then
        echo "Usage: $0 extend <hours>"
        return 1
    fi
    
    # This would require authentication in a real implementation
    # For now, just log the request
    log_warn "Failsafe extension requested: +${additional_hours}h"
    
    # Update timestamp to effectively extend
    local current_timestamp=$(get_state_timestamp)
    local extension_seconds=$((additional_hours * 3600))
    local new_timestamp=$((current_timestamp + extension_seconds))
    
    # This doesn't actually work with our state format, but shows the concept
    # In practice, you'd need a separate extension tracker
    
    echo "Extension not implemented in this version"
    echo "Use recovery phrase or wait for failsafe expiry"
    
    return 1
}

##########################################################################################
# EMERGENCY DISABLE
##########################################################################################

emergency_disable_failsafe() {
    # This should only be accessible via root shell or Magisk manager
    
    if [ "$1" != "--confirm-disable" ]; then
        echo "WARNING: Disabling failsafe can lead to permanent lockout!"
        echo "Usage: $0 disable --confirm-disable"
        return 1
    fi
    
    log_warn "FAILSAFE TIMER DISABLED BY USER"
    
    # Set failsafe to 0 in config
    if [ -f "$CONFIG_FILE" ]; then
        sed -i 's/^failsafe_hours:.*/failsafe_hours:0/' "$CONFIG_FILE"
    else
        echo "failsafe_hours:0" >> "$CONFIG_FILE"
    fi
    
    echo "Failsafe timer disabled"
    echo "WARNING: Device can now remain in hostile mode indefinitely"
    
    return 0
}

##########################################################################################
# MAIN EXECUTION
##########################################################################################

case "$1" in
    "check")
        check_failsafe
        ;;
    "monitor")
        monitor_failsafe
        ;;
    "remaining"|"countdown")
        display_countdown
        ;;
    "trigger")
        if [ "$2" = "--force" ]; then
            trigger_failsafe_recovery
        else
            echo "Usage: $0 trigger --force"
            echo "This will immediately restore normal mode"
        fi
        ;;
    "extend")
        extend_failsafe "$2"
        ;;
    "disable")
        emergency_disable_failsafe "$2"
        ;;
    "status")
        echo "=== Failsafe Timer Status ==="
        echo "Failsafe enabled: $([ "$(get_failsafe_hours)" != "999999" ] && echo 'YES' || echo 'NO')"
        echo "Failsafe duration: $(get_failsafe_hours)h"
        echo "Min hostile duration: $(get_hostile_min_duration)s"
        echo ""
        
        if is_hostile_mode; then
            echo "Current mode: HOSTILE"
            echo "Remaining time: $(get_remaining_time)"
        else
            echo "Current mode: $(get_current_state)"
        fi
        
        echo ""
        echo "=== Failsafe History ==="
        tail -5 "${DATA_DIR}/failsafe.log" 2>/dev/null || echo "No failsafe events"
        ;;
    *)
        echo "Usage: $0 {check|monitor|remaining|trigger|extend|disable|status}"
        exit 1
        ;;
esac

