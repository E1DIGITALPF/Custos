#!/system/bin/sh
##########################################################################################
#
# Custos Anti-Forensic Defense Module
# Hostile Custody Mode Component
#
# Implements "panic mode" for border crossing / arrest scenarios
# Activates comprehensive defensive measures instantly
#
##########################################################################################

MODDIR="${0%/*}/.."
. "${MODDIR}/common/functions.sh"

# Trigger configuration
TRIGGER_CONF="${DATA_DIR}/triggers.conf"

# Trigger state tracking
VOLUME_DOWN_COUNT=0
VOLUME_DOWN_FIRST=0
AIRPLANE_TOGGLE_COUNT=0
AIRPLANE_TOGGLE_FIRST=0
POWER_BUTTON_COUNT=0
POWER_BUTTON_FIRST=0

##########################################################################################
# CONFIGURATION PARSER
##########################################################################################

parse_trigger_config() {
    local trigger_name="$1"
    local field="$2"
    
    if [ -f "$TRIGGER_CONF" ]; then
        grep "^${trigger_name}:" "$TRIGGER_CONF" 2>/dev/null | cut -d':' -f"$field"
    else
        echo ""
    fi
}

is_trigger_enabled() {
    local trigger_name="$1"
    local config_line=$(grep "^${trigger_name}:" "$TRIGGER_CONF" 2>/dev/null)
    
    echo "$config_line" | grep -qi "enabled"
}

get_trigger_threshold() {
    local trigger_name="$1"
    parse_trigger_config "$trigger_name" 2
}

get_trigger_window() {
    local trigger_name="$1"
    parse_trigger_config "$trigger_name" 3
}

##########################################################################################
# HOSTILE MODE ACTIVATION
##########################################################################################

activate_hostile_mode() {
    local trigger_source="${1:-manual}"
    
    log_warn "=== HOSTILE MODE ACTIVATION ==="
    log_warn "Trigger source: $trigger_source"
    
    # Already in hostile mode?
    if is_hostile_mode; then
        log_info "Already in hostile mode - reinforcing defenses"
        enforce_hostile_mode
        return 0
    fi
    
    local timestamp=$(date +%s)
    
    # Record activation
    set_state "HOSTILE"
    echo "${trigger_source}:${timestamp}" >> "${DATA_DIR}/hostile_activations.log"
    
    # PHASE 1: IMMEDIATE ACTIONS (Critical Path)
    log_info "Phase 1: Immediate defensive actions"
    
    # Lock screen instantly
    input keyevent 26
    
    # Kill any exposed processes
    pkill -9 -f "adbd" 2>/dev/null
    
    # PHASE 2: KEY EVICTION
    log_info "Phase 2: Key eviction"
    sh "${MODDIR}/common/key_eviction.sh" quick &
    
    # PHASE 3: USB LOCKDOWN
    log_info "Phase 3: USB lockdown"
    sh "${MODDIR}/common/usb_defense.sh" enforce &
    
    # PHASE 4: ADB NEUTRALIZATION
    log_info "Phase 4: ADB neutralization"
    sh "${MODDIR}/common/adb_neutralizer.sh" neutralize &
    
    # PHASE 5: NETWORK ISOLATION
    log_info "Phase 5: Network isolation"
    enable_airplane_mode
    
    # PHASE 6: BIOMETRIC DISABLE
    log_info "Phase 6: Disabling biometrics"
    disable_biometrics
    
    # Wait for critical tasks
    wait
    
    # PHASE 7: FULL KEY EVICTION (BACKGROUND)
    log_info "Phase 7: Full key eviction (background)"
    sh "${MODDIR}/common/key_eviction.sh" evict-all &
    
    # Vibrate to confirm activation (3 short pulses)
    for i in 1 2 3; do
        cmd vibrator vibrate 100 2>/dev/null
        sleep 0.2
    done
    
    log_warn "=== HOSTILE MODE ACTIVE ==="
    log_warn "Device secured - recovery phrase required to restore"
    
    # Start enforcement loop
    enforce_hostile_mode &
}

##########################################################################################
# HOSTILE MODE ENFORCEMENT
##########################################################################################

