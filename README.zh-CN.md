# Quota

[English](README.md)

Quota 是一个轻量级 macOS 菜单栏应用，用于实时查看 [Codex](https://github.com/openai/codex) 的用量配额。

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5.9+-orange" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License">
</p>

> [!NOTE]
> 使用前需要安装 Codex CLI 或 Codex.app，并确保账户有可读取的 rate limit 配额数据。

## 特性

- 菜单栏展示 Codex 5 小时额度和周额度
- Terminal 或 Codex 前台时在 Touch Bar 展示额度
- 额度不足时发送 macOS 通知
- 每 2 分钟自动刷新，也支持手动刷新
- 支持 Codex app-server 连接代理配置
- 支持全局快捷键打开菜单栏弹窗
- 支持跟随系统、英文和简体中文语言切换
- 以 accessory 模式运行，不占 Dock 栏
- 通过 Codex `app-server` 读取数据，优先使用 `PATH` 中的 `codex`，找不到时回退到 `/Applications/Codex.app`

## 截图

### 菜单栏

![菜单栏配额视图](Docs/Images/menu-bar.png)

### Touch Bar

![Touch Bar 配额视图](Docs/Images/touch-bar.jpg)

### 额度通知

![额度通知提醒](Docs/Images/notification.png)

## 安装

### 下载 DMG

从 [GitHub Releases](https://github.com/slightlee/quota/releases) 下载最新的 `Quota-*.dmg`，打开后将 `Quota.app` 拖入 `Applications`。

### 从源码构建

```bash
git clone https://github.com/slightlee/quota.git
cd quota
bash Scripts/package-app.sh
ditto .build/package/Quota.app /Applications/Quota.app
```

然后从 `Applications` 启动 `Quota.app`。

如需开机自启：

**系统设置 -> 通用 -> 登录项 -> 添加 Quota**

不建议直接运行或复制 `.build/release/Quota` 裸二进制；通知权限、应用图标和菜单栏资源都依赖标准 `.app` 包结构。

## 使用

启动后菜单栏会出现 Quota 图标，稍等片刻自动获取数据。

- 点击菜单栏图标查看 5 小时窗口和周限额
- 点击 `刷新` 或按 `⌘R` 手动刷新
- 点击 `设置` 配置代理、全局快捷键和显示语言
- 点击 `退出` 或按 `⌘Q` 退出

Touch Bar 只在 Terminal 或 Codex 前台时显示，切换到其他应用后会隐藏。

### 通知阈值

默认在以下剩余额度阈值发送通知：

- 低于 20%：普通提醒
- 低于 10%：紧急提醒
- 低于 5%：严重不足提醒

每个窗口、每个阈值只提醒一次；额度恢复到 50% 以上后会重置提醒状态。

## 打包

### 生成 `.app`

```bash
bash Scripts/package-app.sh
```

输出：

```text
.build/package/Quota.app
```

### 生成 `.dmg`

```bash
bash Scripts/package-dmg.sh
```

输出：

```text
.build/Quota-<version>.dmg
```

DMG 默认包含固定 Finder 安装窗口布局：左侧为 `Quota.app`，右侧为 `Applications` 快捷入口。如果 CI 环境无法控制 Finder，会自动降级为默认布局但仍生成可用 DMG。

## 工作原理

```text
┌──────────────┐     JSON-RPC (stdio)     ┌──────────────┐
│              │ ◄──────────────────────► │              │
│    Quota     │   account/rateLimits/    │    Codex     │
│              │         read             │ (app-server) │
└──────┬───────┘                          └──────┬───────┘
       │                                         │
       ▼                                         ▼
 ┌──────────────────────────┐             ┌──────────────────────┐
 │ MenuBarController        │             │ TouchBarController   │
 │ + MenuBarLimitView       │             │ + TouchBarLimitView  │
 └──────────────────────────┘             └──────────────────────┘
```

Quota 会启动 Codex 的 `app-server` 子进程，通过 stdin/stdout 上的 JSON-RPC 读取配额数据，并每 2 分钟刷新一次。

## 系统要求

- macOS 14 Sonoma 或更高版本
- Codex CLI 或 Codex.app
- 拥有可读取 rate limit 配额数据的 Codex 账户

## 开发

```bash
# 本地运行
swift run

# 生成 .app
bash Scripts/package-app.sh

# 生成 .dmg
bash Scripts/package-dmg.sh

# 查看调试日志
swift run 2>&1 | grep "\[Quota\]"
```

## 贡献

欢迎提交 Issue 和 PR。

## 许可证

[MIT](LICENSE)
