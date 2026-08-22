#!/system/bin/sh

config_file="$MODDIR/refresh.conf"
module_id=global_refresh
scene_rate_jar="$MODDIR/bin/scene-rate.jar"
scene_packages_file="$MODDIR/scene-packages.list"
refresh_settings_file="$MODDIR/original-refresh-settings.conf"
app_labels_cache_file="$MODDIR/app-labels.cache"

log() {
    printf '%s\n' "global_refresh: $*"
}

update_module_description() {
    description="$1"
    ksud_bin=$(command -v ksud 2>/dev/null)
    if [ -z "$ksud_bin" ] && [ -x /data/adb/ksud ]; then
        ksud_bin=/data/adb/ksud
    fi

    if [ -n "$ksud_bin" ]; then
        KSU_MODULE="$module_id" "$ksud_bin" module config set override.description "$description" >/dev/null 2>&1 && return 0
    fi
    log 'ksud 不可用，无法更新 KernelSU 模块描述。'
    return 1
}

clear_module_description() {
    ksud_bin=$(command -v ksud 2>/dev/null)
    if [ -z "$ksud_bin" ] && [ -x /data/adb/ksud ]; then
        ksud_bin=/data/adb/ksud
    fi
    [ -n "$ksud_bin" ] || return 0
    KSU_MODULE="$module_id" "$ksud_bin" module config delete override.description >/dev/null 2>&1
}

# Emit one record per primary-display mode: ID, horizontal resolution, rounded refresh rate.
# The parser supports both single-line and multi-line mSfDisplayModes output.
get_display_modes() {
    dumpsys display 2>/dev/null | awk '
        function emit_modes(line, chunks, chunk_count, fields, field_count, i, j, field, id, width, rate) {
            chunk_count = split(line, chunks, "DisplayMode\\{")
            for (i = 2; i <= chunk_count; i++) {
                id = width = rate = ""
                field_count = split(chunks[i], fields, ",")
                for (j = 1; j <= field_count; j++) {
                    field = fields[j]
                    gsub(/^[[:space:]]+/, "", field)
                    if (field ~ /^id=/) {
                        sub(/^id=/, "", field)
                        id = field
                    } else if (field ~ /^width=/) {
                        sub(/^width=/, "", field)
                        width = field
                    } else if (field ~ /^refreshRate=/) {
                        sub(/^refreshRate=/, "", field)
                        rate = field
                    } else if (field ~ /^peakRefreshRate=/ && rate == "") {
                        sub(/^peakRefreshRate=/, "", field)
                        rate = field
                    } else if (field ~ /^vsyncRate=/ && rate == "") {
                        sub(/^vsyncRate=/, "", field)
                        rate = field
                    }
                }
                if (id != "" && width != "" && rate != "") {
                    printf "%s %s %d\n", id, width, int(rate + 0.5)
                }
            }
        }
        /mSfDisplayModes=/ { reading_modes = 1 }
        reading_modes { emit_modes($0) }
        reading_modes && /^[[:space:]]*\]/ { exit }
        reading_modes && $0 !~ /mSfDisplayModes=/ && /^[[:space:]]*m[A-Za-z0-9_]+=/ { exit }
    ' | sort -u
}

get_maximum() {
    awk 'NR == 1 || $1 > maximum { maximum = $1 } END { if (NR) print maximum }'
}

get_available_rates() {
    modes="$1"
    max_width=$(printf '%s\n' "$modes" | awk '{ print $2 }' | get_maximum)
    printf '%s\n' "$modes" |
        awk -v width="$max_width" '$2 == width { print $3 }' |
        sort -nu |
        tr '\n' ' ' |
        sed 's/[[:space:]]*$//'
}

