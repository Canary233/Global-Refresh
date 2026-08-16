#!/system/bin/sh

# KernelSU extracts module files as regular files first; restore executable bits
# for the scripts that are invoked by the module lifecycle and WebUI.
config_file="$MODPATH/refresh.conf"
old_config_file="/data/adb/modules/global_refresh/refresh.conf"
if [ "$old_config_file" != "$config_file" ] && [ -s "$old_config_file" ]; then
    cp -f "$old_config_file" "$config_file"
elif [ ! -s "$config_file" ] && [ -s "$MODPATH/refresh.conf.default" ]; then
    cp -f "$MODPATH/refresh.conf.default" "$config_file"
fi

set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/global-refresh.sh" 0 0 0755
set_perm "$MODPATH/refresh-common.sh" 0 0 0755
set_perm "$MODPATH/refresh-webui.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
set_perm "$MODPATH/bin/scene-rate.jar" 0 0 0644
