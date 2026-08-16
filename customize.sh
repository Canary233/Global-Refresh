#!/system/bin/sh

# KernelSU extracts module files as regular files first; restore executable bits
# for the scripts that are invoked by the module lifecycle and WebUI.
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/global-refresh.sh" 0 0 0755
set_perm "$MODPATH/refresh-common.sh" 0 0 0755
set_perm "$MODPATH/refresh-webui.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
set_perm "$MODPATH/bin/scene-rate.jar" 0 0 0644