get_current_refresh_rate() {
    active_rate=$(cmd display get-active-mode 0 2>/dev/null | awk '
        /Refresh Rate:/ {
            rate = $0
            sub(/^.*Refresh Rate:[[:space:]]*/, "", rate)
            sub(/[[:space:]].*$/, "", rate)
            print int(rate + 0.5)
            exit
        }
    ')
    if [ -n "$active_rate" ]; then
        printf '%s\n' "$active_rate"
        return 0
    fi

    dumpsys display 2>/dev/null | awk '
        /mActiveSfDisplayMode=/ {
            field_count = split($0, fields, ",")
            rate = ""
            for (i = 1; i <= field_count; i++) {
                field = fields[i]
                gsub(/^[[:space:]]+/, "", field)
                if (field ~ /^peakRefreshRate=/) {
                    sub(/^peakRefreshRate=/, "", field)
                    rate = field
                } else if (field ~ /^refreshRate=/ && rate == "") {
                    sub(/^refreshRate=/, "", field)
                    rate = field
                }
            }
            if (rate != "") {
                print int(rate + 0.5)
                exit
            }
        }
    '
}

write_default_config() {
    umask 022
    if [ -s "$MODDIR/refresh.conf.default" ]; then
        cp -f "$MODDIR/refresh.conf.default" "$config_file" || return 1
        chmod 0644 "$config_file" 2>/dev/null
        return 0
    fi

    cat > "$config_file" <<'EOF'
# 全局高刷配置
# 版本：1.4.0
# 开启后全局锁定 refresh_rate；关闭后按 app_refresh_rates 为应用单独锁定。
global_refresh_enabled=false
# refresh_rate 可填写 auto 或整数帧率，例如 60、90、120。
# auto 会自动选择当前最高分辨率下的最高可用帧率。
refresh_rate=auto
# 禁止小米动态空闲/视频降帧；填写 false 可关闭。
disable_idle_fps=true
# 在小米/HyperOS 上使用系统场景策略压过视频应用的 60Hz 请求。
enable_scene_refresh_rate=true
# 应用和目标刷新率，格式为 包名=档位，多个应用用逗号分隔。留空即不锁定任何应用。
app_refresh_rates=
EOF
    chmod 0644 "$config_file" 2>/dev/null
}

write_config_value() {
    key="$1"
    value="$2"
    temp_file="$config_file.tmp.$$"

    if [ ! -s "$config_file" ]; then
        write_default_config || return 1
    fi

    awk -v key="$key" -v value="$value" '
        BEGIN { replaced = 0 }
        $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
            print key "=" value
            replaced = 1
            next
        }
        { print }
        END { if (!replaced) print key "=" value }
    ' "$config_file" > "$temp_file" || {
        rm -f "$temp_file"
        return 1
    }
    chmod 0644 "$temp_file" 2>/dev/null
    mv -f "$temp_file" "$config_file"
}

write_configured_rate() {
    write_config_value refresh_rate "$1"
}

read_configured_rate() {
    awk -F '=' '
        /^[[:space:]]*refresh_rate[[:space:]]*=/ {
            value = $2
            gsub(/^[[:space:]]+/, "", value)
            gsub(/[[:space:]]+$/, "", value)
            print value
            exit
        }
    ' "$config_file" 2>/dev/null | tr '[:upper:]' '[:lower:]'
}

read_global_refresh_enabled() {
    value=$(awk -F '=' '
        /^[[:space:]]*global_refresh_enabled[[:space:]]*=/ {
            value = $2
            gsub(/^[[:space:]]+/, "", value)
            gsub(/[[:space:]]+$/, "", value)
            print value
            exit
        }
    ' "$config_file" 2>/dev/null | tr '[:upper:]' '[:lower:]')

    case "$value" in
        true|1|yes|on) printf '%s\n' true ;;
        *) printf '%s\n' false ;;
    esac
}

write_global_refresh_enabled() {
    case "$1" in
        true|1|yes|on) write_config_value global_refresh_enabled true ;;
        false|0|no|off) write_config_value global_refresh_enabled false ;;
        *) return 1 ;;
    esac
}

read_disable_idle_fps() {
    awk -F '=' '
        /^[[:space:]]*disable_idle_fps[[:space:]]*=/ {
            value = $2
            gsub(/^[[:space:]]+/, "", value)
            gsub(/[[:space:]]+$/, "", value)
            print value
            exit
        }
    ' "$config_file" 2>/dev/null | tr '[:upper:]' '[:lower:]'
}

