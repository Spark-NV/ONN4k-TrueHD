#!/bin/sh
# Builds module/system/product/overlay/OnnTrueHDSettingsOverlay.apk.
# Set these first:
#   AAPT2         aapt2 binary (com.android.tools.build:aapt2 on Google Maven)
#   APKSIG        apksig jar (com.android.tools.build:apksig on Google Maven)
#   FRAMEWORK_RES /system/framework/framework-res.apk pulled from the box
#   TVSETTINGS    /system_ext/priv-app/TvSettingsTwoPanel/TvSettingsTwoPanel.apk
#                 pulled from the box (must match the hash in compat.sh)
#   KEYSTORE      a PKCS12 keystore with an "overlay" alias, KEYPASS its password
set -e
cd "$(dirname "$0")"
out=$(mktemp -d)
"$AAPT2" compile --dir res -o "$out/res.zip"
"$AAPT2" link -o "$out/unsigned.apk" --manifest AndroidManifest.xml \
	-I "$FRAMEWORK_RES" -I "$TVSETTINGS" \
	--package-id 0x7e --allow-reserved-package-id "$out/res.zip"
java -cp "$APKSIG" SignApk.java "$out/unsigned.apk" \
	../../module/system/product/overlay/OnnTrueHDSettingsOverlay.apk "$KEYSTORE" "$KEYPASS" overlay
rm -rf "$out"
