#!/system/bin/sh

MODDIR=${0%/*}
. "$MODDIR/refresh-common.sh"

print_state() {
    modes=$(get_display_modes)
    if [ -z "$modes" ]; then
        printf '%s\n' 'error=未找到系统支持的显示模式'
        return 1
    fi

    available_rates=$(get_available_rates "$modes")
    max_width=$(printf '%s\n' "$modes" | awk '{ print $2 }' | get_maximum)
    auto_rate=$(printf '%s\n' "$available_rates" | tr ' ' '\n' | get_maximum)
    configured=$(read_configured_rate)
    case "$configured" in
        auto) ;;
        *[!0-9]*|'') configured=auto ;;
        *)
            if ! printf '%s\n' "$available_rates" | tr ' ' '\n' | grep -qx "$configured"; then
                configured=auto
            fi
            ;;
    esac

    current=$(get_current_refresh_rate)
    [ -n "$current" ] || current=unknown
    printf 'rates=%s\n' "$available_rates"
    printf 'selected=%s\n' "$configured"
    printf 'auto=%s\n' "$auto_rate"
    printf 'current=%s\n' "$current"
    printf 'width=%s\n' "$max_width"
    printf 'configured_apps=%s\n' "$(read_high_refresh_apps)"
}

print_apps() {
    printf 'configured_apps=%s\n' "$(read_high_refresh_apps)"
    list_high_refresh_app_labels | while IFS="$(printf '\t')" read -r package_name app_label; do
        [ -n "$package_name" ] || continue
        [ -n "$app_label" ] || app_label="$package_name"
        printf 'app=%s\t%s\n' "$package_name" "$app_label"
    done
}

prepare_target_rate() {
    requested="$1"
    modes=$(get_display_modes)
    if [ -z "$modes" ]; then
        printf '%s\n' 'error=未找到系统支持的显示模式'
        return 1
    fi

    available_rates=$(get_available_rates "$modes")
    max_width=$(printf '%s\n' "$modes" | awk '{ print $2 }' | get_maximum)
    auto_rate=$(printf '%s\n' "$available_rates" | tr ' ' '\n' | get_maximum)
    case "$requested" in
        auto) target_rate=$auto_rate ;;
        ''|*[!0-9]*) printf '%s\n' 'error=刷新率必须是 auto 或系统支持的整数档位'; return 1 ;;
        *)
            if ! printf '%s\n' "$available_rates" | tr ' ' '\n' | grep -qx "$requested"; then
                printf 'error=不支持 %sHz，可用档位：%s\n' "$requested" "$available_rates"
                return 1
            fi
            target_rate=$requested
            ;;
    esac

    mode_id=$(printf '%s\n' "$modes" | awk -v width="$max_width" -v rate="$target_rate" '$2 == width && $3 == rate { print $1; exit }')
    if [ -z "$mode_id" ]; then
        printf 'error=最高分辨率 %s 不支持 %sHz\n' "$max_width" "$target_rate"
        return 1
    fi
}

apply_current_application_lock() {
    target_rate="$1"
    mode_id="$2"
    foreground_package=$(get_foreground_package)
    locked=0

    if is_high_refresh_app "$foreground_package"; then
        capture_original_refresh_settings
        apply_idle_fps_policy
        apply_user_refresh_rate "$target_rate"
        register_scene_refresh_rate "$foreground_package" "$target_rate" || true
        force_display_mode "$mode_id" || return 1
        locked=1
    else
        release_high_refresh_lock
    fi

    sleep 0.2
    current=$(get_current_refresh_rate)
    [ -n "$current" ] || current=unknown
}

apply_rate() {
    requested=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    prepare_target_rate "$requested" || return 1
    if ! write_configured_rate "$requested"; then
        printf '%s\n' 'error=无法写入 refresh.conf'
        return 1
    fi
    if ! apply_current_application_lock "$target_rate" "$mode_id"; then
        printf 'error=应用 %sHz 失败，已保存配置\n' "$target_rate"
        return 1
    fi

    update_module_description "当前刷新率：${current}Hz"
    printf 'ok=1\nrequested=%s\ntarget=%s\ncurrent=%s\nlocked=%s\n' "$requested" "$target_rate" "$current" "$locked"
}

save_apps() {
    if ! write_high_refresh_apps "$1"; then
        printf '%s\n' 'error=无法写入 refresh.conf'
        return 1
    fi

    requested=$(read_configured_rate)
    requested=${requested:-auto}
    prepare_target_rate "$requested" || return 1
    if ! apply_current_application_lock "$target_rate" "$mode_id"; then
        printf '%s\n' 'error=应用应用选择失败'
        return 1
    fi

    update_module_description "当前刷新率：${current}Hz"
    printf 'ok=1\napps=%s\ncurrent=%s\nlocked=%s\n' "$(read_high_refresh_apps)" "$current" "$locked"
}

case "$1" in
    status|'') print_state ;;
    apps) print_apps ;;
    apply) apply_rate "$2" ;;
    setapps) save_apps "$2" ;;
    *) printf '%s\n' 'error=未知操作' ; exit 1 ;;
esac