read_scene_refresh_rate_enabled() {
    awk -F '=' '
        /^[[:space:]]*enable_scene_refresh_rate[[:space:]]*=/ {
            value = $2
            gsub(/^[[:space:]]+/, "", value)
            gsub(/[[:space:]]+$/, "", value)
            print value
            exit
        }
    ' "$config_file" 2>/dev/null | tr '[:upper:]' '[:lower:]'
}

read_high_refresh_apps() {
    awk -F '=' '
        /^[[:space:]]*high_refresh_apps[[:space:]]*=/ {
            value = $2
            gsub(/^[[:space:]]+/, "", value)
            gsub(/[[:space:]]+$/, "", value)
            print value
            exit
        }
    ' "$config_file" 2>/dev/null
}

normalize_high_refresh_apps() {
    printf '%s' "$1" | tr ',' '\n' | awk '
        {
            gsub(/^[[:space:]]+/, "")
            gsub(/[[:space:]]+$/, "")
            if ($0 ~ /^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+$/ && !seen[$0]++) {
                output = output == "" ? $0 : output "," $0
            }
        }
        END { print output }
    '
}

write_high_refresh_apps() {
    apps=$(normalize_high_refresh_apps "$1")
    requested_rate=$(read_configured_rate)
    case "$requested_rate" in
        ''|*[!0-9]*) requested_rate=auto ;;
    esac
    app_rates=$(printf '%s\n' "$apps" | tr ',' '\n' | awk -v rate="$requested_rate" '
        NF { output = output == "" ? $0 "=" rate : output "," $0 "=" rate }
        END { print output }
    ')
    write_app_refresh_rates "$app_rates"
}

read_app_refresh_rates() {
    awk '
        /^[[:space:]]*app_refresh_rates[[:space:]]*=/ {
            value = $0
            sub(/^[^=]*=/, "", value)
            gsub(/^[[:space:]]+/, "", value)
            gsub(/[[:space:]]+$/, "", value)
            print value
            exit
        }
    ' "$config_file" 2>/dev/null
}

normalize_app_refresh_rates() {
    printf '%s' "$1" | tr ',' '\n' | awk '
        {
            gsub(/^[[:space:]]+/, "")
            gsub(/[[:space:]]+$/, "")
            count = split($0, fields, "=")
            package_name = fields[1]
            rate = tolower(fields[2])
            if (count == 2 && package_name ~ /^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+$/ && rate ~ /^(auto|[0-9]+)$/ && !seen[package_name]++) {
                output = output == "" ? package_name "=" rate : output "," package_name "=" rate
            }
        }
        END { print output }
    '
}

# Legacy high_refresh_apps entries are retained as the prior shared refresh_rate
# until WebUI saves the new per-application format.
list_configured_app_rates() {
    legacy_rate=$(read_configured_rate)
    case "$legacy_rate" in
        ''|*[!0-9]*) legacy_rate=auto ;;
    esac

    {
        read_app_refresh_rates | tr ',' '\n'
        read_high_refresh_apps | tr ',' '\n' | awk -v rate="$legacy_rate" '
            /^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+$/ { print $0 "=" rate }
        '
    } | awk '
        {
            count = split($0, fields, "=")
            package_name = fields[1]
            rate = tolower(fields[2])
            if (count == 2 && package_name ~ /^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+$/ && rate ~ /^(auto|[0-9]+)$/ && !seen[package_name]++) {
                order[++record_count] = package_name
                values[package_name] = rate
            }
        }
        END {
            for (position = 1; position <= record_count; position++) {
                package_name = order[position]
                print package_name "=" values[package_name]
            }
        }
    '
}

get_configured_app_rate() {
    package_name="$1"
    case "$package_name" in
        ''|*[!A-Za-z0-9_.]*) return 1 ;;
    esac
    list_configured_app_rates | awk -F '=' -v package_name="$package_name" '$1 == package_name { print $2; exit }'
}

write_app_refresh_rates() {
    app_rates=$(normalize_app_refresh_rates "$1")
    write_config_value app_refresh_rates "$app_rates" || return 1
    # Clear the legacy list once the new mapping has been saved, allowing users to remove old entries.
    write_config_value high_refresh_apps ''
}

is_high_refresh_app() {
    package_name="$1"
    case "$package_name" in
        ''|*[!A-Za-z0-9_.]*) return 1 ;;
    esac
    [ -n "$(get_configured_app_rate "$package_name")" ]
}

