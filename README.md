# Quota

在 macOS 菜单栏和 Touch Bar 实时查看 [Codex](https://github.com/openai/codex) 的用量配额。

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5.9+-orange" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License">
</p>

> [!NOTE]
> 本项目需要已安装 Codex CLI 或 Codex.app（二选一即可），且账户需有有效的 rate limit 配额。

## 特性

- 菜单栏图标快速查看 Codex 配额详情
- Terminal 或 Codex 前台时，在 Touch Bar 展示 5 小时窗口和周限额
- 每 2 分钟自动刷新，也支持手动刷新
- 以 accessory 模式运行，不占 Dock 栏
- 通过 Codex 的 `app-server` 读取数据，优先使用 PATH 中的 `codex` CLI，找不到时回退到 `/Applications/Codex.app`

## 安装

### 从源码构建

```bash
git clone https://github.com/slightlee/quota.git
cd quota
swift build -c release
cp .build/release/Quota ~/Applications/Quota
```

然后双击运行，或加入登录项实现开机自启：

**系统设置 → 通用 → 登录项 → 添加 Quota**

### 打包为 `.app`

```bash
bash Scripts/package-app.sh
```

打包产物会输出到 `.build/package/Quota.app`，可以直接双击启动。

## 使用

启动后菜单栏会出现 Quota 图标，稍等片刻自动获取数据。

- 点击菜单栏图标查看 5 小时窗口和周限额
- 点击「刷新」或按 `⌘R` 手动刷新
- 点击「代理设置...」配置连接代理
- 点击「退出」或按 `⌘Q` 退出

Touch Bar 只在 Terminal 或 Codex 前台时显示，切换到其他应用后会隐藏。

## 工作原理

```
┌──────────────┐     JSON-RPC (stdio)     ┌──────────────┐
│              │ ◄──────────────────────► │              │
│    Quota     │   account/rateLimits/    │    Codex     │
│              │         read             │ (app-server) │
└──────┬───────┘                          └──────────────┘
       │
       ▼
 ┌──────────────────────────┐   ┌──────────────────────┐
 │ MenuBarController        │   │ TouchBarController   │
 │ + MenuBarLimitView       │   │ + TouchBarLimitView  │
 └──────────────────────────┘   └──────────────────────┘
```

Quota 启动 Codex 的 app-server 子进程，通过 stdin/stdout 以 JSON-RPC 协议读取配额数据，每 2 分钟轮询一次。

## 系统要求

- macOS 14 (Sonoma) 或更高版本
- [Codex CLI](https://github.com/openai/codex) 或 Codex.app 已安装（二选一即可）

## 开发

```bash
# 本地运行
swift run

# 生成发布版
swift build -c release

# 查看调试日志
swift run 2>&1 | grep "\[Quota\]"
```

## 贡献

欢迎提 Issue 和 PR。

## 许可证

[MIT](LICENSE)
