#!/system/bin/sh
##########################################################################################
#
# Custos Anti-Forensic Defense Module
# Profile Manager
#
# Manages security profiles (TRAVELER, HOSTILE_CUSTODY, etc.)
# Handles activation, deactivation, and enforcement
#
##########################################################################################

MODDIR="${0%/*}/.."
. "${MODDIR}/common/functions.sh"

# Profile directories
PROFILE_DIR="${MODDIR}/config/profiles"
USER_PROFILE_DIR="${DATA_DIR}/profiles"
ACTIVE_PROFILE_FILE="${DATA_DIR}/.active_profile"

##########################################################################################
# PROFILE CONFIGURATION PARSER
##########################################################################################

# Parse INI-style configuration
# Usage: parse_profile_value <profile_file> <section> <key>
parse_profile_value() {
    local file="$1"
    local section="$2"
    local key="$3"
    
    if [ ! -f "$file" ]; then
        return 1
    fi
    
    # Find section and key
    awk -F= -v section="[$section]" -v key="$key" '
        $0 == section { in_section=1; next }
        /^\[/ { in_section=0 }
        in_section && $1 == key { print $2; exit }
    ' "$file" | tr -d ' '
}

# Get profile display name
get_profile_name() {
    local profile="$1"
    local file="${PROFILE_DIR}/${profile}.conf"
    
    if [ -f "$file" ]; then
        parse_profile_value "$file" "profile" "display_name"
    else
        echo "$profile"
    fi
}

# Check if profile exists
profile_exists() {
    local profile="$1"
    [ -f "${PROFILE_DIR}/${profile}.conf" ] || [ -f "${USER_PROFILE_DIR}/${profile}.conf" ]
}

# Get profile file path
get_profile_path() {
    local profile="$1"
    
    # User profiles override system profiles
    if [ -f "${USER_PROFILE_DIR}/${profile}.conf" ]; then
        echo "${USER_PROFILE_DIR}/${profile}.conf"
    elif [ -f "${PROFILE_DIR}/${profile}.conf" ]; then
        echo "${PROFILE_DIR}/${profile}.conf"
    else
        echo ""
    fi
}

##########################################################################################
# PROFILE STATE MANAGEMENT
##########################################################################################

get_active_profile() {
    if [ -f "$ACTIVE_PROFILE_FILE" ]; then
        cat "$ACTIVE_PROFILE_FILE" 2>/dev/null
    else
        echo "none"
    fi
}

set_active_profile() {
    local profile="$1"
    echo "$profile" > "$ACTIVE_PROFILE_FILE"
    chmod 600 "$ACTIVE_PROFILE_FILE"
}

clear_active_profile() {
    rm -f "$ACTIVE_PROFILE_FILE"
}

is_profile_active() {
    local profile="$1"
    [ "$(get_active_profile)" = "$profile" ]
}

##########################################################################################
# TRAVELER PROFILE IMPLEMENTATION
##########################################################################################

apply_traveler_profile() {
    local profile_file="$1"
    
    log_info "Applying Traveler profile"
    
    # USB restrictions
    local usb_mode=$(parse_profile_value "$profile_file" "usb" "mode")
    case "$usb_mode" in
        "restrict")
            # Disable MTP/PTP but not full lockdown
            safe_resetprop sys.usb.config "charging"
            settings put global adb_enabled 0 2>/dev/null
            settings put global development_settings_enabled 0 2>/dev/null
            ;;
        "charge")
            sh "${MODDIR}/common/usb_defense.sh" enforce
            ;;
    esac
    
    # ADB handling
    local adb_state=$(parse_profile_value "$profile_file" "adb" "state")
    if [ "$adb_state" = "disabled" ]; then
        settings put global adb_enabled 0 2>/dev/null
        settings put global development_settings_enabled 0 2>/dev/null
        
        local clear_keys=$(parse_profile_value "$profile_file" "adb" "clear_keys")
        if [ "$clear_keys" = "true" ]; then
            rm -f /data/misc/adb/adb_keys 2>/dev/null
        fi
    fi
    
    # Session tokens
    local token_action=$(parse_profile_value "$profile_file" "encryption" "session_tokens")
    if [ "$token_action" = "clear" ]; then
        sh "${MODDIR}/common/key_eviction.sh" tokens
    fi
    
    # Screen lock
    local lock_mode=$(parse_profile_value "$profile_file" "screen" "lock_mode")
    if [ "$lock_mode" = "strict" ]; then
        local timeout=$(parse_profile_value "$profile_file" "screen" "timeout_override")
        if [ -n "$timeout" ] && [ "$timeout" != "0" ]; then
            settings put system screen_off_timeout $((timeout * 1000)) 2>/dev/null
        fi
    fi
    
    local hide_notif=$(parse_profile_value "$profile_file" "screen" "hide_notifications")
    if [ "$hide_notif" = "true" ]; then
        settings put secure lock_screen_show_notifications 0 2>/dev/null
    fi
    
    # Network restrictions
    local net_mode=$(parse_profile_value "$profile_file" "network" "mode")
    if [ "$net_mode" = "restrict" ]; then
        # Disable Wi-Fi auto-connect
        settings put global wifi_networks_available_notification_on 0 2>/dev/null
    elif [ "$net_mode" = "airplane" ]; then
        enable_airplane_mode
    fi
    
    # Data protection
    local clear_clip=$(parse_profile_value "$profile_file" "data" "clear_clipboard")
    if [ "$clear_clip" = "true" ]; then
        service call clipboard 2 2>/dev/null
    fi
    
    local clear_recent=$(parse_profile_value "$profile_file" "data" "clear_recents")
    if [ "$clear_recent" = "true" ]; then
        am broadcast -a com.android.systemui.recents.ACTION_CLEAR_ALL 2>/dev/null
    fi
    
    # Set state
    set_state "TRAVELER"
    set_active_profile "traveler"
    
    # Haptic feedback
    cmd vibrator vibrate 100 2>/dev/null
    sleep 0.1
    cmd vibrator vibrate 100 2>/dev/null
    sleep 0.1
    cmd vibrator vibrate 100 2>/dev/null
    
    log_info "Traveler profile applied successfully"
}

