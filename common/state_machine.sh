#!/system/bin/sh
##########################################################################################
#
# Custos Anti-Forensic Defense Module
# Defensive State Machine Controller
#
# Manages state transitions and ensures consistent defensive posture
# Supports: NORMAL, TRAVELER, ALERT, HOSTILE, RECOVERY, LOCKDOWN
#
##########################################################################################

MODDIR="${0%/*}/.."
. "${MODDIR}/common/functions.sh"

# State definitions
STATE_NORMAL="NORMAL"
STATE_TRAVELER="TRAVELER"
STATE_ALERT="ALERT"
STATE_HOSTILE="HOSTILE"
STATE_RECOVERY="RECOVERY"
STATE_LOCKDOWN="LOCKDOWN"

# Transition log
TRANSITION_LOG="${DATA_DIR}/state_transitions.log"

##########################################################################################
# STATE TRANSITION RULES
##########################################################################################

# Valid state transitions:
#
# NORMAL -> TRAVELER (manual activation)
# NORMAL -> ALERT (suspicious activity)
# NORMAL -> HOSTILE (immediate threat)
#
# TRAVELER -> NORMAL (manual deactivation)
# TRAVELER -> HOSTILE (trigger while in traveler mode)
#
# ALERT -> NORMAL (timeout, no escalation)
# ALERT -> HOSTILE (confirmed threat)
#
# HOSTILE -> RECOVERY (valid recovery phrase)
# RECOVERY -> NORMAL (restoration complete)
#
# LOCKDOWN -> (no exit - permanent lockdown after too many failures)

is_valid_transition() {
    local from_state="$1"
    local to_state="$2"
    
    case "${from_state}:${to_state}" in
        # From NORMAL
        "NORMAL:TRAVELER") return 0 ;;
        "NORMAL:ALERT") return 0 ;;
        "NORMAL:HOSTILE") return 0 ;;
        
        # From TRAVELER
        "TRAVELER:NORMAL") return 0 ;;
        "TRAVELER:HOSTILE") return 0 ;;
        "TRAVELER:ALERT") return 0 ;;
        
        # From ALERT
        "ALERT:NORMAL") return 0 ;;
        "ALERT:HOSTILE") return 0 ;;
        
        # From HOSTILE
        "HOSTILE:RECOVERY") return 0 ;;
        "HOSTILE:LOCKDOWN") return 0 ;;
        
        # From RECOVERY
        "RECOVERY:NORMAL") return 0 ;;
        "RECOVERY:HOSTILE") return 0 ;;
        
        # Invalid
        *) return 1 ;;
    esac
}

##########################################################################################
# STATE HANDLERS
##########################################################################################

handle_state_normal() {
    log_info "Entering NORMAL state"
    
    # Clear any alert/hostile/traveler artifacts
    rm -f "${DATA_DIR}/.alert_timestamp" 2>/dev/null
    rm -f "${DATA_DIR}/.recovery_validated" 2>/dev/null
    rm -f "${DATA_DIR}/.alert_reason" 2>/dev/null
    rm -f "${DATA_DIR}/.active_profile" 2>/dev/null
    
    # Restore normal USB functionality if needed
    # (Only if coming from non-hostile state - hostile requires recovery)
    
    # Ensure baseline monitoring is active
    # (USB monitoring continues in normal mode for early detection)
}

handle_state_traveler() {
    local reason="$1"
    log_info "Entering TRAVELER state: $reason"
    
    # Record traveler activation
    echo "$(date +%s):$reason" >> "${DATA_DIR}/traveler_activations.log"
    
    # Apply traveler profile
    sh "${MODDIR}/common/profiles.sh" activate traveler
    
    # Haptic feedback
    cmd vibrator vibrate 100 2>/dev/null
    sleep 0.1
    cmd vibrator vibrate 100 2>/dev/null
}

