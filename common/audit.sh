#!/system/bin/sh
##########################################################################################
#
# Custos Anti-Forensic Defense Module
# Self-Audit Script
#
# Verifies that all defensive components are properly installed and functioning
#
##########################################################################################

MODDIR="${0%/*}/.."
. "${MODDIR}/common/functions.sh"

# Audit result tracking
AUDIT_PASSED=0
AUDIT_WARNINGS=0
AUDIT_FAILURES=0

##########################################################################################
# OUTPUT HELPERS
##########################################################################################

print_header() {
    echo "=============================================="
    echo "$1"
    echo "=============================================="
    echo ""
}

print_section() {
    echo ""
    echo "--- $1 ---"
}

print_ok() {
    echo "[OK] $1"
    AUDIT_PASSED=$((AUDIT_PASSED + 1))
}

print_warn() {
    echo "[WARN] $1"
    AUDIT_WARNINGS=$((AUDIT_WARNINGS + 1))
}

print_fail() {
    echo "[FAIL] $1"
    AUDIT_FAILURES=$((AUDIT_FAILURES + 1))
}

print_skip() {
    echo "[SKIP] $1"
}

print_info() {
    echo "[INFO] $1"
}

##########################################################################################
# AUDIT CHECKS
##########################################################################################

check_module_installed() {
    print_section "Module Installation"
    
    # Check module directory
    if [ -d "$MODDIR" ]; then
        print_ok "Module directory exists"
    else
        print_fail "Module directory not found: $MODDIR"
        return 1
    fi
    
    # Check critical files
    local critical_files=(
        "module.prop"
        "service.sh"
        "post-fs-data.sh"
        "common/functions.sh"
        "common/usb_defense.sh"
        "common/adb_neutralizer.sh"
        "common/hostile_mode.sh"
        "common/key_eviction.sh"
        "common/recovery_validator.sh"
    )
    
    for file in "${critical_files[@]}"; do
        if [ -f "${MODDIR}/${file}" ]; then
            print_ok "Found: $file"
        else
            print_fail "Missing: $file"
        fi
    done
    
    # Check data directory
    if [ -d "$DATA_DIR" ]; then
        print_ok "Data directory exists"
    else
        print_warn "Data directory missing - may need reboot"
    fi
}

check_services_running() {
    print_section "Service Status"
    
    # Check for USB defense monitor
    if pgrep -f "usb_defense.sh" >/dev/null 2>&1; then
        print_ok "USB defense monitor running"
    else
        print_fail "USB defense monitor NOT running"
    fi
    
    # Check for ADB neutralizer
    if pgrep -f "adb_neutralizer.sh" >/dev/null 2>&1; then
        print_ok "ADB neutralizer running"
    else
        print_warn "ADB neutralizer not running (may be okay in NORMAL mode)"
    fi
    
    # Check for hostile mode monitor
    if pgrep -f "hostile_mode.sh" >/dev/null 2>&1; then
        print_ok "Hostile mode monitor running"
    else
        print_warn "Hostile mode monitor not running"
    fi
}

check_current_state() {
    print_section "State Machine"
    
    local state=$(get_current_state)
    print_info "Current state: $state"
    
    case "$state" in
        "NORMAL")
            print_ok "State is NORMAL - baseline monitoring active"
            ;;
        "TRAVELER")
            print_ok "State is TRAVELER - preemptive protection active"
            ;;
        "ALERT")
            print_warn "State is ALERT - suspicious activity detected"
            ;;
        "HOSTILE")
            print_warn "State is HOSTILE - maximum protection active"
            ;;
        "LOCKDOWN")
            print_fail "State is LOCKDOWN - permanent lockdown"
            ;;
        *)
            print_warn "State is UNKNOWN - may need initialization"
            ;;
    esac
    
    # Check state timestamp
    local ts=$(get_state_timestamp)
    if [ -n "$ts" ] && [ "$ts" != "0" ]; then
        print_info "State since: $(date -d @$ts 2>/dev/null || echo $ts)"
    fi
}

