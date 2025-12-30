#!/system/bin/sh
##########################################################################################
#
# Custos Anti-Forensic Defense Module
# Recovery Phrase Validator
#
# Validates recovery phrase to exit hostile mode
# Implements secure validation with rate limiting
#
##########################################################################################

MODDIR="${0%/*}/.."
. "${MODDIR}/common/functions.sh"

# Recovery configuration
PHRASE_HASH_FILE="${DATA_DIR}/recovery_phrase.enc"
ATTEMPT_LOG="${DATA_DIR}/recovery_attempts.log"
LOCKOUT_FILE="${DATA_DIR}/.recovery_lockout"
VALIDATION_FLAG="${DATA_DIR}/.recovery_validated"

# Security parameters
MAX_ATTEMPTS=3
LOCKOUT_DURATION=300  # 5 minutes lockout after max attempts
ATTEMPT_WINDOW=60     # Window for counting attempts

##########################################################################################
# PHRASE VALIDATION
##########################################################################################

validate_phrase() {
    local input_phrase="$1"
    
    # Check for lockout
    if is_locked_out; then
        local remaining=$(get_lockout_remaining)
        log_warn "Recovery locked out for ${remaining}s"
        echo "LOCKED:${remaining}"
        return 1
    fi
    
    # Get stored hash
    if [ ! -f "$PHRASE_HASH_FILE" ]; then
        log_error "Recovery phrase file not found"
        echo "ERROR:no_phrase_configured"
        return 1
    fi
    
    local stored_hash=$(cat "$PHRASE_HASH_FILE" 2>/dev/null)
    
    if [ -z "$stored_hash" ]; then
        log_error "Recovery phrase hash is empty"
        echo "ERROR:empty_hash"
        return 1
    fi
    
    # Compute input hash
    local input_hash=$(echo -n "$input_phrase" | sha512sum | cut -d' ' -f1)
    
    # Compare hashes (constant-time comparison would be better, but shell limitations)
    if [ "$input_hash" = "$stored_hash" ]; then
        log_info "Recovery phrase validated successfully"
        handle_successful_validation
        echo "SUCCESS"
        return 0
    else
        log_warn "Recovery phrase validation failed"
        handle_failed_validation
        
        local attempts=$(get_recent_attempts)
        local remaining=$((MAX_ATTEMPTS - attempts))
        
        echo "FAILED:${remaining}"
        return 1
    fi
}

##########################################################################################
# ATTEMPT TRACKING
##########################################################################################

record_attempt() {
    local result="$1"
    local timestamp=$(date +%s)
    
    echo "${timestamp}:${result}" >> "$ATTEMPT_LOG"
    chmod 600 "$ATTEMPT_LOG"
}

get_recent_attempts() {
    local now=$(date +%s)
    local window_start=$((now - ATTEMPT_WINDOW))
    local count=0
    
    if [ -f "$ATTEMPT_LOG" ]; then
        while IFS=: read -r timestamp result; do
            if [ "$timestamp" -ge "$window_start" ] && [ "$result" = "FAILED" ]; then
                count=$((count + 1))
            fi
        done < "$ATTEMPT_LOG"
    fi
    
    echo "$count"
}

clear_attempts() {
    rm -f "$ATTEMPT_LOG" 2>/dev/null
    rm -f "$LOCKOUT_FILE" 2>/dev/null
}

##########################################################################################
# LOCKOUT MANAGEMENT
##########################################################################################

is_locked_out() {
    if [ ! -f "$LOCKOUT_FILE" ]; then
        return 1
    fi
    
    local lockout_time=$(cat "$LOCKOUT_FILE" 2>/dev/null)
    local now=$(date +%s)
    local elapsed=$((now - lockout_time))
    
    if [ $elapsed -ge $LOCKOUT_DURATION ]; then
        # Lockout expired
        rm -f "$LOCKOUT_FILE"
        return 1
    fi
    
    return 0
}

get_lockout_remaining() {
    if [ ! -f "$LOCKOUT_FILE" ]; then
        echo "0"
        return
    fi
    
    local lockout_time=$(cat "$LOCKOUT_FILE" 2>/dev/null)
    local now=$(date +%s)
    local elapsed=$((now - lockout_time))
    local remaining=$((LOCKOUT_DURATION - elapsed))
    
    if [ $remaining -lt 0 ]; then
        remaining=0
    fi
    
    echo "$remaining"
}

trigger_lockout() {
    log_warn "Triggering recovery lockout"
    date +%s > "$LOCKOUT_FILE"
    chmod 600 "$LOCKOUT_FILE"
    
    # Vibrate warning pattern
    for i in 1 2 3; do
        cmd vibrator vibrate 500 2>/dev/null
        sleep 0.5
    done
}

##########################################################################################
# VALIDATION HANDLERS
##########################################################################################

handle_successful_validation() {
    record_attempt "SUCCESS"
    clear_attempts
    
    # Create validation flag
    touch "$VALIDATION_FLAG"
    chmod 600 "$VALIDATION_FLAG"
    
    # Notify state machine
    sh "${MODDIR}/common/state_machine.sh" event "recovery_phrase_valid" ""
    
    # Vibrate success pattern (2 short, 1 long)
    cmd vibrator vibrate 100 2>/dev/null
    sleep 0.1
    cmd vibrator vibrate 100 2>/dev/null
    sleep 0.1
    cmd vibrator vibrate 500 2>/dev/null
}

