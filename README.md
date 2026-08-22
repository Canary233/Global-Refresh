# 全局高刷
面向 KernelSU 的全局高刷模块。WebUI 支持全局锁定目标刷新率，或为每个应用设置独立刷新率。
在 Xiaomi / HyperOS 设备上，模块会使用系统场景刷新率策略，避免已配置应用（例如视频播放器）请求回落到 60Hz。

## 安装

1. 从 [Releases](https://github.com/Canary233/global-refresh/releases) 下载最新 ZIP。
2. 在 KernelSU 管理器安装模块后重启设备。
3. 打开模块 WebUI，选择全局高刷或应用刷新率模式。

## 配置

配置文件位于模块目录：`refresh.conf`。

```ini
global_refresh_enabled=false
refresh_rate=auto
disable_idle_fps=true
enable_scene_refresh_rate=true
app_refresh_rates=com.example.piliplus=120,com.example.reader=90
```

- `global_refresh_enabled=true` 时，全局锁定 `refresh_rate`；`refresh_rate` 可以是 `auto` 或系统支持的整数档位。
- `global_refresh_enabled=false` 时，使用 `app_refresh_rates` 设置应用包名与档位，格式为 `包名=auto` 或 `包名=整数档位`，多个应用以逗号分隔。
- 旧版 `high_refresh_apps` 会继续生效，并使用旧版 `refresh_rate`；在 WebUI 保存应用设置后会自动迁移。
- WebUI 会缓存系统应用名称；安装或卸载应用后会自动重新生成列表。
- OTA 升级会保留已有的 `refresh.conf`，不会清空已选应用。

## OTA 更新

`module.prop` 已指向仓库的 [update.json](https://raw.githubusercontent.com/Canary233/global-refresh/main/update.json)。KernelSU 管理器会使用其中的版本号、版本代码和 Release 下载地址检查更新。

## 构建

```powershell
pwsh ./scripts/build.ps1
```

构建产物输出至 `dist/`。
