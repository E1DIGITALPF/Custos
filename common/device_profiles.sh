#!/system/bin/sh
##########################################################################################
#
# Custos Anti-Forensic Defense Module
# Device Profile Manager
#
# Detects device manufacturer and applies device-specific optimizations
# to reduce false positives and enhance defensive capabilities.
#
##########################################################################################

MODDIR="${0%/*}/.."
. "${MODDIR}/common/functions.sh"

# Device profile directories
DEVICE_PROFILE_DIR="${MODDIR}/config/devices"
ACTIVE_DEVICE_PROFILE="${DATA_DIR}/.device_profile"

##########################################################################################
# DEVICE DETECTION
##########################################################################################

detect_manufacturer() {
    local manufacturer=$(getprop ro.product.manufacturer | tr '[:upper:]' '[:lower:]')
    echo "$manufacturer"
}

detect_brand() {
    local brand=$(getprop ro.product.brand | tr '[:upper:]' '[:lower:]')
    echo "$brand"
}

detect_model() {
    local model=$(getprop ro.product.model)
    echo "$model"
}

detect_device() {
    local device=$(getprop ro.product.device)
    echo "$device"
}

detect_hardware() {
    local hardware=$(getprop ro.hardware)
    echo "$hardware"
}

get_android_version() {
    getprop ro.build.version.release
}

get_security_patch_level() {
    getprop ro.build.version.security_patch
}

##########################################################################################
# DEVICE PROFILE SELECTION
##########################################################################################

select_device_profile() {
    local manufacturer=$(detect_manufacturer)
    local brand=$(detect_brand)
    local device=$(detect_device)
    
    log_info "Detecting device: manufacturer=$manufacturer, brand=$brand, device=$device"
    
    # Check for exact device match first
    if [ -f "${DEVICE_PROFILE_DIR}/${device}.conf" ]; then
        echo "${device}"
        return 0
    fi
    
    # Check for brand match
    case "$brand" in
        "google")
            echo "google_pixel"
            ;;
        "samsung")
            echo "samsung"
            ;;
        "xiaomi"|"redmi"|"poco")
            echo "xiaomi"
            ;;
        "oneplus")
            echo "oneplus"
            ;;
        "huawei"|"honor")
            echo "huawei"
            ;;
        "oppo"|"realme")
            echo "oppo"
            ;;
        "vivo"|"iqoo")
            echo "vivo"
            ;;
        "motorola"|"lenovo")
            echo "motorola"
            ;;
        "nokia")
            echo "nokia"
            ;;
        "sony")
            echo "sony"
            ;;
        "lg")
            echo "lg"
            ;;
        "asus")
            echo "asus"
            ;;
        *)
            # Fallback to manufacturer
            case "$manufacturer" in
                "google")
                    echo "google_pixel"
                    ;;
                "samsung")
                    echo "samsung"
                    ;;
                *)
                    echo "generic"
                    ;;
            esac
            ;;
    esac
}

##########################################################################################
# PROFILE LOADING
##########################################################################################

get_device_profile_path() {
    local profile_name="$1"
    local profile_path="${DEVICE_PROFILE_DIR}/${profile_name}.conf"
    
    if [ -f "$profile_path" ]; then
        echo "$profile_path"
    else
        echo "${DEVICE_PROFILE_DIR}/generic.conf"
    fi
}

load_device_profile() {
    local profile_name=$(select_device_profile)
    local profile_path=$(get_device_profile_path "$profile_name")
    
    if [ -f "$profile_path" ]; then
        log_info "Loading device profile: $profile_name"
        echo "$profile_name" > "$ACTIVE_DEVICE_PROFILE"
        chmod 600 "$ACTIVE_DEVICE_PROFILE"
        return 0
    else
        log_warn "Device profile not found, using generic"
        echo "generic" > "$ACTIVE_DEVICE_PROFILE"
        return 1
    fi
}

get_active_device_profile() {
    if [ -f "$ACTIVE_DEVICE_PROFILE" ]; then
        cat "$ACTIVE_DEVICE_PROFILE"
    else
        select_device_profile
    fi
}

##########################################################################################
# DEVICE-SPECIFIC VALUE RETRIEVAL
##########################################################################################