enforce_hostile_mode() {
    log_info "Enforcing hostile mode"
    
    while is_hostile_mode; do
        # Continuously enforce all defensive measures
        
        # USB lockdown
        sh "${MODDIR}/common/usb_defense.sh" enforce >/dev/null 2>&1
        
        # Kill ADB
        pkill -9 -x "adbd" 2>/dev/null
        
        # Ensure screen lock
        if is_screen_on && ! is_device_locked; then
            input keyevent 26
        fi
        
        # Ensure airplane mode
        airplane=$(settings get global airplane_mode_on 2>/dev/null)
        if [ "$airplane" != "1" ]; then
            enable_airplane_mode
        fi
        
        # Ensure biometrics disabled
        fingerprint_enabled=$(settings get secure fingerprint_enabled 2>/dev/null)
        if [ "$fingerprint_enabled" = "1" ]; then
            disable_biometrics
        fi
        
        sleep 1
    done
    
    log_info "Hostile mode enforcement stopped"
}

##########################################################################################
# ALERT MODE
##########################################################################################

activate_alert_mode() {
    local trigger_source="${1:-unknown}"
    
    if is_hostile_mode; then
        log_debug "Already in hostile mode - ignoring alert"
        return 0
    fi
    
    log_warn "Alert mode activated by: $trigger_source"
    set_state "ALERT"
    
    # Record alert reason for compound trigger detection
    echo "$trigger_source" > "${DATA_DIR}/.alert_reason"
    
    # Single vibration for alert
    cmd vibrator vibrate 200 2>/dev/null
    
    # Get alert timeout from config
    local timeout=$(grep "^alert_timeout:" "$TRIGGER_CONF" 2>/dev/null | cut -d':' -f2)
    timeout=${timeout:-30}
    
    # Schedule return to normal if no escalation
    (
        sleep "$timeout"
        if is_alert_mode; then
            log_info "Alert timeout - returning to normal"
            set_state "NORMAL"
            rm -f "${DATA_DIR}/.alert_reason"
        fi
    ) &
}

##########################################################################################
# TRIGGER HANDLERS
##########################################################################################

handle_volume_trigger() {
    local now=$(date +%s)
    local threshold=$(get_trigger_threshold "volume_down")
    local window=$(get_trigger_window "volume_down")
    
    threshold=${threshold:-5}
    window=${window:-3}
    
    # Check if within time window
    if [ $((now - VOLUME_DOWN_FIRST)) -gt "$window" ]; then
        # Reset counter
        VOLUME_DOWN_COUNT=1
        VOLUME_DOWN_FIRST=$now
    else
        VOLUME_DOWN_COUNT=$((VOLUME_DOWN_COUNT + 1))
    fi
    
    log_debug "Volume down count: $VOLUME_DOWN_COUNT / $threshold"
    
    if [ "$VOLUME_DOWN_COUNT" -ge "$threshold" ]; then
        log_warn "Volume panic trigger activated"
        VOLUME_DOWN_COUNT=0
        activate_hostile_mode "volume_panic"
    fi
}

handle_sim_removal() {
    local sim_config=$(grep "^sim_removed:" "$TRIGGER_CONF" 2>/dev/null)
    
    if echo "$sim_config" | grep -qi "enabled"; then
        # Direct HOSTILE (legacy behavior, not recommended)
        log_warn "SIM removal trigger activated (direct hostile)"
        activate_hostile_mode "sim_removal"
    elif echo "$sim_config" | grep -qi "alert"; then
        # ALERT mode (recommended - reduces false positives)
        log_warn "SIM removal detected - entering alert mode"
        activate_alert_mode "sim_removal"
        
        # Check for compound trigger: SIM + USB
        if is_usb_connected; then
            log_warn "SIM removal + USB connected - escalating to hostile"
            activate_hostile_mode "sim_removal_plus_usb"
        fi
        
        # Check for compound trigger: SIM + USB + screen off
        if is_usb_connected && ! is_screen_on; then
            log_warn "SIM removal + USB + screen off - immediate hostile"
            activate_hostile_mode "sim_usb_screen_off"
        fi
    else
        log_debug "SIM removal trigger disabled"
    fi
}

handle_compound_sim_usb() {
    # Called when USB is connected while in ALERT from SIM removal
    if is_alert_mode; then
        local alert_reason=$(cat "${DATA_DIR}/.alert_reason" 2>/dev/null)
        if echo "$alert_reason" | grep -qi "sim"; then
            log_warn "USB connected during SIM alert - escalating to hostile"
            activate_hostile_mode "sim_removal_plus_usb"
        fi
    fi
}

handle_lockscreen_fail() {
    local fail_count="$1"
    local threshold=$(get_trigger_threshold "lockscreen_fail")
    threshold=${threshold:-5}
    
    if [ "$fail_count" -ge "$threshold" ]; then
        log_warn "Lockscreen fail trigger activated ($fail_count attempts)"
        activate_hostile_mode "lockscreen_fail"
    fi
}

