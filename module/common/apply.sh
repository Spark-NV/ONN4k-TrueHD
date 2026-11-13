# Does the actual work. service.sh sources this once the box has finished
# booting, so nothing in here can get in the way of Android starting up.
#
# Roughly:
#   1. load t9015rate.ko so the HDMI audio link can run at 192 kHz
#   2. mount a copy of the audio policy with TrueHD added to the surround list
#   3. mount a copy of aml_audio_config.json with onn's hidden options turned on
#   4. flip the TrueHD prop on and the "always DD+" prop off
#   5. restart audio so it all takes effect, then put back the user's mode
#   6. turn on the "Audio output mode" row in Settings
#
# If anything goes wrong partway, everything done so far is put back.
# We never pick the audio mode ourselves, that's the user's call in onn's menu.

STATE=/data/adb/onn_truehd
LOG=$STATE/apply.log
PENDING=$STATE/apply.pending
GEN_POLICY=$STATE/audio_policy_configuration.xml
GEN_AML_CONFIG=$STATE/aml_audio_config.json
HELPER=$MODDIR/kernel/t9015rate.ko

mkdir -p "$STATE"
[ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 65536 ] && {
	tail -n 300 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
}

log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

set_status() {
	# "Display & Sound" would break the sed below, so escape & | and \ first
	local text
	text=$(printf '%s' "$1" | sed 's/[&|\\]/\\&/g')
	sed -i "s|^description=.*|description=$text|" "$MODDIR/module.prop"
	log "status: $1"
}

audio_restart() {
	/system/bin/stop vendor.audio-hal
	/system/bin/stop audioserver
	/system/bin/start vendor.audio-hal
	/system/bin/start audioserver
	local i=0
	while [ $i -lt 30 ]; do
		if [ "$(getprop init.svc.vendor.audio-hal)" = running ] &&
		   [ "$(getprop init.svc.audioserver)" = running ] &&
		   /system/bin/service check media.audio_flinger | grep -q ': found'; then
			sleep 3
			[ "$(getprop init.svc.audioserver)" = running ] && return 0
		fi
		sleep 1
		i=$((i + 1))
	done
	return 1
}

# droidaudio only reads the HAL's feature flags when it starts, so it needs
# a kick after the HAL restart too
droidaudio_restart() {
	/system/bin/stop droidaudio
	/system/bin/start droidaudio
	local i=0
	while [ $i -lt 20 ]; do
		[ -n "$(digital_mode_get)" ] && return 0
		sleep 1
		i=$((i + 1))
	done
	return 1
}

# /odm is really a symlink to /oem, and /proc/mounts has the real path
mounted() { grep -q " $(readlink -f "$1") " /proc/1/mounts; }
bind() { $BB nsenter -t 1 -m -- /system/bin/mount --bind "$1" "$2"; }
unbind() { mounted "$1" && $BB nsenter -t 1 -m -- /system/bin/umount "$1"; }

overlay_set() { /system/bin/cmd overlay "$1" --user 0 "$OVERLAY_PKG" >/dev/null 2>&1; }

rollback() {
	log "rolling back"
	unbind "$AML_CONFIG"
	unbind "$POLICY"
	resetprop --delete "$TRUEHD_PROP" 2>/dev/null
	[ -n "$OLD_FORCEDDP" ] && resetprop "$FORCEDDP_PROP" "$OLD_FORCEDDP"
	grep -q '^t9015rate ' /proc/modules && /system/bin/rmmod t9015rate
	audio_restart || log "audio services did not restart after rollback"
	droidaudio_restart || log "vendor audio service did not restart after rollback"
	overlay_set disable
}

fail() {
	log "FAILED: $1"
	[ "$2" = rollback ] && rollback
	rm -f "$PENDING"
	set_status "Inactive: $1. Nothing is changed. Log: $LOG"
	exit 0
}

# Stick DOLBY_TRUEHD into the <surroundSound> list, then make sure the result
# is exactly one line longer and still ends properly
make_policy() {
	awk '
		/<surroundSound>/ { in_ss = 1 }
		in_ss && /<\/formats>/ && !done {
			match($0, /^[ \t]*/)
			print substr($0, 1, RLENGTH) "    <format name=\"AUDIO_FORMAT_DOLBY_TRUEHD\" />"
			done = 1
		}
		{ print }
		/<\/surroundSound>/ { in_ss = 0 }
	' "$POLICY" > "$GEN_POLICY" || return 1
	surround_has_truehd "$GEN_POLICY" || return 1
	[ "$(wc -l < "$GEN_POLICY")" -eq $(($(wc -l < "$POLICY") + 1)) ] || return 1
	tail -n 3 "$GEN_POLICY" | grep -q '</audioPolicyConfiguration>' || return 1
	chmod 0644 "$GEN_POLICY"
	chcon u:object_r:vendor_configs_file:s0 "$GEN_POLICY"
}