handle_state_alert() {
    local reason="$1"
    log_warn "Entering ALERT state: $reason"
    
    # Record alert timestamp and reason
    date +%s > "${DATA_DIR}/.alert_timestamp"
    echo "$reason" > "${DATA_DIR}/.alert_reason"
    
    # Single haptic feedback
    cmd vibrator vibrate 100 2>/dev/null
    
    # Schedule auto-return to normal (or to traveler if came from there)
    local timeout=$(grep "^alert_timeout:" "${DATA_DIR}/triggers.conf" 2>/dev/null | cut -d':' -f2)
    timeout=${timeout:-30}
    
    local return_state="$STATE_NORMAL"
    # Check if we came from traveler mode
    if [ -f "${DATA_DIR}/.pre_alert_state" ]; then
        return_state=$(cat "${DATA_DIR}/.pre_alert_state")
    fi
    
    (
        sleep "$timeout"
        current=$(get_current_state)
        if [ "$current" = "ALERT" ]; then
            log_info "Alert timeout - returning to $return_state"
            transition_state "$return_state" "alert_timeout"
        fi
    ) &
}

handle_state_hostile() {
    local reason="$1"
    log_warn "Entering HOSTILE state: $reason"
    
    # Record hostile activation
    echo "$(date +%s):$reason" >> "${DATA_DIR}/hostile_activations.log"
    
    # Apply hostile custody profile
    sh "${MODDIR}/common/profiles.sh" activate hostile_custody force
    
    # Or use direct hostile mode if profiles not available
    if [ $? -ne 0 ]; then
        sh "${MODDIR}/common/hostile_mode.sh" activate "$reason"
    fi
}

handle_state_recovery() {
    log_info "Entering RECOVERY state"
    
    # Stop hostile enforcement temporarily
    # User is attempting recovery
    
    # Mark recovery in progress
    touch "${DATA_DIR}/.recovery_in_progress"
}

handle_state_lockdown() {
    log_error "Entering LOCKDOWN state - PERMANENT"
    
    # This is permanent - too many failed recovery attempts
    
    # Execute maximum defensive measures
    sh "${MODDIR}/common/key_eviction.sh" evict-all
    sh "${MODDIR}/common/usb_defense.sh" enforce
    sh "${MODDIR}/common/adb_neutralizer.sh" neutralize
    
    # Wipe recovery phrase to prevent further attempts
    secure_delete "${DATA_DIR}/recovery_phrase.enc"
    
    # Lock forever
    while true; do
        input keyevent 26  # Keep screen locked
        sleep 10
    done
}

##########################################################################################
# STATE TRANSITION
##########################################################################################

transition_state() {
    local new_state="$1"
    local reason="${2:-unspecified}"
    
    local current_state=$(get_current_state)
    
    # Validate transition
    if [ "$current_state" = "$new_state" ]; then
        log_debug "Already in state $new_state"
        return 0
    fi
    
    if ! is_valid_transition "$current_state" "$new_state"; then
        log_error "Invalid state transition: $current_state -> $new_state"
        return 1
    fi
    
    log_info "State transition: $current_state -> $new_state (reason: $reason)"
    
    # Save pre-alert state for return after alert
    if [ "$new_state" = "$STATE_ALERT" ]; then
        echo "$current_state" > "${DATA_DIR}/.pre_alert_state"
    fi
    
    # Log transition
    echo "$(date +%s):${current_state}:${new_state}:${reason}" >> "$TRANSITION_LOG"
    
    # Update state
    set_state "$new_state"
    
    # Execute state handler
    case "$new_state" in
        "$STATE_NORMAL")
            handle_state_normal
            ;;
        "$STATE_TRAVELER")
            handle_state_traveler "$reason"
            ;;
        "$STATE_ALERT")
            handle_state_alert "$reason"
            ;;
        "$STATE_HOSTILE")
            handle_state_hostile "$reason"
            ;;
        "$STATE_RECOVERY")
            handle_state_recovery
            ;;
        "$STATE_LOCKDOWN")
            handle_state_lockdown
            ;;
    esac
    
    return 0
}

##########################################################################################
# EVENT PROCESSING
##########################################################################################

