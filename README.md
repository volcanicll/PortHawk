# PortHawk · 端口簿

> 常驻 macOS 菜单栏的端口账簿：**什么应用占了什么端口、什么项目用了什么端口**，一眼可查。

[![CI](https://github.com/volcanicll/PortHawk/actions/workflows/ci.yml/badge.svg)](https://github.com/volcanicll/PortHawk/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/volcanicll/PortHawk?color=A3321C&label=%E7%89%88%E6%9C%AC)](https://github.com/volcanicll/PortHawk/releases/latest)
[![Site](https://img.shields.io/badge/%E8%90%BD%E5%9C%B0%E9%A1%B5-2D4B6F)](https://volcanicll.github.io/PortHawk/)

**下载安装**：前往 [落地页](https://volcanicll.github.io/PortHawk/)，或终端一条命令安装最新版：

```bash
curl -fsSL https://volcanicll.github.io/PortHawk/install.sh | bash
```

![面板总览](verify/panel.png)

PortHawk 是一个原生 SwiftUI 菜单栏应用（`MenuBarExtra`），整个 App 是一个约 1 MB 的二进制，无 Electron、无运行时依赖。它把本机所有 TCP 监听端口记成一册账：端口号在左侧页码列，进程、所属项目、PID、路径在右；项目归属通过读取进程工作目录自动推断。

## 功能

- **账簿面板**：所有 TCP 监听端口一册账，hairline 横格分组，宋体标题、等宽端口号。
- **两种视图**：「按项目」把端口归到所属项目组下；「按端口」先收藏、后全部，按端口号排序。
- **进程品牌墨点**：约 90 项常见开发工具进程（node、python、redis-server、Code Helper…）在行首显示品牌色墨点。
- **明细页**：点任意行钻取整页明细——完整命令行、可执行路径、所在目录、用户、父进程、线程数、内存、累计与实时 CPU%，可直接结束或强制结束（SIGKILL）。
- **一键结束进程（两步确认）**：悬停行出现「结束」，第一次点变实心「确认结束」，2.5 秒内再点才发信号；结束中的行被红笔划掉（账簿式批注）。权限不足时页脚给出可复制的 sudo 命令。
- **收藏与占位行**：点星收藏常用端口，置顶展示；收藏的端口空闲时显示淡墨「未占用」占位行，服务挂掉一目了然。
- **占用告警**：收藏端口被新进程占走时，菜单栏图标出现圆点、行上盖朱砂「占」印章；新端口盖蓝墨「新」印章。
- **对外/本机徽章**：监听 `0.0.0.0` / `*`（局域网可达）标赭色「对外」，仅 `127.0.0.1` 标灰色「本机」；工具栏「仅对外」一键筛选暴露面。
- **失败不撒谎**：lsof 扫描失败（含 3 秒超时）时保留上一轮数据，页脚提示「扫描失败 · 保留上一轮」。
- **设置页**：刷新间隔（1/3/5/10 秒）、菜单栏数字开关、登录时启动（SMAppService）。

## 截图

| 明细页 | 设置页 |
| --- | --- |
| ![明细页](verify/detail.png) | ![设置页](verify/settings.png) |

## 安装与签名说明

应用使用 **ad-hoc 临时签名**（仓库无 Apple Developer 证书，未公证）。这带来一个已知代价：

- **浏览器下载的 DMG/zip 带 quarantine 标记**，首次打开会弹「已损坏，无法打开」或「无法验证开发者」。
- 两种解法：
  1. **用安装脚本**（推荐）：`curl -fsSL https://volcanicll.github.io/PortHawk/install.sh | bash`——curl 下载的文件不带 quarantine，装完直接能开，且总是最新版；
  2. **手动安装后清除标记**：`xattr -cr /Applications/PortHawk.app`，之后正常打开。

若要彻底消除该提示，需要 Developer ID 证书签名 + 公证（Apple Developer Program，$99/年）；收到 `codesign` 证书后在 `release.yml` 构建步骤加入签名与 `notarytool` 公证即可。

## 构建与运行

要求 macOS 13+ 与 Command Line Tools（无需完整 Xcode）。

```bash
./build.sh
open build/PortHawk.app
```

构建产物在 `build/PortHawk.app`，菜单栏出现书本图标与端口计数。

## 开发与诊断

```bash
# 数据层自检：与 lsof 原始输出对照
./build/PortHawk.app/Contents/MacOS/PortHawk --cli

# 对指定端口发结束信号（验证 kill 流程）
./build/PortHawk.app/Contents/MacOS/PortHawk --cli --kill-port 3000

# 浮动预览窗（真实数据真实交互，免菜单栏点击）
./build/PortHawk.app/Contents/MacOS/PortHawk --preview

# 截图验证：真实数据 / 模拟状态 / 明细页 / 设置页 / 菜单栏图标
./build/PortHawk.app/Contents/MacOS/PortHawk --screenshot verify/real.png
./build/PortHawk.app/Contents/MacOS/PortHawk --screenshot-mock verify/mock.png
./build/PortHawk.app/Contents/MacOS/PortHawk --screenshot-mock-detail verify/detail.png
./build/PortHawk.app/Contents/MacOS/PortHawk --screenshot-mock-settings verify/settings.png
./build/PortHawk.app/Contents/MacOS/PortHawk --render-icon verify/icon.png 12 --alert
```

## 发布流程（GitHub Actions）

- **`ci.yml`**：`Sources/`、`build.sh` 变化或 PR 时在干净的 macOS runner 上跑一次 `./build.sh`，保证构建脚本始终可用。
- **`release.yml`**：推送 `v*` 标签触发——从 tag 注入版本号到 Info.plist → 构建 → 打 DMG 与 zip 安装包 → 自动创建 GitHub Release 并上传产物。
- **`site-deploy.yml`**：`site/` 变化时把落地页部署到 GitHub Pages。页面版本号在浏览器里运行时从 Releases API 拉取，**应用发新版只需推 tag，落地页无需重部署**。

日常发版：`git tag v0.x.0 && git push origin v0.x.0`。

## 数据来源与边界

- 端口清单：`lsof -iTCP -sTCP:LISTEN -n -P -l +c0`，按 `(port, pid)` 去重（IPv4/IPv6 双栈只记一条，与 `lsof` 的行数差异即来源于此）。
- 项目推断：`proc_pidinfo(PROC_PIDVNODEPATHINFO)` 读进程 cwd，取目录 basename；`/System`、`/usr`、`/private/var`、`/tmp` 等系统路径与家目录本身不视为项目。
- 只覆盖**当前用户**的进程：其他用户的进程读不到 cwd 与可执行路径（明细相应字段显示 `—`），结束他人进程会提示权限不足并给出 sudo 命令。
- 只监控 TCP 监听；UDP 与出站连接不在账上。
- lsof 会把进程名里的空格转义为 `\x20`（如 `Google\x20Chrome`），已还原。

## 灵感与借鉴

**[Pulse](https://github.com/egoist/pulse)**（Go + WebView 菜单栏系统监视器）——品牌墨点、inspector 明细钻取、Force Quit、过滤预设均来自对其二进制的静态逆向；其整机监控能力不属于端口账簿的边界，未采纳。

**[PortBar](https://github.com/egoist/portbar)**（Swift 菜单栏端口监控）——收藏占位行、扫描失败保留旧数据、扫描超时、结束进程二次确认、sudo 命令复制、菜单栏数字徽标、登录自启。

## 目录结构

```
Sources/
├── main.swift          入口分发（菜单栏应用 / CLI / 截图与图标诊断）
├── Core/
│   ├── PortScanner.swift   lsof 解析 + proc_pidinfo 项目推断与明细数据 + kill
│   ├── AppState.swift      轮询、新旧 diff、收藏告警、分组、明细采样、偏好迁移
│   └── DevBrand.swift      进程品牌目录（约 90 项开发工具）
└── UI/
    ├── PanelViews.swift    账簿面板、明细页、设置页
    └── Theme.swift         纸面视觉令牌（纸、墨、蓝墨、朱砂、赭金）
```

偏好存储于 UserDefaults（域 `app.porthawk.PortHawk`）；从旧 bundle id（`local.controlport.app`）升级会自动迁移收藏与设置。

## License

[MIT](LICENSE)