handle_usb_data_attempt() {
    if is_trigger_enabled "usb_data_attempt"; then
        log_warn "USB data attempt trigger activated"
        
        # First attempt: alert mode
        if is_normal_mode; then
            activate_alert_mode "usb_data_attempt"
        # Second attempt in alert: hostile mode
        elif is_alert_mode; then
            activate_hostile_mode "usb_data_attempt"
        fi
    fi
}

handle_boot_anomaly() {
    local anomaly_type="${1:-unknown}"
    
    case "$anomaly_type" in
        "strong"|"STRONG")
            # Strong anomaly always goes HOSTILE
            if is_trigger_enabled "boot_anomaly_strong"; then
                log_warn "Strong boot anomaly trigger activated"
                activate_hostile_mode "boot_anomaly_strong"
            fi
            ;;
        "weak"|"WEAK")
            # Weak anomaly goes to ALERT (reduces false positives from OTAs)
            local weak_config=$(grep "^boot_anomaly_weak:" "$TRIGGER_CONF" 2>/dev/null)
            if echo "$weak_config" | grep -qi "alert"; then
                log_warn "Weak boot anomaly - entering alert mode"
                activate_alert_mode "boot_anomaly_weak"
            elif echo "$weak_config" | grep -qi "enabled"; then
                log_warn "Weak boot anomaly trigger activated (legacy mode)"
                activate_hostile_mode "boot_anomaly_weak"
            fi
            ;;
        *)
            # Legacy behavior for backward compatibility
            if is_trigger_enabled "boot_anomaly"; then
                log_warn "Boot anomaly trigger activated"
                activate_hostile_mode "boot_anomaly"
            fi
            ;;
    esac
}

handle_airplane_toggle() {
    local now=$(date +%s)
    local threshold=$(get_trigger_threshold "airplane_toggle")
    local action=$(parse_trigger_config "airplane_toggle" 3)
    
    threshold=${threshold:-3}
    
    if [ $((now - AIRPLANE_TOGGLE_FIRST)) -gt 5 ]; then
        AIRPLANE_TOGGLE_COUNT=1
        AIRPLANE_TOGGLE_FIRST=$now
    else
        AIRPLANE_TOGGLE_COUNT=$((AIRPLANE_TOGGLE_COUNT + 1))
    fi
    
    if [ "$AIRPLANE_TOGGLE_COUNT" -ge "$threshold" ]; then
        AIRPLANE_TOGGLE_COUNT=0
        if [ "$action" = "alert" ]; then
            activate_alert_mode "airplane_toggle"
        else
            activate_hostile_mode "airplane_toggle"
        fi
    fi
}

handle_power_button() {
    local now=$(date +%s)
    local config=$(grep "^power_button:" "$TRIGGER_CONF" 2>/dev/null)
    
    if [ -z "$config" ]; then
        return
    fi
    
    local threshold=$(echo "$config" | cut -d':' -f2)
    local window=$(echo "$config" | cut -d':' -f3)
    local action=$(echo "$config" | cut -d':' -f4)
    
    threshold=${threshold:-7}
    window=${window:-5}
    
    if [ $((now - POWER_BUTTON_FIRST)) -gt "$window" ]; then
        POWER_BUTTON_COUNT=1
        POWER_BUTTON_FIRST=$now
    else
        POWER_BUTTON_COUNT=$((POWER_BUTTON_COUNT + 1))
    fi
    
    if [ "$POWER_BUTTON_COUNT" -ge "$threshold" ]; then
        POWER_BUTTON_COUNT=0
        if [ "$action" = "alert" ]; then
            activate_alert_mode "power_button"
        else
            activate_hostile_mode "power_button"
        fi
    fi
}

##########################################################################################
# INPUT EVENT MONITORING
##########################################################################################

monitor_input_events() {
    log_info "Starting input event monitor"
    
    # Find input device for keys
    for device in /dev/input/event*; do
        if [ -c "$device" ]; then
            # Check if this device handles keys
            if getevent -pl "$device" 2>/dev/null | grep -q "KEY"; then
                monitor_device "$device" &
            fi
        fi
    done
}

