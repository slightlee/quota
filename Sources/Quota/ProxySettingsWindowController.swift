import AppKit

// MARK: - 常量

private enum Layout {
    static let windowWidth: CGFloat = 480
    static let windowHeight: CGFloat = 200
    static let padding: CGFloat = 24
    static let labelWidth: CGFloat = 48
    static let rowSpacing: CGFloat = 12
    static let sectionSpacing: CGFloat = 14
}

// MARK: - ProxySettingsWindowController

final class ProxySettingsWindowController: NSWindowController {
    private let store: ProxySettingsStore
    private let onSave: (ProxyConfiguration) -> Void
    private let rootViewController: ProxySettingsViewController

    init(store: ProxySettingsStore, onSave: @escaping (ProxyConfiguration) -> Void) {
        self.store = store
        self.onSave = onSave
        self.rootViewController = ProxySettingsViewController()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Layout.windowWidth, height: Layout.windowHeight),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "代理设置"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentViewController = rootViewController

        super.init(window: window)

        rootViewController.configure(
            configuration: store.configuration,
            onSave: { [weak self] configuration in
                self?.store.configuration = configuration
                self?.onSave(configuration)
            },
            onCancel: { [weak self] in
                self?.window?.close()
            }
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        rootViewController.loadViewIfNeeded()
        rootViewController.reload(configuration: store.configuration)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - ProxySettingsViewController

private final class ProxySettingsViewController: NSViewController {
    private let modeControl = NSSegmentedControl(labels: ProxyMode.allCases.map(\.displayTitle), trackingMode: .selectOne, target: nil, action: nil)
    private let proxyURLField = NSTextField(string: "")
    private let helperLabel = NSTextField(labelWithString: "")
    private let saveButton = NSButton(title: "保存", target: nil, action: nil)
    private let cancelButton = NSButton(title: "取消", target: nil, action: nil)
    private var onSave: ((ProxyConfiguration) -> Void)?
    private var onCancel: (() -> Void)?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: Layout.windowWidth, height: Layout.windowHeight))
        setupUI()
    }

    func configure(
        configuration: ProxyConfiguration,
        onSave: @escaping (ProxyConfiguration) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onSave = onSave
        self.onCancel = onCancel
        reload(configuration: configuration)
    }

    func reload(configuration: ProxyConfiguration) {
        guard isViewLoaded else { return }
        modeControl.selectedSegment = ProxyMode.allCases.firstIndex(of: configuration.mode) ?? 0
        proxyURLField.stringValue = configuration.proxyURL
        updateVisibility()
    }

    // MARK: - UI 构建

    private func setupUI() {
        // ── 说明文字 ──
        let subtitleLabel = NSTextField(labelWithString: "选择代理模式以连接 Codex 服务")
        subtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor

        // ── 模式选择行 ──
        let modeLabel = makeLabel("模式")
        modeControl.target = self
        modeControl.action = #selector(modeChanged)

        let modeRow = makeRow(label: modeLabel, control: modeControl)

        // ── 代理地址行 ──
        let proxyLabel = makeLabel("地址")
        proxyURLField.placeholderString = "http://127.0.0.1:7890"
        proxyURLField.target = self
        proxyURLField.action = #selector(valueChanged)

        let proxyRow = makeRow(label: proxyLabel, control: proxyURLField)

        // ── 提示文字 ──
        helperLabel.font = .systemFont(ofSize: 11, weight: .regular)
        helperLabel.textColor = .secondaryLabelColor
        helperLabel.maximumNumberOfLines = 0
        helperLabel.lineBreakMode = .byWordWrapping

        // ── 按钮行（右对齐）──
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.target = self
        saveButton.action = #selector(save)

        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.target = self
        cancelButton.action = #selector(cancel)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let buttonRow = NSStackView(views: [spacer, cancelButton, saveButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        buttonRow.alignment = .centerY

        // ── 根布局（单一 stack view，用 edgeInsets 控制边距）──
        let rootStack = NSStackView(views: [subtitleLabel, modeRow, proxyRow, helperLabel, buttonRow])
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = Layout.sectionSpacing
        rootStack.edgeInsets = NSEdgeInsets(
            top: Layout.padding,
            left: Layout.padding,
            bottom: Layout.padding,
            right: Layout.padding
        )

        view.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: view.topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        updateVisibility()
    }

    private func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.widthAnchor.constraint(equalToConstant: Layout.labelWidth).isActive = true
        return label
    }

    private func makeRow(label: NSView, control: NSView) -> NSStackView {
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = Layout.rowSpacing
        return row
    }

    // MARK: - 逻辑

    private func currentConfiguration() -> ProxyConfiguration {
        let mode = ProxyMode.allCases[safe: modeControl.selectedSegment] ?? .automatic
        return ProxyConfiguration(mode: mode, proxyURL: proxyURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func updateVisibility() {
        let configuration = currentConfiguration()
        let isManual = configuration.mode == .manual
        proxyURLField.isEnabled = isManual
        proxyURLField.alphaValue = isManual ? 1.0 : 0.45
        helperLabel.stringValue = isManual
            ? "填写完整的代理地址，例如 http://127.0.0.1:7890 或 socks5://127.0.0.1:1080"
            : "自动模式使用系统代理，关闭模式不注入代理"
    }

    @objc private func modeChanged() {
        updateVisibility()
    }

    @objc private func valueChanged() {}

    @objc private func save() {
        let configuration = currentConfiguration()
        if configuration.mode == .manual {
            guard Self.isValidProxyURL(configuration.proxyURL) else {
                presentValidationError()
                return
            }
        }

        onSave?(configuration)
        view.window?.close()
    }

    @objc private func cancel() {
        onCancel?()
    }

    private func presentValidationError() {
        let alert = NSAlert()
        alert.messageText = "代理地址无效"
        alert.informativeText = "请输入完整的代理地址，例如 http://127.0.0.1:7890 或 socks5://127.0.0.1:1080。"
        alert.alertStyle = .warning
        if let window = view.window ?? NSApp.keyWindow {
            alert.beginSheetModal(for: window) { _ in }
        } else {
            alert.runModal()
        }
    }

    private static func isValidProxyURL(_ value: String) -> Bool {
        guard let components = URLComponents(string: value), let scheme = components.scheme, let host = components.host, !scheme.isEmpty, !host.isEmpty else {
            return false
        }
        return true
    }
}

// MARK: - Utils

private extension Array {
    subscript(safe index: Index) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