list_installed_apps() {
    cmd package list packages -3 2>/dev/null |
        sed 's/^package://' |
        awk '/^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+$/' |
        sort -u
}

list_high_refresh_apps() {
    {
        list_configured_app_rates | awk -F '=' '{ print $1 }'
        list_installed_apps
    } | awk '/^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+$/' | sort -u
}

resolve_app_labels() {
    package_names="$1"
    [ -n "$package_names" ] || return 0

    if [ -r "$scene_rate_jar" ] && [ -x /system/bin/app_process ]; then
        (
            # Package names are validated by list_high_refresh_apps before word splitting.
            set -- $package_names
            CLASSPATH="$scene_rate_jar" /system/bin/app_process /system/bin SceneRate --labels "$@"
        ) && return 0
    fi

    printf '%s\n' "$package_names" | while IFS= read -r package_name; do
        [ -n "$package_name" ] && printf '%s\t%s\n' "$package_name" "$package_name"
    done
}

app_labels_cache_matches() {
    package_names="$1"
    [ -s "$app_labels_cache_file" ] || return 1

    cached_packages=$(awk -F '\t' '{ print $1 }' "$app_labels_cache_file")
    [ "$cached_packages" = "$package_names" ]
}

write_app_labels_cache() {
    labels="$1"
    cache_temp="$app_labels_cache_file.tmp.$$"

    printf '%s\n' "$labels" > "$cache_temp" || return 1
    chmod 0644 "$cache_temp" 2>/dev/null
    mv -f "$cache_temp" "$app_labels_cache_file"
}

get_installed_app_labels() {
    package_names=$(list_installed_apps)
    [ -n "$package_names" ] || return 0

    if app_labels_cache_matches "$package_names"; then
        cat "$app_labels_cache_file"
        return 0
    fi

    labels=$(resolve_app_labels "$package_names")
    [ -n "$labels" ] || return 1
    write_app_labels_cache "$labels" || log '无法写入应用名称缓存。'
    printf '%s\n' "$labels"
}

list_high_refresh_app_labels() {
    installed_labels=$(get_installed_app_labels) || return 1
    printf '%s\n' "$installed_labels"

    list_configured_app_rates | awk -F '=' '{ print $1 }' | while IFS= read -r package_name; do
        [ -n "$package_name" ] || continue
        if ! printf '%s\n' "$installed_labels" | awk -F '\t' -v package_name="$package_name" '$1 == package_name { found = 1 } END { exit !found }'; then
            printf '%s\t%s\n' "$package_name" "$package_name"
        fi
    done
}

get_foreground_package() {
    activity_state=$(dumpsys activity activities 2>/dev/null)
    package_name=$(printf '%s\n' "$activity_state" | sed -n 's/^.*topResumedActivity=ActivityRecord{[^ ]* u[0-9]* \([^/ ]*\)\/.*$/\1/p' | head -n 1)
    if [ -n "$package_name" ]; then
        printf '%s\n' "$package_name"
        return 0
    fi
    window_state=$(dumpsys window 2>/dev/null)
    package_name=$(printf '%s\n' "$window_state" | sed -n 's/^.*mCurrentFocus=Window{[^ ]* [^ ]* \([^/ ]*\)\/.*$/\1/p' | head -n 1)
    if [ -n "$package_name" ] && [ "$package_name" != 'com.android.systemui' ]; then
        printf '%s\n' "$package_name"
        return 0
    fi
    printf '%s\n' "$window_state" | sed -n 's/^.*mFocusedApp=ActivityRecord{[^ ]* u[0-9]* \([^/ ]*\)\/.*$/\1/p' | head -n 1
}

remember_scene_package() {
    package_name="$1"
    [ -n "$package_name" ] || return 0
    [ -f "$scene_packages_file" ] && grep -qxF "$package_name" "$scene_packages_file" && return 0
    printf '%s\n' "$package_name" >> "$scene_packages_file"
    chmod 0600 "$scene_packages_file" 2>/dev/null
}