monitor_device() {
    local device="$1"
    log_debug "Monitoring input device: $device"
    
    getevent -l "$device" 2>/dev/null | while read -r timestamp type code value; do
        case "$code" in
            *KEY_VOLUMEDOWN*)
                if [ "$value" = "DOWN" ] || [ "$value" = "1" ]; then
                    handle_volume_trigger
                fi
                ;;
            *KEY_POWER*)
                if [ "$value" = "DOWN" ] || [ "$value" = "1" ]; then
                    handle_power_button
                fi
                ;;
        esac
    done
}

##########################################################################################
# SETTINGS MONITOR
##########################################################################################

monitor_settings() {
    log_info "Starting settings monitor"
    
    local last_airplane=""
    
    while true; do
        # Monitor airplane mode toggles
        current_airplane=$(settings get global airplane_mode_on 2>/dev/null)
        if [ -n "$last_airplane" ] && [ "$current_airplane" != "$last_airplane" ]; then
            handle_airplane_toggle
        fi
        last_airplane="$current_airplane"
        
        # Monitor ADB setting changes
        adb_enabled=$(settings get global adb_enabled 2>/dev/null)
        if [ "$adb_enabled" = "1" ] && is_hostile_mode; then
            log_warn "ADB enable attempt in hostile mode - blocking"
            settings put global adb_enabled 0 2>/dev/null
        fi
        
        sleep 1
    done
}

##########################################################################################
# MAIN MONITORING LOOP
##########################################################################################

monitor_all_triggers() {
    log_info "Starting hostile mode trigger monitors"
    
    # Start input event monitors
    monitor_input_events &
    
    # Start settings monitor
    monitor_settings &
    
    # SIM state is monitored in service.sh
    
    log_info "All trigger monitors active"
    
    # Keep the main process running
    while true; do
        sleep 60
        
        # Periodic status check
        log_debug "Trigger monitor heartbeat - state: $(get_current_state)"
    done
}

##########################################################################################
# DEACTIVATION (REQUIRES RECOVERY)
##########################################################################################

deactivate_hostile_mode() {
    # This should only be called after recovery phrase validation
    if [ ! -f "${DATA_DIR}/.recovery_validated" ]; then
        log_error "Cannot deactivate - recovery not validated"
        return 1
    fi
    
    log_info "Deactivating hostile mode"
    
    # Stop enforcement
    set_state "NORMAL"
    
    # Remove recovery validation file
    rm -f "${DATA_DIR}/.recovery_validated"
    
    # Restore USB
    sh "${MODDIR}/common/usb_defense.sh" restore --force
    
    # Restore ADB
    sh "${MODDIR}/common/adb_neutralizer.sh" restore --force
    
    # Disable airplane mode
    disable_airplane_mode
    
    # Re-enable biometrics
    enable_biometrics
    
    log_info "Normal mode restored"
    
    # Vibrate confirmation (2 long pulses)
    cmd vibrator vibrate 500 2>/dev/null
    sleep 0.3
    cmd vibrator vibrate 500 2>/dev/null
    
    return 0
}

##########################################################################################
# MAIN EXECUTION
##########################################################################################

case "$1" in
    "activate")
        activate_hostile_mode "${2:-manual}"
        ;;
    "enforce")
        enforce_hostile_mode
        ;;
    "alert")
        activate_alert_mode "${2:-manual}"
        ;;
    "deactivate")
        deactivate_hostile_mode
        ;;
    "monitor")
        monitor_all_triggers
        ;;
    "handle_sim_trigger")
        # Called by service.sh when SIM removal detected
        handle_sim_removal
        ;;
    "handle_compound_check")
        # Called when USB connected during ALERT mode
        handle_compound_sim_usb
        ;;
    "boot_anomaly")
        # Called by post-fs-data.sh with anomaly type
        handle_boot_anomaly "$2"
        ;;
    "status")
        echo "=== Hostile Mode Status ==="
        echo "Current state: $(get_current_state)"
        echo "State timestamp: $(get_state_timestamp)"
        echo ""
        echo "=== Trigger Configuration ==="
        if [ -f "$TRIGGER_CONF" ]; then
            grep -v "^#" "$TRIGGER_CONF" | grep -v "^$"
        else
            echo "No configuration found"
        fi
        echo ""
        echo "=== Recent Activations ==="
        tail -5 "${DATA_DIR}/hostile_activations.log" 2>/dev/null || echo "None"
        ;;
    "test")
        echo "Testing hostile mode trigger in 3 seconds..."
        echo "Press Ctrl+C to cancel"
        sleep 3
        activate_hostile_mode "test"
        ;;
    *)
        echo "Usage: $0 {activate|enforce|alert|deactivate|monitor|status|test}"
        exit 1
        ;;
esac

