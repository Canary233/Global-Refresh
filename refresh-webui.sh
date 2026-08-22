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
    printf 'global_enabled=%s\n' "$(read_global_refresh_enabled)"
}

print_apps() {
    configured_rates=$(list_configured_app_rates | awk '
        { output = output == "" ? $0 : output "," $0 }
        END { print output }
    ')
    printf 'configured_rates=%s\n' "$configured_rates"
    list_high_refresh_app_labels | awk -F '\t' -v configured_rates="$configured_rates" '
        BEGIN {
            count = split(configured_rates, records, ",")
            for (position = 1; position <= count; position++) {
                split(records[position], fields, "=")
                if (fields[1] != "") rates[fields[1]] = fields[2]
            }
        }
        {
            package_name = $1
            label = $2
            if (package_name != "") print "app=" package_name "\t" label "\t" rates[package_name]
        }
    '
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

read_current_rate() {
    current=$(get_current_refresh_rate)
    [ -n "$current" ] || current=unknown
}

apply_global_lock() {
    capture_original_refresh_settings
    apply_idle_fps_policy
    clear_registered_scene_refresh_rates
    apply_user_refresh_rate "$target_rate"
    force_display_mode "$mode_id" || return 1
    sleep 0.2
    read_current_rate
    locked=1
}

apply_current_application_lock() {
    foreground_package=$(get_foreground_package)
    requested=$(get_configured_app_rate "$foreground_package")
    locked=0

    if [ -z "$requested" ]; then
        release_high_refresh_lock
        read_current_rate
        return 0
    fi

    prepare_target_rate "$requested" || return 1
    capture_original_refresh_settings
    apply_idle_fps_policy
    apply_user_refresh_rate "$target_rate"
    register_scene_refresh_rate "$foreground_package" "$target_rate" || true
    force_display_mode "$mode_id" || return 1
    sleep 0.2
    read_current_rate
    locked=1
}

set_global() {
    enabled="$1"
    requested=$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')
    case "$enabled" in
        true|false) ;;
        *) printf '%s\n' 'error=全局高刷开关无效'; return 1 ;;
    esac

    prepare_target_rate "$requested" || return 1
    if ! write_configured_rate "$requested" || ! write_global_refresh_enabled "$enabled"; then
        printf '%s\n' 'error=无法写入 refresh.conf'
        return 1
    fi

    if [ "$enabled" = true ]; then
        if ! apply_global_lock; then
            printf 'error=应用全局 %sHz 失败，已保存配置\n' "$target_rate"
            return 1
        fi
        message="已全局锁定 ${target_rate}Hz"
    else
        if ! apply_current_application_lock; then
            printf '%s\n' 'error=关闭全局高刷后无法应用当前应用配置'
            return 1
        fi
        message='已关闭全局高刷，可配置每个应用的刷新率'
    fi

    update_module_description "当前刷新率：${current}Hz"
    printf 'ok=1\nglobal_enabled=%s\nrequested=%s\ntarget=%s\ncurrent=%s\nlocked=%s\nmessage=%s\n' "$enabled" "$requested" "$target_rate" "$current" "$locked" "$message"
}

validate_app_rates() {
    app_rates=$(normalize_app_refresh_rates "$1")
    old_ifs=$IFS
    IFS=,
    for record in $app_rates; do
        rate=${record#*=}
        prepare_target_rate "$rate" || {
            IFS=$old_ifs
            return 1
        }
    done
    IFS=$old_ifs
}

save_app_rates() {
    if [ "$(read_global_refresh_enabled)" = true ]; then
        printf '%s\n' 'error=请先关闭全局高刷，再配置应用刷新率'
        return 1
    fi

    validate_app_rates "$1" || return 1
    if ! write_app_refresh_rates "$app_rates"; then
        printf '%s\n' 'error=无法写入 refresh.conf'
        return 1
    fi

    if ! apply_current_application_lock; then
        printf '%s\n' 'error=应用当前应用配置失败，已保存设置'
        return 1
    fi

    update_module_description "当前刷新率：${current}Hz"
    printf 'ok=1\nrates=%s\ncurrent=%s\nlocked=%s\n' "$app_rates" "$current" "$locked"
}

case "$1" in
    status|'') print_state ;;
    apps) print_apps ;;
    setglobal) set_global "$2" "$3" ;;
    setapps) save_app_rates "$2" ;;
    *) printf '%s\n' 'error=未知操作' ; exit 1 ;;
esac