##########################################################################################
# HOSTILE CUSTODY PROFILE IMPLEMENTATION
##########################################################################################

apply_hostile_custody_profile() {
    local profile_file="$1"
    
    log_warn "Applying Hostile Custody profile"
    
    # This mostly delegates to existing hostile mode logic
    # but reads configuration from the profile
    
    # Immediate screen lock
    input keyevent 26
    
    # Key eviction
    local immediate=$(parse_profile_value "$profile_file" "key_eviction" "immediate")
    if [ "$immediate" = "true" ]; then
        sh "${MODDIR}/common/key_eviction.sh" evict-all &
    fi
    
    # USB lockdown
    sh "${MODDIR}/common/usb_defense.sh" enforce
    
    # ADB neutralization
    local use_bind=$(parse_profile_value "$profile_file" "adb" "use_bind_mounts")
    if [ "$use_bind" = "true" ]; then
        sh "${MODDIR}/common/adb_neutralizer.sh" neutralize
    else
        # Lighter ADB blocking without bind mounts
        pkill -9 -x "adbd" 2>/dev/null
        settings put global adb_enabled 0 2>/dev/null
    fi
    
    # Network isolation
    local force_airplane=$(parse_profile_value "$profile_file" "network" "force_airplane")
    if [ "$force_airplane" = "true" ]; then
        enable_airplane_mode
    fi
    
    # Biometric disable
    local bio_state=$(parse_profile_value "$profile_file" "biometrics" "state")
    if [ "$bio_state" = "disabled" ]; then
        disable_biometrics
    fi
    
    # Set state
    set_state "HOSTILE"
    set_active_profile "hostile_custody"
    
    # Haptic feedback
    local pattern=$(parse_profile_value "$profile_file" "haptic" "activate_pattern")
    if [ -n "$pattern" ]; then
        for duration in $(echo "$pattern" | tr ',' ' '); do
            cmd vibrator vibrate "$duration" 2>/dev/null
            sleep 0.1
        done
    fi
    
    # Start enforcement loop
    start_hostile_enforcement "$profile_file" &
    
    log_warn "Hostile Custody profile applied"
}

start_hostile_enforcement() {
    local profile_file="$1"
    local interval=$(parse_profile_value "$profile_file" "enforcement" "interval_ms")
    interval=${interval:-1000}
    
    # Convert ms to seconds (shell doesn't do sub-second easily)
    local sleep_time=$(echo "scale=2; $interval / 1000" | bc 2>/dev/null || echo "1")
    
    while [ "$(get_active_profile)" = "hostile_custody" ]; do
        # Re-enforce measures
        sh "${MODDIR}/common/usb_defense.sh" enforce >/dev/null 2>&1
        pkill -9 -x "adbd" 2>/dev/null
        
        # Ensure screen stays locked
        if is_screen_on && ! is_device_locked; then
            input keyevent 26
        fi
        
        sleep "$sleep_time"
    done
}

##########################################################################################
# PROFILE ACTIVATION
##########################################################################################

