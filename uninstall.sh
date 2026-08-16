#!/system/bin/sh

MODDIR=${0%/*}
. "$MODDIR/refresh-common.sh"

release_high_refresh_lock
rm -f "$refresh_settings_file"
clear_module_description