check_usb_defense() {
    print_section "USB Defense"
    
    # Check USB configuration
    local usb_config=$(getprop sys.usb.config)
    print_info "USB config: $usb_config"
    
    if echo "$usb_config" | grep -qi "charging"; then
        print_ok "USB set to charging mode"
    elif echo "$usb_config" | grep -qi "adb"; then
        print_warn "USB config contains 'adb' - may be accessible"
    elif echo "$usb_config" | grep -qi "mtp"; then
        print_warn "USB config contains 'mtp' - file transfer may be possible"
    else
        print_info "USB config: $usb_config"
    fi
    
    # Check USB gadget state
    if [ -f "/sys/class/android_usb/android0/functions" ]; then
        local funcs=$(cat /sys/class/android_usb/android0/functions 2>/dev/null)
        if [ -z "$funcs" ]; then
            print_ok "USB gadget functions empty (locked)"
        else
            print_info "USB gadget functions: $funcs"
        fi
    fi
    
    # Check ADB enabled
    local adb_enabled=$(settings get global adb_enabled 2>/dev/null)
    if [ "$adb_enabled" = "0" ]; then
        print_ok "ADB disabled in settings"
    elif [ "$adb_enabled" = "1" ]; then
        print_warn "ADB enabled in settings"
    fi
    
    # Check development settings
    local dev_enabled=$(settings get global development_settings_enabled 2>/dev/null)
    if [ "$dev_enabled" = "0" ]; then
        print_ok "Development settings disabled"
    elif [ "$dev_enabled" = "1" ]; then
        print_info "Development settings enabled"
    fi
}

check_adb_status() {
    print_section "ADB Status"
    
    # Check if adbd is running
    if pgrep -x "adbd" >/dev/null 2>&1; then
        print_warn "adbd process is running"
    else
        print_ok "adbd process NOT running"
    fi
    
    # Check ADB socket
    if [ -S "/dev/socket/adbd" ]; then
        print_warn "ADB socket exists"
    else
        print_ok "ADB socket does not exist"
    fi
    
    # Check debuggable property
    local debuggable=$(getprop ro.debuggable)
    if [ "$debuggable" = "0" ]; then
        print_ok "Device not debuggable"
    else
        print_info "ro.debuggable = $debuggable"
    fi
    
    # Check ADB TCP port
    local tcp_port=$(getprop service.adb.tcp.port)
    if [ -z "$tcp_port" ] || [ "$tcp_port" = "0" ]; then
        print_ok "ADB TCP port not set"
    else
        print_warn "ADB TCP port set: $tcp_port"
    fi
}

check_recovery_system() {
    print_section "Recovery System"
    
    # Check recovery phrase
    if [ -f "${DATA_DIR}/recovery_phrase.enc" ]; then
        print_ok "Recovery phrase configured"
    else
        print_fail "Recovery phrase NOT configured"
    fi
    
    # Check failsafe timer
    local failsafe_hours=$(grep "^failsafe_hours:" "${DATA_DIR}/triggers.conf" 2>/dev/null | cut -d':' -f2)
    if [ -n "$failsafe_hours" ] && [ "$failsafe_hours" != "0" ]; then
        print_ok "Failsafe timer: ${failsafe_hours}h"
    else
        print_warn "Failsafe timer disabled"
    fi
    
    # Check recovery attempts
    local attempts=$(cat "${DATA_DIR}/.recovery_failures" 2>/dev/null || echo "0")
    if [ "$attempts" = "0" ]; then
        print_ok "No failed recovery attempts"
    else
        print_info "Failed recovery attempts: $attempts"
    fi
    
    # Check lockout status
    if [ -f "${DATA_DIR}/.recovery_lockout" ]; then
        print_warn "Recovery currently locked out"
    else
        print_ok "Recovery not locked out"
    fi
}

check_trigger_config() {
    print_section "Trigger Configuration"
    
    local config_file="${DATA_DIR}/triggers.conf"
    
    if [ ! -f "$config_file" ]; then
        config_file="${MODDIR}/config/triggers.conf"
    fi
    
    if [ -f "$config_file" ]; then
        print_ok "Trigger configuration found"
        
        # Check key triggers
        if grep -q "^volume_down:.*:enabled" "$config_file" 2>/dev/null; then
            print_ok "Volume panic trigger enabled"
        else
            print_warn "Volume panic trigger not enabled"
        fi
        
        if grep -q "^lockscreen_fail:.*:enabled" "$config_file" 2>/dev/null; then
            print_ok "Lockscreen fail trigger enabled"
        else
            print_warn "Lockscreen fail trigger not enabled"
        fi
        
        if grep -q "^sim_removed" "$config_file" 2>/dev/null; then
            print_ok "SIM removal trigger configured"
        else
            print_info "SIM removal trigger not configured"
        fi
    else
        print_fail "Trigger configuration not found"
    fi
}

