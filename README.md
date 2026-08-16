# 全局高刷
面向 KernelSU 的全局高刷模块。通过 WebUI 选择需要高刷的应用，模块仅在这些应用处于前台时锁定刷新率。
在 Xiaomi / HyperOS 设备上，模块会使用系统场景刷新率策略，避免已选应用（例如视频播放器）请求回落到 60Hz。

## 安装

1. 从 [Releases](https://github.com/Canary233/global-refresh/releases) 下载最新 ZIP。
2. 在 KernelSU 管理器安装模块后重启设备。
3. 打开模块 WebUI，选择刷新率和需要高刷的应用。

## 配置

配置文件位于模块目录：`refresh.conf`。

```ini
refresh_rate=auto
disable_idle_fps=true
enable_scene_refresh_rate=true
high_refresh_apps=com.example.piliplus
```

- `refresh_rate` 可以是 `auto` 或系统支持的整数档位。
- `high_refresh_apps` 为逗号分隔的应用包名。留空时，模块不会锁定任何应用。

## OTA 更新

`module.prop` 已指向仓库的 [update.json](https://raw.githubusercontent.com/Canary233/global-refresh/main/update.json)。KernelSU 管理器会使用其中的版本号、版本代码和 Release 下载地址检查更新。

## 构建

```powershell
pwsh ./scripts/build.ps1
```

构建产物输出至 `dist/`。
