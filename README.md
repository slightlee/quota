# Quota

在 macOS 菜单栏和 Touch Bar 实时查看 [Codex](https://github.com/openai/codex) 的用量配额。

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5.9+-orange" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License">
</p>

> [!NOTE]
> 本项目需要已安装 Codex CLI（`/Applications/Codex.app`），且账户需有有效的 rate limit 配额。

## 效果

<!-- 替换为实际截图 -->

| 菜单栏 | Touch Bar |
|:---:|:---:|
| `Codex 72% / 85%` | ██████████░░░░░ 5 小时 |
| | ████████████████ 周限额 |

- 菜单栏显示 5 小时窗口 / 周限额的剩余百分比
- Touch Bar 以分段进度条可视化展示，颜色随余量变化（绿 → 橙 → 红）
- 每 2 分钟自动刷新，也可点击菜单手动刷新
- 以 accessory 模式运行，不占 Dock 栏

## 安装

### Homebrew（推荐）

> TODO: 发布后补充

### 从源码构建

```bash
git clone https://github.com/<your-username>/quota.git
cd quota
swift build -c release
cp .build/release/Quota ~/Applications/Quota
```

然后双击运行，或加入登录项实现开机自启：

**系统设置 → 通用 → 登录项 → 添加 Quota**

## 使用

启动后菜单栏会出现 `Codex --%`，稍等片刻自动获取数据。

- **查看详细配额** — 点击菜单栏图标
- **手动刷新** — 菜单中点击「刷新」或按 `⌘R`
- **退出** — 菜单中点击「退出」或按 `⌘Q`

## 工作原理

```
┌──────────────┐     JSON-RPC (stdio)     ┌──────────────┐
│              │ ◄──────────────────────► │              │
│    Quota     │   account/rateLimits/    │  Codex CLI   │
│              │         read             │ (app-server) │
└──────┬───────┘                          └──────────────┘
       │
       ▼
 ┌─────────────┐     ┌─────────────────┐
 │ 菜单栏文字  │     │ Touch Bar 进度条│
 └─────────────┘     └─────────────────┘
```

Quota 启动 Codex CLI 的 app-server 子进程，通过 stdin/stdout 以 JSON-RPC 协议读取配额数据，每 2 分钟轮询一次。

## 系统要求

- macOS 14 (Sonoma) 或更高版本
- [Codex CLI](https://github.com/openai/codex) 已安装

## 贡献

欢迎提 Issue 和 PR。

```bash
# 开发模式运行
swift run

# 查看调试日志
swift run 2>&1 | grep "\[Quota\]"
```

## 许可证

[MIT](LICENSE)