# Get device-specific configuration value
# Falls back to generic if not defined for current device
get_device_value() {
    local section="$1"
    local key="$2"
    local default="$3"
    
    local profile=$(get_active_device_profile)
    local profile_path=$(get_device_profile_path "$profile")
    
    if [ ! -f "$profile_path" ]; then
        echo "$default"
        return
    fi
    
    # Parse INI value
    local value=$(awk -F= -v section="[$section]" -v key="$key" '
        $0 == section { in_section=1; next }
        /^\[/ { in_section=0 }
        in_section && $1 == key { print $2; exit }
    ' "$profile_path" | tr -d ' ')
    
    if [ -n "$value" ]; then
        echo "$value"
    else
        echo "$default"
    fi
}

##########################################################################################
# DEVICE CAPABILITY DETECTION
##########################################################################################

has_titan_m() {
    # Google Pixel 3+ has Titan M security chip
    local device=$(detect_device)
    case "$device" in
        "blueline"|"crosshatch"|"flame"|"coral"|"sunfish"|"bramble"|"redfin"|"oriole"|"raven"|"bluejay"|"panther"|"cheetah"|"lynx"|"tangorpro"|"felix"|"husky"|"shiba"|"akita"|"tokay"|"caiman"|"komodo")
            return 0
            ;;
    esac
    return 1
}

has_knox() {
    # Samsung Knox
    if [ -f "/system/framework/knoxsdk.jar" ] || [ -d "/data/knox" ]; then
        return 0
    fi
    return 1
}

has_trustzone() {
    # Qualcomm TrustZone
    if [ -d "/dev/qseecom" ] || [ -c "/dev/qseecom" ]; then
        return 0
    fi
    return 1
}

has_verified_boot() {
    local vbstate=$(getprop ro.boot.verifiedbootstate)
    [ -n "$vbstate" ]
}

get_verified_boot_state() {
    getprop ro.boot.verifiedbootstate
}

is_bootloader_locked() {
    local state=$(get_verified_boot_state)
    [ "$state" = "green" ]
}

##########################################################################################
# DEVICE-SPECIFIC BEHAVIOR ADJUSTMENTS
##########################################################################################

apply_device_adjustments() {
    local profile=$(get_active_device_profile)
    
    log_info "Applying device-specific adjustments for: $profile"
    
    case "$profile" in
        "google_pixel")
            apply_pixel_adjustments
            ;;
        "samsung")
            apply_samsung_adjustments
            ;;
        "xiaomi")
            apply_xiaomi_adjustments
            ;;
        "oneplus")
            apply_oneplus_adjustments
            ;;
        *)
            apply_generic_adjustments
            ;;
    esac
}

apply_pixel_adjustments() {
    log_debug "Applying Pixel-specific adjustments"
    
    # Pixels have strong Verified Boot - can trust weak signals more
    # Titan M makes key eviction more effective
    
    if has_titan_m; then
        log_info "Titan M detected - enhanced key eviction available"
    fi
}

apply_samsung_adjustments() {
    log_debug "Applying Samsung-specific adjustments"
    
    # Samsung uses Download Mode instead of EDL
    # Knox provides additional security layer
    # Be careful with boot anomaly detection - Knox can cause false positives
    
    if has_knox; then
        log_info "Knox detected - adjusting boot anomaly thresholds"
    fi
}

apply_xiaomi_adjustments() {
    log_debug "Applying Xiaomi-specific adjustments"
    
    # Xiaomi devices often have unlocked bootloaders
    # EDL mode is more accessible
    # More conservative thresholds needed
}

apply_oneplus_adjustments() {
    log_debug "Applying OnePlus-specific adjustments"
    
    # OnePlus devices are often unlocked for custom ROMs
    # Similar concerns to Xiaomi
}

apply_generic_adjustments() {
    log_debug "Applying generic device adjustments"
    
    # Conservative defaults
}

##########################################################################################
# MAIN EXECUTION
##########################################################################################

case "$1" in
    "detect")
        echo "=== Device Detection ==="
        echo "Manufacturer: $(detect_manufacturer)"
        echo "Brand: $(detect_brand)"
        echo "Model: $(detect_model)"
        echo "Device: $(detect_device)"
        echo "Hardware: $(detect_hardware)"
        echo "Android: $(get_android_version)"
        echo "Security patch: $(get_security_patch_level)"
        echo ""
        echo "Selected profile: $(select_device_profile)"
        ;;
    "load")
        load_device_profile
        ;;
    "apply")
        apply_device_adjustments
        ;;
    "capabilities")
        echo "=== Device Capabilities ==="
        echo "Titan M: $(has_titan_m && echo 'YES' || echo 'NO')"
        echo "Knox: $(has_knox && echo 'YES' || echo 'NO')"
        echo "TrustZone: $(has_trustzone && echo 'YES' || echo 'NO')"
        echo "Verified Boot: $(has_verified_boot && echo 'YES' || echo 'NO')"
        echo "VB State: $(get_verified_boot_state)"
        echo "Bootloader Locked: $(is_bootloader_locked && echo 'YES' || echo 'NO')"
        ;;
    "get")
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "Usage: $0 get <section> <key> [default]"
            exit 1
        fi
        get_device_value "$2" "$3" "$4"
        ;;
    "status")
        echo "Active device profile: $(get_active_device_profile)"
        echo "Profile path: $(get_device_profile_path "$(get_active_device_profile)")"
        ;;
    *)
        echo "Custos Device Profile Manager"
        echo ""
        echo "Usage: $0 <command>"
        echo ""
        echo "Commands:"
        echo "  detect       Detect device and select profile"
        echo "  load         Load device profile"
        echo "  apply        Apply device-specific adjustments"
        echo "  capabilities Show device security capabilities"
        echo "  get <s> <k>  Get device config value"
        echo "  status       Show active profile"
        exit 1
        ;;
esac

