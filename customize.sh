#!/system/bin/sh
##########################################################################################
#
# Custos Anti-Forensic Defense Module
# Installation Script
#
##########################################################################################

SKIPUNZIP=1

# Print module banner
ui_print "╔══════════════════════════════════════════════════════════════╗"
ui_print "║              CUSTOS ANTI-FORENSIC DEFENSE                    ║"
ui_print "║                     v1.0.0                                   ║"
ui_print "╠══════════════════════════════════════════════════════════════╣"
ui_print "║  Neutralizes: Cellebrite UFED, Oxygen Forensic, MOBILedit   ║"
ui_print "╚══════════════════════════════════════════════════════════════╝"
ui_print ""

# Check Android version (minimum Android 8.0 for FBE support)
API=$(getprop ro.build.version.sdk)
if [ "$API" -lt 26 ]; then
    ui_print "! Android 8.0+ required (API 26+)"
    ui_print "! Current API level: $API"
    abort "! Installation aborted"
fi

ui_print "- Android API level: $API ✓"

# Check for ARM64 architecture
ARCH=$(getprop ro.product.cpu.abi)
if [ "$ARCH" != "arm64-v8a" ]; then
    ui_print "! Warning: Module optimized for arm64-v8a"
    ui_print "! Current architecture: $ARCH"
fi

ui_print "- Architecture: $ARCH"

# Check Magisk version
MAGISK_VER=$(magisk -v 2>/dev/null | cut -d':' -f1)
MAGISK_VER_CODE=$(magisk -V 2>/dev/null)

if [ -z "$MAGISK_VER_CODE" ] || [ "$MAGISK_VER_CODE" -lt 20400 ]; then
    ui_print "! Magisk 20.4+ required for sepolicy patches"
    abort "! Installation aborted"
fi

ui_print "- Magisk version: $MAGISK_VER ($MAGISK_VER_CODE) ✓"

# Extract module files
ui_print "- Extracting module files..."
unzip -o "$ZIPFILE" -x 'META-INF/*' -d "$MODPATH" >&2

# Create required directories
ui_print "- Creating directory structure..."
mkdir -p "$MODPATH/system/bin"
mkdir -p "$MODPATH/common"
mkdir -p "$MODPATH/config"
mkdir -p "/data/adb/custos"

# Set permissions
ui_print "- Setting permissions..."
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm_recursive "$MODPATH/common" 0 0 0755 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755

# Set permissions for common scripts
for script in "$MODPATH/common"/*.sh; do
    [ -f "$script" ] && set_perm "$script" 0 0 0755
done

# Initialize state database
ui_print "- Initializing state database..."
echo "NORMAL:$(date +%s)" > "/data/adb/custos/state.db"
chmod 600 "/data/adb/custos/state.db"

# Generate initial boot hash (will be updated on first clean boot)
ui_print "- Recording boot partition hash..."
if [ -e "/dev/block/by-name/boot" ]; then
    sha256sum /dev/block/by-name/boot 2>/dev/null | cut -d' ' -f1 > "$MODPATH/config/boot_hash.txt"
elif [ -e "/dev/block/bootdevice/by-name/boot" ]; then
    sha256sum /dev/block/bootdevice/by-name/boot 2>/dev/null | cut -d' ' -f1 > "$MODPATH/config/boot_hash.txt"
else
    ui_print "! Warning: Could not locate boot partition"
    echo "UNKNOWN" > "$MODPATH/config/boot_hash.txt"
fi

# Setup recovery phrase if not exists
if [ ! -f "/data/adb/custos/recovery_phrase.enc" ]; then
    ui_print ""
    ui_print "╔══════════════════════════════════════════════════════════════╗"
    ui_print "║                  RECOVERY PHRASE SETUP                       ║"
    ui_print "╠══════════════════════════════════════════════════════════════╣"
    ui_print "║  Default recovery phrase: 'custos_recovery_2025'             ║"
    ui_print "║  CHANGE THIS via the companion app or terminal command:      ║"
    ui_print "║  su -c 'custos_set_phrase <your_secret_phrase>'              ║"
    ui_print "╚══════════════════════════════════════════════════════════════╝"
    
    # Set default phrase (SHA-512 hash)
    echo -n "custos_recovery_2025" | sha512sum | cut -d' ' -f1 > "/data/adb/custos/recovery_phrase.enc"
    chmod 600 "/data/adb/custos/recovery_phrase.enc"
fi

# Copy default trigger configuration
ui_print "- Installing trigger configuration..."
cp "$MODPATH/config/triggers.conf" "/data/adb/custos/triggers.conf" 2>/dev/null
chmod 600 "/data/adb/custos/triggers.conf"

# Verify SELinux policy rules
if [ -f "$MODPATH/sepolicy.rule" ]; then
    ui_print "- SELinux policy rules installed ✓"
else
    ui_print "! Warning: SELinux policy file missing"
fi

# Final verification
ui_print ""
ui_print "- Verifying installation..."

INSTALL_OK=true

[ ! -f "$MODPATH/service.sh" ] && INSTALL_OK=false && ui_print "! Missing: service.sh"
[ ! -f "$MODPATH/post-fs-data.sh" ] && INSTALL_OK=false && ui_print "! Missing: post-fs-data.sh"
[ ! -f "$MODPATH/common/usb_defense.sh" ] && INSTALL_OK=false && ui_print "! Missing: usb_defense.sh"
[ ! -f "$MODPATH/common/adb_neutralizer.sh" ] && INSTALL_OK=false && ui_print "! Missing: adb_neutralizer.sh"
[ ! -f "$MODPATH/common/hostile_mode.sh" ] && INSTALL_OK=false && ui_print "! Missing: hostile_mode.sh"

if [ "$INSTALL_OK" = true ]; then
    ui_print ""
    ui_print "╔══════════════════════════════════════════════════════════════╗"
    ui_print "║              INSTALLATION SUCCESSFUL                         ║"
    ui_print "╠══════════════════════════════════════════════════════════════╣"
    ui_print "║  Module will activate on next reboot.                        ║"
    ui_print "║                                                              ║"
    ui_print "║  HOSTILE MODE TRIGGERS:                                      ║"
    ui_print "║  • Volume Down x5 in 3 seconds                               ║"
    ui_print "║  • SIM card removal                                          ║"
    ui_print "║  • 5 failed unlock attempts                                  ║"
    ui_print "║  • Abnormal boot detected                                    ║"
    ui_print "║                                                              ║"
    ui_print "║  REMEMBER YOUR RECOVERY PHRASE!                              ║"
    ui_print "╚══════════════════════════════════════════════════════════════╝"
else
    abort "! Installation verification failed"
fi

