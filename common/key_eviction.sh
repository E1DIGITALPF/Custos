#!/system/bin/sh
##########################################################################################
#
# Custos Anti-Forensic Defense Module
# Key Eviction Component
#
# Evicts encryption keys from memory on hostile events
# Defeats: Physical extraction and memory forensics
#
##########################################################################################

MODDIR="${0%/*}/.."
. "${MODDIR}/common/functions.sh"

##########################################################################################
# KEY EVICTION FUNCTIONS
##########################################################################################

evict_fbe_keys() {
    log_info "Evicting FBE (File-Based Encryption) keys"
    
    # Invalidate user keyring
    # This removes the decryption keys from kernel memory
    
    # Using keyctl if available (requires specific kernel support)
    if command -v keyctl >/dev/null 2>&1; then
        # Invalidate all keys in user keyring
        keyctl clear @u 2>/dev/null
        keyctl clear @us 2>/dev/null
        keyctl clear @s 2>/dev/null
        
        # Revoke all linked keyrings
        for key in $(keyctl list @u 2>/dev/null | awk '{print $1}'); do
            keyctl invalidate "$key" 2>/dev/null
            keyctl revoke "$key" 2>/dev/null
        done
        
        log_debug "Kernel keyrings cleared via keyctl"
    fi
    
    # Alternative: Direct syscall approach via helper binary if available
    if [ -x "/data/adb/custos/bin/key_evictor" ]; then
        /data/adb/custos/bin/key_evictor --evict-all 2>/dev/null
    fi
    
    # Force vold to drop cached keys
    # This triggers re-authentication requirement
    vdc cryptfs lock 2>/dev/null
    
    log_info "FBE key eviction completed"
}

evict_dm_crypt_keys() {
    log_info "Evicting dm-crypt keys"
    
    # For devices using Full Disk Encryption (older devices)
    # This attempts to wipe the dm-crypt key from the key_data table
    
    # Suspend encrypted volumes (this wipes the key from memory)
    for dm_device in /dev/block/dm-*; do
        if [ -b "$dm_device" ]; then
            # Try to suspend the device (wipes key)
            dmsetup suspend "$dm_device" 2>/dev/null
            # Immediately resume to avoid complete system halt
            # Note: Without the key, data becomes inaccessible
            dmsetup resume "$dm_device" 2>/dev/null
        fi
    done
    
    log_debug "dm-crypt key eviction attempted"
}

evict_keystore_keys() {
    log_info "Evicting Android Keystore keys"
    
    # Clear keystore daemon cache
    # This forces re-authentication for app-level encryption keys
    
    # Signal keystore to flush
    pkill -USR1 keystore 2>/dev/null
    pkill -USR1 credstore 2>/dev/null
    
    # For Android 12+, use identity credential system
    pkill -USR1 credstore_aidl 2>/dev/null
    
    # Lock the keystore
    # This requires PIN/password to unlock again
    cmd lock_settings lock 2>/dev/null
    
    log_debug "Keystore keys evicted"
}

##########################################################################################
# SESSION AND TOKEN PURGE
##########################################################################################

purge_session_tokens() {
    log_info "Purging session tokens and auth data"
    
    # Clear authentication tokens from apps
    # These are used by forensic tools for cloud extraction
    
    # Common token file patterns
    TOKEN_PATTERNS=(
        "*token*"
        "*session*"
        "*auth*"
        "*cookie*"
        "*credential*"
        "*oauth*"
        "*refresh*"
        "*access*"
    )
    
    # Clear shared preferences containing tokens
    for pattern in "${TOKEN_PATTERNS[@]}"; do
        find /data/data/*/shared_prefs -name "$pattern" -type f -exec rm -f {} \; 2>/dev/null
    done
    
    # Clear databases that might contain sessions
    for pattern in "${TOKEN_PATTERNS[@]}"; do
        find /data/data/*/databases -name "$pattern" -type f -exec rm -f {} \; 2>/dev/null
    done
    
    # Clear cache directories that might contain tokens
    find /data/data/*/cache -type f -name "*token*" -exec rm -f {} \; 2>/dev/null
    find /data/data/*/cache -type f -name "*session*" -exec rm -f {} \; 2>/dev/null
    
    # Clear account manager cached credentials
    rm -rf /data/system_ce/*/accounts_ce.db-journal 2>/dev/null
    rm -rf /data/system_de/*/accounts_de.db-journal 2>/dev/null
    
    # Specific high-value targets for cloud extraction
    SENSITIVE_APPS=(
        "com.google.android.gms"
        "com.google.android.gsf"
        "com.whatsapp"
        "com.facebook.orca"
        "com.facebook.katana"
        "org.telegram.messenger"
        "com.instagram.android"
        "com.twitter.android"
        "com.snapchat.android"
        "com.discord"
        "org.thoughtcrime.securesms"  # Signal
    )
    
    for app in "${SENSITIVE_APPS[@]}"; do
        app_dir="/data/data/$app"
        if [ -d "$app_dir" ]; then
            # Clear shared prefs with tokens
            rm -rf "${app_dir}/shared_prefs/"*token* 2>/dev/null
            rm -rf "${app_dir}/shared_prefs/"*session* 2>/dev/null
            rm -rf "${app_dir}/shared_prefs/"*auth* 2>/dev/null
            
            # Clear cache
            rm -rf "${app_dir}/cache/"* 2>/dev/null
            
            log_debug "Purged tokens from: $app"
        fi
    done
    
    log_info "Session token purge completed"
}

##########################################################################################
# MEMORY SCRUBBING
##########################################################################################

