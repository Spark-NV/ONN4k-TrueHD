#!/system/bin/sh
# Everything else goes away on the next reboot. This just cleans up the log
# and the generated config copies.
#
# The audio output mode you picked is saved by onn's own service, so it stays.
# Passthrough is fine on stock (you just get DD+ again), or set it back to
# Automatic before removing if you want it exactly stock.
rm -rf /data/adb/onn_truehd
