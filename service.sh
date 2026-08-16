#!/system/bin/sh

MODDIR=${0%/*}
(
    while [ "$(getprop sys.boot_completed)" != "1" ]; do
        sleep 2
    done
    exec /system/bin/sh "$MODDIR/global-refresh.sh"
) >/data/local/tmp/global-refresh.log 2>&1 &
