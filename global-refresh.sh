#!/system/bin/sh

MODDIR=${0%/*}
poll_seconds=1
last_description=
last_scene_key=
lock_active=false

. "$MODDIR/refresh-common.sh"
clear_module_description

update_description_if_needed() {
    current_rate="$1"
    description="当前刷新率：${current_rate}Hz"
    [ "$description" = "$last_description" ] && return 0
    update_module_description "$description" && last_description="$description"
}

release_lock_if_needed() {
    [ "$lock_active" = true ] || return 0
    release_high_refresh_lock
    lock_active=false
    last_scene_key=
    log '当前应用未配置高刷，已释放刷新率锁定。'
}

# Remove scene entries left by an earlier service instance before enforcing the current selection.
clear_registered_scene_refresh_rates
restore_user_refresh_rate
setprop persist.vendor.disable_idle_fps false

while true; do
    foreground_package=$(get_foreground_package)
    if ! is_high_refresh_app "$foreground_package"; then
        release_lock_if_needed
        current_rate=$(get_current_refresh_rate)
        [ -n "$current_rate" ] && update_description_if_needed "$current_rate"
        sleep "$poll_seconds"
        continue
    fi

    modes=$(get_display_modes)
    if [ -z "$modes" ]; then
        log '未找到主屏显示模式，稍后重试。'
        sleep 3
        continue
    fi

    available_rates=$(get_available_rates "$modes")
    default_rate=$(printf '%s\n' "$available_rates" | tr ' ' '\n' | get_maximum)
    if [ -z "$default_rate" ]; then
        log '未找到可用刷新率，稍后重试。'
        sleep 3
        continue
    fi

    if [ ! -s "$config_file" ] && ! write_default_config; then
        log "无法写入配置文件：$config_file"
        sleep 3
        continue
    fi

    requested_rate=$(read_configured_rate)
    if ! target_rate=$(resolve_target_rate "$requested_rate" "$default_rate"); then
        log "配置 refresh_rate=$requested_rate 无效；请使用 auto 或整数帧率。"
        sleep 3
        continue
    fi

    max_width=$(printf '%s\n' "$modes" | awk '{ print $2 }' | get_maximum)
    mode_id=$(printf '%s\n' "$modes" | awk -v width="$max_width" -v rate="$target_rate" '$2 == width && $3 == rate { print $1; exit }')
    if [ -z "$mode_id" ]; then
        log "最高分辨率 $max_width 不支持 ${target_rate}Hz；可用值：$available_rates"
        sleep 3
        continue
    fi

    capture_original_refresh_settings
    apply_idle_fps_policy
    apply_user_refresh_rate "$target_rate"
    lock_active=true

    scene_key="${foreground_package}:${target_rate}"
    if [ "$scene_key" != "$last_scene_key" ]; then
        if register_scene_refresh_rate "$foreground_package" "$target_rate"; then
            last_scene_key="$scene_key"
            log "已为配置的应用 $foreground_package 登记 ${target_rate}Hz 场景策略"
        fi
    fi

    current_rate=$(get_current_refresh_rate)
    if [ "$current_rate" != "$target_rate" ]; then
        force_display_mode "$mode_id"
        sleep 0.1
        current_rate=$(get_current_refresh_rate)
    fi
    [ -n "$current_rate" ] || current_rate=$target_rate
    update_description_if_needed "$current_rate"

    sleep "$poll_seconds"
done