# compat_check already matched the stock file's sha256, so we know what's in
# it: the same three HDMI keys, plus the three flags that unhide the options
make_aml_config() {
	cat > "$GEN_AML_CONFIG" <<-'EOF'
	{
	    "HDMITX_Src_Select": 4,
	    "HDMITX_Multi_CH_Src_Select": 3,
	    "HDMITX_HBR_Src_Select": 3,
	    "Passthrough_Audio_Config": 1,
	    "Dolby_DRC_Audio_Config": 1,
	    "Dts_DRC_Audio_Config": 1
	}
	EOF
	chmod 0644 "$GEN_AML_CONFIG"
	chcon u:object_r:vendor_configs_file:s0 "$GEN_AML_CONFIG"
}

log "---- boot $(getprop ro.boot.bootreason) uptime $(cut -d' ' -f1 /proc/uptime)s"

# apply.pending only exists while steps 1-5 run. Finding it here means the
# box went down in the middle last time, so back off and let the user decide.
if [ -f "$PENDING" ]; then
	rm -f "$PENDING"
	overlay_set disable
	touch "$MODDIR/disable"
	set_status "Disabled itself: the box rebooted while TrueHD passthrough was being applied. Re-enable in Magisk to try again. Log: $LOG"
	exit 0
fi

# make sure the Settings row isn't left on if we bail out here
if ! compat_check || ! compat_runtime; then
	overlay_set disable
	fail "$COMPAT_REASON"
fi
command -v resetprop >/dev/null || fail "resetprop not found"

touch "$PENDING"
sync

# 1. kernel helper
if ! grep -q '^t9015rate ' /proc/modules; then
	base=$(t9015_data_base)
	case "$base" in
	0x0000000000000000 | 0x0 | "") fail "could not read the codec driver's address" ;;
	esac
	if ! /system/bin/insmod "$HELPER" data_base="$base" 2>> "$LOG"; then
		dmesg | grep t9015rate | tail -n 3 >> "$LOG"
		fail "kernel helper refused to load"
	fi
	log "kernel helper loaded (data_base=$base)"
fi

# 2. audio policy
if ! surround_has_truehd "$POLICY"; then
	make_policy || fail "could not build the edited audio policy" rollback
	bind "$GEN_POLICY" "$POLICY" || fail "could not mount the edited audio policy" rollback
	log "audio policy mounted"
fi

# 3. HAL config
if ! grep -q Passthrough_Audio_Config "$AML_CONFIG"; then
	make_aml_config || fail "could not write the audio HAL config" rollback
	bind "$GEN_AML_CONFIG" "$AML_CONFIG" || fail "could not mount the audio HAL config" rollback
	log "audio HAL config mounted"
fi

# 4. props (memory only, gone on reboot)
OLD_FORCEDDP=$(getprop "$FORCEDDP_PROP")
resetprop "$TRUEHD_PROP" true
resetprop "$FORCEDDP_PROP" false
log "props set ($FORCEDDP_PROP was '$OLD_FORCEDDP')"

# 5. restart audio. The HAL comes back up in Automatic no matter what was
# saved, so hand it the saved mode again afterwards.
audio_restart || fail "audio services did not come back" rollback
droidaudio_restart || fail "vendor audio service did not come back" rollback
log "audio services restarted"
mode=$(digital_mode_get)
digital_mode_set "$mode" || fail "could not hand the saved audio mode to the HAL" rollback
log "audio mode: $(mode_name "$mode") (HAL reports $(hal_mode))"

rm -f "$PENDING"

# 6. Settings row. Only if Settings is the exact build the overlay was made
# from. If not, no big deal, the Magisk Action button opens the same menu.
if settings_overlay_compatible && overlay_set enable; then
	where="in Settings > Display & Sound > Audio output mode"
	log "Settings row enabled"
else
	overlay_set disable
	where="with the Magisk Action button"
	log "Settings row not enabled (Settings app is a different build)"
fi

if [ "$mode" = 3 ]; then
	set_status "Active. Audio output mode: Passthrough, so TrueHD/Atmos is sent untouched. Change it $where."
else
	set_status "Active. Audio output mode: $(mode_name "$mode"). For lossless TrueHD/Atmos choose Passthrough $where."
fi
