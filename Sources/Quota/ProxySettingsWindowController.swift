import AppKit

final class ProxySettingsWindowController: NSWindowController {
    private let store: ProxySettingsStore
    private let onSave: (ProxyConfiguration) -> Void
    private let rootViewController: ProxySettingsViewController

    init(store: ProxySettingsStore, onSave: @escaping (ProxyConfiguration) -> Void) {
        self.store = store
        self.onSave = onSave
        self.rootViewController = ProxySettingsViewController()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 240),
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

private final class ProxySettingsViewController: NSViewController {
    private let modeControl = NSSegmentedControl(labels: ProxyMode.allCases.map(\.displayTitle), trackingMode: .selectOne, target: nil, action: nil)
    private let proxyURLField = NSTextField(string: "")
    private let stateLabel = NSTextField(labelWithString: "")
    private let helperLabel = NSTextField(labelWithString: "")
    private let saveButton = NSButton(title: "保存", target: nil, action: nil)
    private let cancelButton = NSButton(title: "取消", target: nil, action: nil)
    private var onSave: ((ProxyConfiguration) -> Void)?
    private var onCancel: (() -> Void)?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 240))
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
        stateLabel.stringValue = stateText(for: configuration)
        updateVisibility()
    }

    private func setupUI() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let titleLabel = NSTextField(labelWithString: "代理设置")
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor

        let subtitleLabel = NSTextField(labelWithString: "自动模式会优先使用系统代理或当前环境变量；手动模式使用你填写的代理地址；关闭模式不注入代理。")
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 0
        subtitleLabel.lineBreakMode = .byWordWrapping

        modeControl.target = self
        modeControl.action = #selector(modeChanged)

        proxyURLField.placeholderString = "http://127.0.0.1:7890 或 socks5://127.0.0.1:1080"
        proxyURLField.target = self
        proxyURLField.action = #selector(valueChanged)

        helperLabel.stringValue = "手动模式下请填写完整代理地址；若使用系统代理或 TUN，可保持自动。"
        helperLabel.font = .systemFont(ofSize: 11, weight: .regular)
        helperLabel.textColor = .secondaryLabelColor
        helperLabel.maximumNumberOfLines = 0
        helperLabel.lineBreakMode = .byWordWrapping

        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.target = self
        saveButton.action = #selector(save)

        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.target = self
        cancelButton.action = #selector(cancel)

        let modeRow = makeRow(title: "模式", control: modeControl)
        let proxyRow = makeRow(title: "代理", control: proxyURLField)

        let buttonStack = NSStackView(views: [cancelButton, saveButton])
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8
        buttonStack.alignment = .centerY

        stateLabel.font = .systemFont(ofSize: 11, weight: .medium)
        stateLabel.textColor = .secondaryLabelColor

        let rootStack = NSStackView(views: [titleLabel, subtitleLabel, stateLabel, modeRow, proxyRow, helperLabel, buttonStack])
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 12
        rootStack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: view.topAnchor),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor)
        ])

        updateVisibility()
    }

    private func makeRow(title: String, control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 44).isActive = true

        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false

        if let textField = control as? NSTextField {
            textField.widthAnchor.constraint(equalToConstant: 280).isActive = true
        }

        return row
    }

    private func currentConfiguration() -> ProxyConfiguration {
        let mode = ProxyMode.allCases[safe: modeControl.selectedSegment] ?? .automatic
        return ProxyConfiguration(mode: mode, proxyURL: proxyURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func updateVisibility() {
        let configuration = currentConfiguration()
        let isManual = configuration.mode == .manual
        proxyURLField.isEnabled = isManual
        proxyURLField.alphaValue = isManual ? 1.0 : 0.55
        stateLabel.stringValue = stateText(for: configuration)
        helperLabel.stringValue = isManual
            ? "请填写完整代理地址，例如 http://127.0.0.1:7890 或 socks5://127.0.0.1:1080。"
            : "自动模式下会优先使用系统代理或当前环境变量；关闭模式不注入代理。"
    }

    private func stateText(for configuration: ProxyConfiguration) -> String {
        switch configuration.mode {
        case .automatic:
            return "当前模式：自动"
        case .disabled:
            return "当前模式：关闭"
        case .manual:
            if configuration.proxyURL.isEmpty {
                return "当前模式：手动（未填写代理地址）"
            }
            return "当前模式：手动"
        }
    }

    @objc private func modeChanged() {
        updateVisibility()
    }

    @objc private func valueChanged() {
        // Intentionally empty; keeps the field active for future validation.
    }

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

private extension Array {
    subscript(safe index: Index) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