process_event() {
    local event_type="$1"
    local event_data="$2"
    
    local current_state=$(get_current_state)
    
    log_debug "Processing event: $event_type (data: $event_data) in state: $current_state"
    
    case "$current_state" in
        "$STATE_NORMAL")
            case "$event_type" in
                "activate_traveler")
                    transition_state "$STATE_TRAVELER" "$event_type"
                    ;;
                "usb_data_attempt"|"airplane_toggle"|"screen_off_usb"|"sim_removed")
                    transition_state "$STATE_ALERT" "$event_type"
                    ;;
                "volume_panic"|"sim_usb_compound"|"lockscreen_fail"|"boot_anomaly_strong")
                    transition_state "$STATE_HOSTILE" "$event_type"
                    ;;
                "boot_anomaly_weak")
                    transition_state "$STATE_ALERT" "$event_type"
                    ;;
            esac
            ;;
        
        "$STATE_TRAVELER")
            case "$event_type" in
                "deactivate_traveler")
                    transition_state "$STATE_NORMAL" "$event_type"
                    ;;
                "usb_data_attempt"|"sim_removed")
                    # In traveler mode, these are more suspicious
                    transition_state "$STATE_ALERT" "$event_type"
                    ;;
                "volume_panic"|"sim_usb_compound"|"lockscreen_fail"|"boot_anomaly_strong")
                    # Immediate escalation from traveler to hostile
                    transition_state "$STATE_HOSTILE" "$event_type"
                    ;;
                "boot_anomaly_weak")
                    transition_state "$STATE_ALERT" "$event_type"
                    ;;
            esac
            ;;
        
        "$STATE_ALERT")
            case "$event_type" in
                "timeout"|"user_dismiss")
                    # Return to previous state (normal or traveler)
                    local return_state=$(cat "${DATA_DIR}/.pre_alert_state" 2>/dev/null || echo "$STATE_NORMAL")
                    rm -f "${DATA_DIR}/.pre_alert_state"
                    transition_state "$return_state" "$event_type"
                    ;;
                "usb_data_attempt"|"volume_panic"|"sim_removal"|"lockscreen_fail"|"boot_anomaly_strong"|"sim_usb_compound")
                    # Any significant event in alert mode escalates to hostile
                    transition_state "$STATE_HOSTILE" "$event_type"
                    ;;
            esac
            ;;
        
        "$STATE_HOSTILE")
            case "$event_type" in
                "recovery_phrase_valid")
                    transition_state "$STATE_RECOVERY" "$event_type"
                    ;;
                "recovery_phrase_fail")
                    # Track failures
                    local fail_count=$(cat "${DATA_DIR}/.recovery_failures" 2>/dev/null || echo "0")
                    fail_count=$((fail_count + 1))
                    echo "$fail_count" > "${DATA_DIR}/.recovery_failures"
                    
                    local max_attempts=$(grep "^recovery_max_attempts:" "${DATA_DIR}/triggers.conf" 2>/dev/null | cut -d':' -f2)
                    max_attempts=${max_attempts:-3}
                    
                    if [ "$fail_count" -ge "$max_attempts" ]; then
                        transition_state "$STATE_LOCKDOWN" "max_recovery_attempts"
                    fi
                    ;;
                "failsafe_expired")
                    transition_state "$STATE_RECOVERY" "failsafe_timer"
                    ;;
            esac
            ;;
        
        "$STATE_RECOVERY")
            case "$event_type" in
                "restoration_complete")
                    rm -f "${DATA_DIR}/.recovery_failures"
                    rm -f "${DATA_DIR}/.recovery_in_progress"
                    rm -f "${DATA_DIR}/.pre_alert_state"
                    transition_state "$STATE_NORMAL" "$event_type"
                    ;;
                "recovery_cancelled"|"recovery_timeout")
                    rm -f "${DATA_DIR}/.recovery_in_progress"
                    transition_state "$STATE_HOSTILE" "$event_type"
                    ;;
            esac
            ;;
        
        "$STATE_LOCKDOWN")
            # No events processed in lockdown
            log_warn "Event ignored in lockdown state: $event_type"
            ;;
    esac
}

##########################################################################################
# STATE PERSISTENCE
##########################################################################################

persist_state() {
    # State is automatically persisted by set_state in functions.sh
    # This function ensures state survives reboots
    
    sync
    log_debug "State persisted to disk"
}

restore_state() {
    local saved_state=$(get_current_state)
    
    if [ -z "$saved_state" ] || [ "$saved_state" = "UNKNOWN" ]; then
        log_info "No saved state - initializing to NORMAL"
        set_state "$STATE_NORMAL"
        return
    fi
    
    log_info "Restored state: $saved_state"
    
    # Re-apply state handlers for persistent states
    case "$saved_state" in
        "$STATE_TRAVELER")
            log_info "Traveler mode persisted - re-applying"
            handle_state_traveler "boot_persistence"
            ;;
        "$STATE_HOSTILE")
            log_warn "Hostile mode persisted - re-enforcing"
            handle_state_hostile "boot_persistence"
            ;;
        "$STATE_LOCKDOWN")
            log_error "Lockdown mode persisted - enforcing"
            handle_state_lockdown
            ;;
    esac
}