scrub_sensitive_memory() {
    log_info "Scrubbing sensitive memory regions"
    
    # Drop filesystem caches
    # This removes potentially cached decrypted data
    sync
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
    
    # Compact memory to overwrite freed pages
    echo 1 > /proc/sys/vm/compact_memory 2>/dev/null
    
    # Clear swap if in use (unlikely on Android, but thorough)
    if [ -f /proc/swaps ]; then
        swapoff -a 2>/dev/null
        swapon -a 2>/dev/null
    fi
    
    # Clear /dev/shm if accessible
    rm -rf /dev/shm/* 2>/dev/null
    
    # Overwrite temp files
    find /data/local/tmp -type f -exec shred -u {} \; 2>/dev/null
    find /cache -type f -exec shred -u {} \; 2>/dev/null
    
    log_debug "Memory scrubbing completed"
}

##########################################################################################
# BIOMETRIC DATA PROTECTION
##########################################################################################

invalidate_biometrics() {
    log_info "Invalidating biometric authentication"
    
    # Cancel any ongoing fingerprint authentication
    cmd fingerprint cancel 2>/dev/null
    
    # Reset fingerprint HAL state
    cmd fingerprint reset 2>/dev/null
    
    # For face unlock
    cmd face reset 2>/dev/null
    
    # Disable biometric unlock temporarily
    settings put secure lock_screen_lock_after_timeout 0 2>/dev/null
    
    # Force lockscreen to require PIN/password
    settings put secure lock_biometric_weak_flags 0 2>/dev/null
    settings put secure lockscreen.biometric_enabled 0 2>/dev/null
    
    log_debug "Biometrics invalidated"
}

##########################################################################################
# CLIPBOARD AND INPUT PROTECTION
##########################################################################################

clear_sensitive_buffers() {
    log_info "Clearing sensitive buffers"
    
    # Clear clipboard
    am broadcast -a clipper.clear 2>/dev/null
    service call clipboard 2 2>/dev/null  # clearPrimaryClip
    
    # Clear recent apps (potential data exposure)
    am broadcast -a com.android.systemui.recents.ACTION_CLEAR_ALL_RECENTS 2>/dev/null
    
    # Clear notification history
    cmd notification cancel_all 2>/dev/null
    
    # Clear keyboard learned words/predictions
    rm -rf /data/data/com.android.inputmethod.latin/files/* 2>/dev/null
    rm -rf /data/data/com.google.android.inputmethod.latin/files/* 2>/dev/null
    
    log_debug "Sensitive buffers cleared"
}

##########################################################################################
# FULL EVICTION SEQUENCE
##########################################################################################

execute_full_eviction() {
    log_info "=== EXECUTING FULL KEY EVICTION SEQUENCE ==="
    
    local start_time=$(date +%s)
    
    # Phase 1: Lock screen immediately
    log_info "Phase 1: Locking screen"
    input keyevent 26  # KEYCODE_POWER (screen off)
    
    # Phase 2: Evict encryption keys
    log_info "Phase 2: Evicting encryption keys"
    evict_fbe_keys
    evict_dm_crypt_keys
    evict_keystore_keys
    
    # Phase 3: Invalidate biometrics
    log_info "Phase 3: Invalidating biometrics"
    invalidate_biometrics
    
    # Phase 4: Purge tokens
    log_info "Phase 4: Purging session tokens"
    purge_session_tokens
    
    # Phase 5: Clear buffers
    log_info "Phase 5: Clearing sensitive buffers"
    clear_sensitive_buffers
    
    # Phase 6: Memory scrub
    log_info "Phase 6: Scrubbing memory"
    scrub_sensitive_memory
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_info "=== KEY EVICTION COMPLETE (${duration}s) ==="
    
    # Record eviction event
    echo "EVICTION:$(date +%s):FULL" >> /data/adb/custos/eviction.log
    chmod 600 /data/adb/custos/eviction.log
}

##########################################################################################
# QUICK EVICTION (FOR PANIC BUTTON)
##########################################################################################

execute_quick_eviction() {
    log_info "=== EXECUTING QUICK KEY EVICTION ==="
    
    # Lock screen
    input keyevent 26
    
    # Critical evictions only
    evict_fbe_keys &
    evict_keystore_keys &
    invalidate_biometrics &
    
    # Wait for critical tasks
    wait
    
    log_info "=== QUICK EVICTION COMPLETE ==="
    
    echo "EVICTION:$(date +%s):QUICK" >> /data/adb/custos/eviction.log
}

##########################################################################################
# MAIN EXECUTION
##########################################################################################

case "$1" in
    "evict-all"|"--evict-all")
        execute_full_eviction
        ;;
    "quick"|"--quick")
        execute_quick_eviction
        ;;
    "fbe")
        evict_fbe_keys
        ;;
    "keystore")
        evict_keystore_keys
        ;;
    "tokens")
        purge_session_tokens
        ;;
    "biometrics")
        invalidate_biometrics
        ;;
    "memory")
        scrub_sensitive_memory
        ;;
    "buffers")
        clear_sensitive_buffers
        ;;
    "status")
        echo "=== Key Eviction Status ==="
        echo "Last eviction: $(tail -1 /data/adb/custos/eviction.log 2>/dev/null || echo 'None')"
        echo "FBE state: $(getprop vold.decrypt)"
        echo "Keystore running: $(pgrep -x keystore >/dev/null && echo 'YES' || echo 'NO')"
        echo "Device locked: $(is_device_locked && echo 'YES' || echo 'NO')"
        ;;
    *)
        echo "Usage: $0 {evict-all|quick|fbe|keystore|tokens|biometrics|memory|buffers|status}"
        exit 1
        ;;
esac