activate_profile() {
    local profile="$1"
    local force="${2:-false}"
    
    log_info "Activating profile: $profile"
    
    # Check if profile exists
    local profile_file=$(get_profile_path "$profile")
    if [ -z "$profile_file" ]; then
        log_error "Profile not found: $profile"
        return 1
    fi
    
    # Check for conflicting active profile
    local current=$(get_active_profile)
    if [ "$current" != "none" ] && [ "$force" != "true" ]; then
        log_warn "Profile already active: $current"
        return 1
    fi
    
    # Apply profile based on type
    case "$profile" in
        "traveler")
            apply_traveler_profile "$profile_file"
            ;;
        "hostile_custody"|"hostile")
            apply_hostile_custody_profile "$profile_file"
            ;;
        *)
            log_error "Unknown profile type: $profile"
            return 1
            ;;
    esac
    
    return 0
}

##########################################################################################
# PROFILE DEACTIVATION
##########################################################################################

deactivate_profile() {
    local current=$(get_active_profile)
    
    if [ "$current" = "none" ]; then
        log_info "No profile active"
        return 0
    fi
    
    log_info "Deactivating profile: $current"
    
    case "$current" in
        "traveler")
            deactivate_traveler
            ;;
        "hostile_custody"|"hostile")
            # Hostile requires recovery phrase
            log_error "Hostile profile requires recovery phrase"
            log_error "Use: recovery_validator.sh interactive"
            return 1
            ;;
    esac
    
    clear_active_profile
    set_state "NORMAL"
    
    log_info "Profile deactivated, returning to NORMAL"
    return 0
}

deactivate_traveler() {
    log_info "Deactivating Traveler profile"
    
    # Restore USB (but keep some security)
    safe_resetprop sys.usb.config "mtp"
    
    # ADB stays disabled until explicitly enabled
    
    # Restore notification visibility
    settings put secure lock_screen_show_notifications 1 2>/dev/null
    
    # Restore Wi-Fi notifications
    settings put global wifi_networks_available_notification_on 1 2>/dev/null
    
    # Disable airplane if it was enabled
    local airplane=$(settings get global airplane_mode_on 2>/dev/null)
    if [ "$airplane" = "1" ]; then
        disable_airplane_mode
    fi
    
    # Haptic confirmation
    cmd vibrator vibrate 200 2>/dev/null
    sleep 0.2
    cmd vibrator vibrate 200 2>/dev/null
}

##########################################################################################
# PROFILE LISTING
##########################################################################################

list_profiles() {
    echo "=== Available Profiles ==="
    echo ""
    
    # System profiles
    for conf in "${PROFILE_DIR}"/*.conf; do
        if [ -f "$conf" ]; then
            local name=$(basename "$conf" .conf)
            local display=$(parse_profile_value "$conf" "profile" "display_name")
            local desc=$(parse_profile_value "$conf" "profile" "description")
            echo "[$name]"
            echo "  Name: $display"
            echo "  Description: $desc"
            echo ""
        fi
    done
    
    # User profiles
    if [ -d "$USER_PROFILE_DIR" ]; then
        for conf in "${USER_PROFILE_DIR}"/*.conf; do
            if [ -f "$conf" ]; then
                local name=$(basename "$conf" .conf)
                local display=$(parse_profile_value "$conf" "profile" "display_name")
                echo "[$name] (user)"
                echo "  Name: $display"
                echo ""
            fi
        done
    fi
    
    echo "=== Current Status ==="
    echo "Active profile: $(get_active_profile)"
    echo "Current state: $(get_current_state)"
}

##########################################################################################
# MAIN EXECUTION
##########################################################################################

case "$1" in
    "activate")
        if [ -z "$2" ]; then
            echo "Usage: $0 activate <profile_name>"
            echo "Available: traveler, hostile_custody"
            exit 1
        fi
        activate_profile "$2" "$3"
        ;;
    "deactivate")
        deactivate_profile
        ;;
    "list")
        list_profiles
        ;;
    "status")
        echo "Active profile: $(get_active_profile)"
        echo "Current state: $(get_current_state)"
        ;;
    "get")
        # Get specific profile value
        if [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
            echo "Usage: $0 get <profile> <section> <key>"
            exit 1
        fi
        profile_file=$(get_profile_path "$2")
        if [ -n "$profile_file" ]; then
            parse_profile_value "$profile_file" "$3" "$4"
        fi
        ;;
    *)
        echo "Custos Profile Manager"
        echo ""
        echo "Usage: $0 <command> [args]"
        echo ""
        echo "Commands:"
        echo "  activate <profile>     Activate a security profile"
        echo "  deactivate             Deactivate current profile"
        echo "  list                   List available profiles"
        echo "  status                 Show current status"
        echo "  get <p> <s> <k>        Get profile config value"
        echo ""
        echo "Profiles:"
        echo "  traveler               Preemptive travel security"
        echo "  hostile_custody        Maximum defense for threats"
        exit 1
        ;;
esac