register_scene_refresh_rate() {
    package_name="$1"
    target_rate="$2"

    case "$(read_scene_refresh_rate_enabled)" in
        false|0|no|off) return 0 ;;
    esac
    case "$package_name" in
        ''|android|com.android.systemui|com.miui.home|com.google.android.permissioncontroller) return 0 ;;
    esac
    case "$target_rate" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ -r "$scene_rate_jar" ] || return 0
    [ -x /system/bin/app_process ] || return 0

    if CLASSPATH="$scene_rate_jar" /system/bin/app_process /system/bin SceneRate "$package_name" "$target_rate" >/dev/null 2>&1; then
        remember_scene_package "$package_name"
        return 0
    fi
    return 1
}

clear_scene_refresh_rate() {
    package_name="$1"
    case "$package_name" in
        ''|*[!A-Za-z0-9_.]*) return 1 ;;
    esac
    [ -r "$scene_rate_jar" ] || return 0
    [ -x /system/bin/app_process ] || return 0

    CLASSPATH="$scene_rate_jar" /system/bin/app_process /system/bin SceneRate "$package_name" -1 >/dev/null 2>&1
}

clear_registered_scene_refresh_rates() {
    [ -r "$scene_packages_file" ] || return 0
    while IFS= read -r package_name; do
        clear_scene_refresh_rate "$package_name"
    done < "$scene_packages_file"
    rm -f "$scene_packages_file"
}

apply_user_refresh_rate() {
    target_rate="$1"
    settings put system peak_refresh_rate "$target_rate" >/dev/null 2>&1
    settings put system min_refresh_rate "$target_rate" >/dev/null 2>&1
    settings put secure user_refresh_rate "$target_rate" >/dev/null 2>&1
    settings put secure miui_refresh_rate "$target_rate" >/dev/null 2>&1
}

force_display_mode() {
    mode_id="$1"
    service call SurfaceFlinger 1035 i64 "$mode_id" >/dev/null 2>&1
}

apply_idle_fps_policy() {
    case "$(read_disable_idle_fps)" in
        false|0|no|off) desired_idle_fps=false ;;
        *) desired_idle_fps=true ;;
    esac
    setprop persist.vendor.disable_idle_fps "$desired_idle_fps"
}

capture_original_refresh_settings() {
    [ -s "$refresh_settings_file" ] && return 0
    umask 077
    {
        printf 'system_peak_refresh_rate=%s\n' "$(settings get system peak_refresh_rate 2>/dev/null)"
        printf 'system_min_refresh_rate=%s\n' "$(settings get system min_refresh_rate 2>/dev/null)"
        printf 'secure_user_refresh_rate=%s\n' "$(settings get secure user_refresh_rate 2>/dev/null)"
        printf 'secure_miui_refresh_rate=%s\n' "$(settings get secure miui_refresh_rate 2>/dev/null)"
    } > "$refresh_settings_file"
    chmod 0600 "$refresh_settings_file" 2>/dev/null
}

restore_refresh_setting() {
    namespace="$1"
    key="$2"
    stored_key="$3"
    value=$(awk -F '=' -v key="$stored_key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$refresh_settings_file" 2>/dev/null)
    case "$value" in
        ''|null) settings delete "$namespace" "$key" >/dev/null 2>&1 ;;
        *) settings put "$namespace" "$key" "$value" >/dev/null 2>&1 ;;
    esac
}

restore_user_refresh_rate() {
    [ -s "$refresh_settings_file" ] || return 0
    restore_refresh_setting system peak_refresh_rate system_peak_refresh_rate
    restore_refresh_setting system min_refresh_rate system_min_refresh_rate
    restore_refresh_setting secure user_refresh_rate secure_user_refresh_rate
    restore_refresh_setting secure miui_refresh_rate secure_miui_refresh_rate
}

release_high_refresh_lock() {
    clear_registered_scene_refresh_rates
    restore_user_refresh_rate
    setprop persist.vendor.disable_idle_fps false
}

resolve_target_rate() {
    requested_rate="$1"
    default_rate="$2"

    case "$requested_rate" in
        ''|auto) printf '%s\n' "$default_rate" ;;
        *[!0-9]*) return 1 ;;
        *) printf '%s\n' "$requested_rate" ;;
    esac
}