check_device_profile() {
    print_section "Device Profile"
    
    local profile=$(cat "${DATA_DIR}/.device_profile" 2>/dev/null)
    
    if [ -n "$profile" ]; then
        print_ok "Device profile loaded: $profile"
    else
        # Try to detect
        local brand=$(getprop ro.product.brand | tr '[:upper:]' '[:lower:]')
        print_info "Detected brand: $brand"
        
        if [ -f "${MODDIR}/config/devices/${brand}.conf" ]; then
            print_ok "Device profile available: $brand"
        elif [ -f "${MODDIR}/config/devices/generic.conf" ]; then
            print_info "Using generic profile"
        else
            print_warn "No device profile found"
        fi
    fi
}

check_selinux() {
    print_section "SELinux Status"
    
    local enforce=$(getenforce 2>/dev/null)
    
    case "$enforce" in
        "Enforcing")
            print_ok "SELinux is Enforcing"
            ;;
        "Permissive")
            print_warn "SELinux is Permissive"
            ;;
        *)
            print_info "SELinux status: $enforce"
            ;;
    esac
    
    # Check if sepolicy.rule exists
    if [ -f "${MODDIR}/sepolicy.rule" ]; then
        print_ok "SELinux policy rules installed"
    else
        print_warn "SELinux policy rules not found"
    fi
}

check_logs() {
    print_section "Recent Activity"
    
    # Check for recent hostile activations
    if [ -f "${DATA_DIR}/hostile_activations.log" ]; then
        local count=$(wc -l < "${DATA_DIR}/hostile_activations.log" 2>/dev/null)
        print_info "Total hostile activations: $count"
        
        local recent=$(tail -1 "${DATA_DIR}/hostile_activations.log" 2>/dev/null)
        if [ -n "$recent" ]; then
            print_info "Last activation: $recent"
        fi
    else
        print_info "No hostile activation history"
    fi
    
    # Check for errors in logcat
    local errors=$(logcat -d -s CUSTOS 2>/dev/null | grep -c "E/")
    if [ "$errors" = "0" ]; then
        print_ok "No errors in recent logs"
    else
        print_warn "Found $errors errors in logs"
    fi
}

##########################################################################################
# USB TEST
##########################################################################################

test_usb() {
    print_header "USB Defense Test"
    
    echo "This test verifies USB is in charge-only mode."
    echo ""
    echo "Please connect your device to a computer and observe:"
    echo ""
    echo "Expected behavior:"
    echo "  - Computer should show 'Charging' or nothing"
    echo "  - No file browser should open"
    echo "  - 'adb devices' should not list this device"
    echo ""
    
    # Show current USB state
    echo "Current USB state:"
    echo "  sys.usb.config: $(getprop sys.usb.config)"
    echo "  sys.usb.state: $(getprop sys.usb.state)"
    
    if [ -f "/sys/class/android_usb/android0/functions" ]; then
        echo "  gadget functions: $(cat /sys/class/android_usb/android0/functions 2>/dev/null || echo 'N/A')"
    fi
    
    if [ -f "/sys/class/android_usb/android0/enable" ]; then
        echo "  gadget enable: $(cat /sys/class/android_usb/android0/enable 2>/dev/null || echo 'N/A')"
    fi
    
    echo ""
    echo "If USB data is accessible, run:"
    echo "  su -c 'sh ${MODDIR}/common/usb_defense.sh enforce'"
}

##########################################################################################
# TRIGGER TEST
##########################################################################################

test_triggers() {
    print_header "Trigger Test"
    
    echo "WARNING: This test will activate HOSTILE mode!"
    echo ""
    echo "Make sure you know your recovery phrase before proceeding."
    echo ""
    echo "The test will:"
    echo "  1. Activate HOSTILE mode"
    echo "  2. Verify protection is active"
    echo "  3. You will need to recover manually"
    echo ""
    echo "Press Ctrl+C to cancel, or wait 5 seconds to continue..."
    
    sleep 5
    
    echo ""
    echo "Activating HOSTILE mode..."
    
    sh "${MODDIR}/common/hostile_mode.sh" activate "audit_test"
    
    echo ""
    echo "HOSTILE mode should now be active."
    echo ""
    echo "To recover, run:"
    echo "  su -c 'sh ${MODDIR}/common/recovery_validator.sh interactive'"
}

