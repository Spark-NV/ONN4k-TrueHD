# Shared bits for customize.sh, service.sh and action.sh, plus the check for
# whether this box is one we know works.
#
# t9015rate.ko pokes two values inside the T9015 codec driver and is built
# for one exact kernel, so it only runs on the builds listed below. On
# anything else we just say why and do nothing.
#
# Got another firmware working? Test it by hand first, then add a line:
#   device|kernel release|sha256 of amlogic-snd-codec-t9015.ko

SUPPORTED_BUILDS="
jarvis2|5.15.196-android14-11-g3d26c188ef7e-ab14657224|a8d99a85c38e78a7850ae25aa0f29b5f8545d1cf7011f5d73e496b9e1e0e324a
"

T9015_KO=/vendor/lib/modules/amlogic-snd-codec-t9015.ko
AUDIO_HAL=/vendor/lib/hw/audio.primary.amlogic.so
POLICY=/odm/etc/audio_policy_configuration.xml
TRUEHD_PROP=ro.vendor.platform.is.aml_truehd_passthrough
FORCEDDP_PROP=ro.vendor.platform.is.forceddp

# The stock HAL config only sets up HDMI routing. We add the flags that make
# onn's Passthrough, Dolby DRC and DTS DRC options show up.
AML_CONFIG=/vendor/etc/aml_audio_config.json
AML_CONFIG_STOCK_SHA256=f960a9910e66cf3ff63ba8794c3ffa7b7e7c469d0cff356c9a6b83eb03daeafe

# The Settings row is an overlay that carries a copy of this Settings build's
# Display & Sound screen with one extra row, so it only gets turned on when
# the Settings app matches.
TVSETTINGS_APK=/system_ext/priv-app/TvSettingsTwoPanel/TvSettingsTwoPanel.apk
TVSETTINGS_SHA256=d633d85309b584a60a8c8335b197a75c2a71447675eff9559b61afaf11d163ce
OVERLAY_PKG=com.onn.truehd.settingsoverlay
SOUND_ACTIVITY=com.droidlogic.tv.settings/.SoundActivity

COMPAT_REASON=""

# Use Magisk's busybox. The toybox grep here chokes on binary files and its
# nsenter ignores -t.
BB=/data/adb/magisk/busybox

# Where the codec driver's .data section is in memory. With kptr_restrict on
# it just reads as zero, so turn that off for this one read and put it back.
t9015_data_base() {
	local old base
	old=$(cat /proc/sys/kernel/kptr_restrict)
	echo 0 > /proc/sys/kernel/kptr_restrict
	base=$(cat /sys/module/amlogic_snd_codec_t9015/sections/.data)
	echo "$old" > /proc/sys/kernel/kptr_restrict
	echo "$base"
}

# Is TrueHD in the <surroundSound> list? Only look inside that section, the
# stock file already mentions TrueHD further up in the HDMI port profiles.
surround_has_truehd() {
	awk '/<surroundSound>/ { s = 1 } s && /AUDIO_FORMAT_DOLBY_TRUEHD/ { f = 1 }
	     /<\/surroundSound>/ { s = 0 } END { exit !f }' "$1"
}

# Is the installed Settings app the one the overlay was made from?
settings_overlay_compatible() {
	[ "$(sha256sum "$TVSETTINGS_APK" 2>/dev/null | cut -d' ' -f1)" = "$TVSETTINGS_SHA256" ]
}

# File checks, fine to run both at install time and on every boot.
compat_check() {
	local device kernel ko_sum line
	device=$(getprop ro.product.device)
	kernel=$(uname -r)

	[ -f "$T9015_KO" ] || { COMPAT_REASON="T9015 codec driver not found"; return 1; }
	ko_sum=$(sha256sum "$T9015_KO" | cut -d' ' -f1)

	for line in $SUPPORTED_BUILDS; do
		if [ "$line" = "$device|$kernel|$ko_sum" ]; then
			$BB grep -q "$TRUEHD_PROP" "$AUDIO_HAL" 2>/dev/null || {
				COMPAT_REASON="audio HAL has no TrueHD passthrough switch"
				return 1
			}
			grep -q '<surroundSound>' "$POLICY" 2>/dev/null || {
				COMPAT_REASON="audio policy has no surround format list"
				return 1
			}
			# either it's still stock, or it's our copy from an earlier run
			if ! grep -q Passthrough_Audio_Config "$AML_CONFIG" &&
			   [ "$(sha256sum "$AML_CONFIG" | cut -d' ' -f1)" != "$AML_CONFIG_STOCK_SHA256" ]; then
				COMPAT_REASON="audio HAL config is not the stock file"
				return 1
			fi
			return 0
		fi
	done
	COMPAT_REASON="unsupported build (device=$device kernel=$kernel)"
	return 1
}

# onn's audio service (droidaudio). On this build call 21 is
# setDigitalAudioMode(int mode, String formats) and 22 is getDigitalAudioMode().
# It saves the mode in /data/droidaudio/droidaudio.db and passes it on to the HAL.
# Modes: 0 PCM, 1 Auto, 2 Manual, 3 Passthrough, 4 Always.
DROIDAUDIO=vendor.amlogic.hardware.droidaudio.IDroidAudio/default

# prints the saved mode, or nothing if the service didn't answer
digital_mode_get() {
	/system/bin/service call "$DROIDAUDIO" 22 2>/dev/null |
		sed -n "s/.*Parcel(.*00000000 \([0-9a-f]\{8\}\) .*/\1/p" |
		{ read -r hex && [ -n "$hex" ] && echo $((0x$hex)); }
}

digital_mode_set() {
	/system/bin/service call "$DROIDAUDIO" 21 i32 "$1" s16 "" >/dev/null 2>&1 &&
		[ "$(digital_mode_get)" = "$1" ]
}

# what the HAL itself says it's doing (AUTO, BYPASS, ...)
hal_mode() {
	/system/bin/dumpsys media.audio_flinger 2>/dev/null |
		sed -n 's/.*digital_audio_mode *: *\([A-Z_]*\).*/\1/p' | head -n 1
}

mode_name() {
	case "$1" in
	0) echo PCM ;; 1) echo Automatic ;; 2) echo Manual ;;
	3) echo Passthrough ;; 4) echo Always ;; *) echo unknown ;;
	esac
}

# Things that have to be up and running before we touch anything.
compat_runtime() {
	[ -r /sys/module/amlogic_snd_codec_t9015/sections/.data ] || {
		COMPAT_REASON="T9015 codec driver is not loaded"
		return 1
	}
	grep -q AMLAUGESOUND /proc/asound/cards 2>/dev/null || {
		COMPAT_REASON="Amlogic sound card is not registered"
		return 1
	}
	[ -n "$(digital_mode_get)" ] || {
		COMPAT_REASON="vendor audio service is not answering"
		return 1
	}
	return 0
}