##########################################################################################
# STATE MACHINE CONTROLLER
##########################################################################################

run_state_machine() {
    log_info "State machine controller starting"
    
    # Load device profile
    sh "${MODDIR}/common/device_profiles.sh" load 2>/dev/null
    
    # Restore state from previous session
    restore_state
    
    # Create named pipe for event processing
    PIPE_FILE="${DATA_DIR}/.state_events"
    rm -f "$PIPE_FILE"
    mkfifo "$PIPE_FILE" 2>/dev/null
    
    # Event processing loop
    while true; do
        if read -r event < "$PIPE_FILE"; then
            event_type=$(echo "$event" | cut -d':' -f1)
            event_data=$(echo "$event" | cut -d':' -f2-)
            process_event "$event_type" "$event_data"
        fi
    done
}

##########################################################################################
# EVENT DISPATCH
##########################################################################################

dispatch_event() {
    local event_type="$1"
    local event_data="$2"
    
    PIPE_FILE="${DATA_DIR}/.state_events"
    
    if [ -p "$PIPE_FILE" ]; then
        echo "${event_type}:${event_data}" > "$PIPE_FILE"
    else
        # Fallback to direct processing
        process_event "$event_type" "$event_data"
    fi
}

##########################################################################################
# MAIN EXECUTION
##########################################################################################

case "$1" in
    "run")
        run_state_machine
        ;;
    "transition")
        transition_state "$2" "$3"
        ;;
    "event")
        dispatch_event "$2" "$3"
        ;;
    "restore")
        restore_state
        ;;
    "status")
        echo "=== State Machine Status ==="
        echo "Current state: $(get_current_state)"
        echo "State timestamp: $(date -d @$(get_state_timestamp) 2>/dev/null || echo $(get_state_timestamp))"
        echo ""
        echo "Active profile: $(cat "${DATA_DIR}/.active_profile" 2>/dev/null || echo 'none')"
        echo "Device profile: $(cat "${DATA_DIR}/.device_profile" 2>/dev/null || echo 'unknown')"
        echo ""
        echo "=== Recent Transitions ==="
        tail -10 "$TRANSITION_LOG" 2>/dev/null | while read line; do
            ts=$(echo "$line" | cut -d':' -f1)
            from=$(echo "$line" | cut -d':' -f2)
            to=$(echo "$line" | cut -d':' -f3)
            reason=$(echo "$line" | cut -d':' -f4-)
            echo "$(date -d @$ts 2>/dev/null || echo $ts): $from -> $to ($reason)"
        done
        ;;
    "graph")
        echo "State Machine Graph (Mermaid format):"
        echo ""
        echo "stateDiagram-v2"
        echo "    [*] --> NORMAL: Boot"
        echo "    "
        echo "    NORMAL --> TRAVELER: Manual activation"
        echo "    NORMAL --> ALERT: Suspicious activity"
        echo "    NORMAL --> HOSTILE: Immediate threat"
        echo "    "
        echo "    TRAVELER --> NORMAL: Manual deactivation"
        echo "    TRAVELER --> HOSTILE: Threat in traveler mode"
        echo "    TRAVELER --> ALERT: Suspicious activity"
        echo "    "
        echo "    ALERT --> NORMAL: Timeout"
        echo "    ALERT --> TRAVELER: Return to traveler"
        echo "    ALERT --> HOSTILE: Confirmed threat"
        echo "    "
        echo "    HOSTILE --> RECOVERY: Valid phrase"
        echo "    HOSTILE --> LOCKDOWN: Max failures"
        echo "    "
        echo "    RECOVERY --> NORMAL: Restored"
        ;;
    *)
        echo "Custos State Machine Controller"
        echo ""
        echo "Usage: $0 <command> [args]"
        echo ""
        echo "Commands:"
        echo "  run                Run state machine controller"
        echo "  transition <s> <r> Transition to state with reason"
        echo "  event <type> <d>   Dispatch event"
        echo "  restore            Restore state from disk"
        echo "  status             Show current status"
        echo "  graph              Display state diagram"
        echo ""
        echo "States: NORMAL, TRAVELER, ALERT, HOSTILE, RECOVERY, LOCKDOWN"
        exit 1
        ;;
esac