##########################################################################################
# REPORT GENERATION
##########################################################################################

generate_report() {
    print_header "Custos Audit Report"
    
    echo "Generated: $(date)"
    echo "Device: $(getprop ro.product.model)"
    echo "Android: $(getprop ro.build.version.release)"
    echo "Security Patch: $(getprop ro.build.version.security_patch)"
    echo ""
    
    # Run all checks
    check_module_installed
    check_services_running
    check_current_state
    check_usb_defense
    check_adb_status
    check_recovery_system
    check_trigger_config
    check_device_profile
    check_selinux
    check_logs
    
    # Summary
    echo ""
    print_header "Audit Summary"
    
    echo "Passed:   $AUDIT_PASSED"
    echo "Warnings: $AUDIT_WARNINGS"
    echo "Failures: $AUDIT_FAILURES"
    echo ""
    
    if [ $AUDIT_FAILURES -gt 0 ]; then
        echo "RESULT: FAILED - Critical issues found"
        return 2
    elif [ $AUDIT_WARNINGS -gt 0 ]; then
        echo "RESULT: PASSED WITH WARNINGS - Review recommended"
        return 1
    else
        echo "RESULT: PASSED - All checks successful"
        return 0
    fi
}

##########################################################################################
# QUICK CHECK
##########################################################################################

quick_check() {
    echo "=== Custos Quick Health Check ==="
    
    # Module installed
    if [ -d "$MODDIR" ] && [ -f "${MODDIR}/module.prop" ]; then
        print_ok "Module installed and active"
    else
        print_fail "Module not properly installed"
    fi
    
    # Current state
    local state=$(get_current_state)
    print_ok "Current state: $state"
    
    # USB monitor
    if pgrep -f "usb_defense.sh" >/dev/null 2>&1; then
        print_ok "USB defense monitor running"
    else
        print_fail "USB defense monitor NOT running"
    fi
    
    # ADB neutralizer check (just verify it can run)
    if [ -f "${MODDIR}/common/adb_neutralizer.sh" ]; then
        print_ok "ADB neutralizer ready"
    else
        print_fail "ADB neutralizer missing"
    fi
    
    # Recovery phrase
    if [ -f "${DATA_DIR}/recovery_phrase.enc" ]; then
        print_ok "Recovery phrase configured"
    else
        print_fail "Recovery phrase NOT configured"
    fi
    
    # Failsafe
    local failsafe=$(grep "^failsafe_hours:" "${DATA_DIR}/triggers.conf" 2>/dev/null | cut -d':' -f2)
    failsafe=${failsafe:-72}
    print_ok "Failsafe timer: ${failsafe}h"
    
    # Device profile
    local profile=$(cat "${DATA_DIR}/.device_profile" 2>/dev/null || echo "auto-detect")
    print_ok "Device profile: $profile"
    
    echo "=== Health Check: $([ $AUDIT_FAILURES -eq 0 ] && echo 'PASSED' || echo 'FAILED') ==="
}

##########################################################################################
# MAIN EXECUTION
##########################################################################################

case "$1" in
    "quick")
        quick_check
        ;;
    "full")
        generate_report
        ;;
    "usb")
        test_usb
        ;;
    "triggers")
        test_triggers
        ;;
    "report")
        generate_report
        ;;
    "module")
        check_module_installed
        ;;
    "services")
        check_services_running
        ;;
    "state")
        check_current_state
        ;;
    *)
        echo "Custos Self-Audit Tool"
        echo ""
        echo "Usage: $0 <command>"
        echo ""
        echo "Commands:"
        echo "  quick      Quick health check (30 seconds)"
        echo "  full       Complete audit (2-3 minutes)"
        echo "  report     Generate detailed report"
        echo "  usb        USB defense verification"
        echo "  triggers   Test triggers (WARNING: activates HOSTILE)"
        echo ""
        echo "Specific checks:"
        echo "  module     Check module installation"
        echo "  services   Check running services"
        echo "  state      Check state machine"
        ;;
esac

