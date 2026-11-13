#!/system/bin/sh
# Magisk's Action button. Opens onn's sound menu on the TV and prints what's
# currently going on. Doesn't change anything.
MODDIR=${0%/*}
. "$MODDIR/common/compat.sh"

yes_no() { if "$@"; then echo yes; else echo no; fi; }

/system/bin/am start -n "$SOUND_ACTIVITY" >/dev/null 2>&1 &&
	echo "Opened onn's sound menu on the TV." && echo

echo "onn 4K Pro TrueHD/Atmos Passthrough"
echo
if compat_check; then echo "Firmware:          supported"; else echo "Firmware:          $COMPAT_REASON"; fi
echo "192 kHz helper:    $(yes_no grep -q '^t9015rate ' /proc/modules)"
echo "TrueHD switch:     $(getprop $TRUEHD_PROP)"
echo "Force DD+:         $(getprop $FORCEDDP_PROP)"
echo "TrueHD in formats: $(yes_no surround_has_truehd $POLICY)"
echo "Hidden options:    $(yes_no grep -q Passthrough_Audio_Config $AML_CONFIG)"
echo "Settings row:      $(/system/bin/cmd overlay list "$OVERLAY_PKG" 2>/dev/null | grep -q '\[x\]' && echo yes || echo no)"
echo "Audio output mode: $(mode_name "$(digital_mode_get)") (HAL: $(hal_mode))"
echo "HDMI offers:       $(/system/bin/dumpsys audio | grep -m1 'type:hdmi' | grep -oE 'ENCODING_(DOLBY_TRUEHD|DOLBY_MAT|E_AC3_JOC)' | sort -u | tr '\n' ' ')"
echo
echo "Last log lines:"
tail -n 8 /data/adb/onn_truehd/apply.log 2>/dev/null