handle_failed_validation() {
    record_attempt "FAILED"
    
    local attempts=$(get_recent_attempts)
    
    log_warn "Failed recovery attempts: $attempts / $MAX_ATTEMPTS"
    
    if [ "$attempts" -ge "$MAX_ATTEMPTS" ]; then
        trigger_lockout
        
        # Check for permanent lockdown threshold
        local total_lockouts=$(grep -c "^" "${DATA_DIR}/.lockout_count" 2>/dev/null || echo "0")
        total_lockouts=$((total_lockouts + 1))
        echo "$total_lockouts" >> "${DATA_DIR}/.lockout_count"
        
        if [ "$total_lockouts" -ge 3 ]; then
            log_error "Maximum lockouts exceeded - triggering permanent lockdown"
            sh "${MODDIR}/common/state_machine.sh" event "max_lockouts" ""
        fi
    fi
    
    # Notify state machine
    sh "${MODDIR}/common/state_machine.sh" event "recovery_phrase_fail" "$attempts"
    
    # Vibrate failure pattern
    cmd vibrator vibrate 1000 2>/dev/null
}

##########################################################################################
# PHRASE MANAGEMENT
##########################################################################################

set_phrase() {
    local new_phrase="$1"
    
    if [ -z "$new_phrase" ]; then
        log_error "Cannot set empty recovery phrase"
        return 1
    fi
    
    if [ ${#new_phrase} -lt 8 ]; then
        log_warn "Recovery phrase should be at least 8 characters"
    fi
    
    # Hash and store
    local hash=$(echo -n "$new_phrase" | sha512sum | cut -d' ' -f1)
    echo "$hash" > "$PHRASE_HASH_FILE"
    chmod 600 "$PHRASE_HASH_FILE"
    
    log_info "Recovery phrase updated"
    return 0
}

##########################################################################################
# RECOVERY SERVICE
##########################################################################################

run_recovery_service() {
    log_info "Recovery validator service starting"
    
    # Create named pipe for phrase input
    PIPE_FILE="${DATA_DIR}/.recovery_input"
    rm -f "$PIPE_FILE"
    mkfifo "$PIPE_FILE" 2>/dev/null
    chmod 600 "$PIPE_FILE"
    
    # Service loop
    while true; do
        if read -r input < "$PIPE_FILE"; then
            result=$(validate_phrase "$input")
            echo "$result" > "${DATA_DIR}/.recovery_result"
        fi
    done
}

##########################################################################################
# INTERACTIVE RECOVERY (via terminal/app)
##########################################################################################

interactive_recovery() {
    if ! is_hostile_mode; then
        echo "Device is not in hostile mode"
        return 0
    fi
    
    echo "======================================"
    echo "CUSTOS RECOVERY MODE"
    echo "======================================"
    echo ""
    
    if is_locked_out; then
        local remaining=$(get_lockout_remaining)
        echo "Recovery is locked out."
        echo "Try again in ${remaining} seconds."
        return 1
    fi
    
    local attempts=$(get_recent_attempts)
    local remaining=$((MAX_ATTEMPTS - attempts))
    
    echo "Attempts remaining: $remaining"
    echo ""
    echo -n "Enter recovery phrase: "
    
    # Read phrase (hidden input)
    stty -echo 2>/dev/null
    read -r phrase
    stty echo 2>/dev/null
    echo ""
    
    result=$(validate_phrase "$phrase")
    
    case "$result" in
        SUCCESS)
            echo ""
            echo "Recovery phrase accepted!"
            echo "Restoring normal mode..."
            
            sh "${MODDIR}/common/hostile_mode.sh" deactivate
            
            echo "Device restored to normal mode."
            return 0
            ;;
        LOCKED:*)
            remaining=$(echo "$result" | cut -d':' -f2)
            echo "Too many failed attempts."
            echo "Locked for ${remaining} seconds."
            return 1
            ;;
        FAILED:*)
            remaining=$(echo "$result" | cut -d':' -f2)
            echo "Invalid recovery phrase."
            echo "Attempts remaining: $remaining"
            return 1
            ;;
        ERROR:*)
            error=$(echo "$result" | cut -d':' -f2)
            echo "Error: $error"
            return 1
            ;;
    esac
}

##########################################################################################
# MAIN EXECUTION
##########################################################################################

case "$1" in
    "validate")
        validate_phrase "$2"
        ;;
    "set")
        set_phrase "$2"
        ;;
    "service")
        run_recovery_service
        ;;
    "interactive"|"recover")
        interactive_recovery
        ;;
    "status")
        echo "=== Recovery Validator Status ==="
        echo "Phrase configured: $([ -f "$PHRASE_HASH_FILE" ] && echo 'YES' || echo 'NO')"
        echo "Locked out: $(is_locked_out && echo 'YES' || echo 'NO')"
        
        if is_locked_out; then
            echo "Lockout remaining: $(get_lockout_remaining)s"
        fi
        
        echo "Recent failed attempts: $(get_recent_attempts)"
        echo "Max attempts: $MAX_ATTEMPTS"
        echo ""
        echo "=== Recent Attempt Log ==="
        tail -10 "$ATTEMPT_LOG" 2>/dev/null | while IFS=: read -r ts result; do
            echo "$(date -d @$ts 2>/dev/null || echo $ts): $result"
        done
        ;;
    "reset")
        # Emergency reset (requires Magisk manager or recovery)
        if [ "$2" = "--confirm-reset" ]; then
            log_warn "Resetting recovery validator state"
            clear_attempts
            rm -f "${DATA_DIR}/.lockout_count"
            rm -f "$VALIDATION_FLAG"
            echo "Recovery validator reset"
        else
            echo "Usage: $0 reset --confirm-reset"
            echo "WARNING: This will clear all lockout state"
        fi
        ;;
    *)
        echo "Usage: $0 {validate <phrase>|set <phrase>|service|interactive|status|reset}"
        exit 1
        ;;
esac

