#!/system/bin/sh
# Magisk runs this in the background. Wait until Android is fully booted
# before doing anything.
MODDIR=${0%/*}

until [ "$(getprop sys.boot_completed)" = 1 ]; do
	sleep 2
done
# give the audio services a moment to settle
sleep 15

. "$MODDIR/common/compat.sh"
. "$MODDIR/common/apply.sh"
