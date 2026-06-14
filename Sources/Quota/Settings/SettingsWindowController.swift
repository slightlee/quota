import AppKit

// MARK: - Constants

private enum Layout {
    static let windowWidth: CGFloat = 480
    static let windowHeight: CGFloat = 280
    static let padding: CGFloat = 24
    static let labelWidth: CGFloat = 48
    static let rowSpacing: CGFloat = 12
    static let sectionSpacing: CGFloat = 14
}

// MARK: - SettingsWindowController

final class SettingsWindowController: NSWindowController {
    private let proxyStore: ProxySettingsStore
    private let hotkeyStore: HotkeySettingsStore
    private let onSave: (ProxyConfiguration, HotkeyConfiguration) -> Void
    private let rootViewController: SettingsViewController

    init(
        proxyStore: ProxySettingsStore,
        hotkeyStore: HotkeySettingsStore,
        onSave: @escaping (ProxyConfiguration, HotkeyConfiguration) -> Void
    ) {
        self.proxyStore = proxyStore
        self.hotkeyStore = hotkeyStore
        self.onSave = onSave
        self.rootViewController = SettingsViewController()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Layout.windowWidth, height: Layout.windowHeight),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "设置"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentViewController = rootViewController

        super.init(window: window)

        rootViewController.configure(
            proxyConfiguration: proxyStore.configuration,
            hotkeyConfiguration: hotkeyStore.configuration,
            onSave: { [weak self] proxyConfig, hotkeyConfig in
                guard let self else { return }
                self.proxyStore.configuration = proxyConfig
                self.hotkeyStore.configuration = hotkeyConfig
                self.onSave(proxyConfig, hotkeyConfig)
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
        rootViewController.reload(
            proxyConfiguration: proxyStore.configuration,
            hotkeyConfiguration: hotkeyStore.configuration
        )
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - SettingsViewController

private final class SettingsViewController: NSViewController {
    // Tab
    private let tabControl = NSSegmentedControl(labels: ["代理", "快捷键"], trackingMode: .selectOne, target: nil, action: nil)
    private let proxyContainer = NSView()
    private let hotkeyContainer = NSView()
    // Proxy
    private let modeControl = NSSegmentedControl(labels: ProxyMode.allCases.map(\.displayTitle), trackingMode: .selectOne, target: nil, action: nil)
    private let proxyURLField = NSTextField(string: "")
    private let helperLabel = NSTextField(labelWithString: "")
    // Hotkey
    private let keyRecorder = KeyRecorderView()
    private let hotkeyToggle = NSButton(checkboxWithTitle: "启用全局快捷键", target: nil, action: nil)
    // Buttons
    private let saveButton = NSButton(title: "保存", target: nil, action: nil)
    private let cancelButton = NSButton(title: "取消", target: nil, action: nil)

    private var onSave: ((ProxyConfiguration, HotkeyConfiguration) -> Void)?
    private var onCancel: (() -> Void)?

    private var pendingHotkeyCode: UInt32 = 0
    private var pendingHotkeyModifiers: UInt32 = 0

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: Layout.windowWidth, height: Layout.windowHeight))
        setupUI()
    }

    func configure(
        proxyConfiguration: ProxyConfiguration,
        hotkeyConfiguration: HotkeyConfiguration,
        onSave: @escaping (ProxyConfiguration, HotkeyConfiguration) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onSave = onSave
        self.onCancel = onCancel
        reload(proxyConfiguration: proxyConfiguration, hotkeyConfiguration: hotkeyConfiguration)
    }

    func reload(proxyConfiguration: ProxyConfiguration, hotkeyConfiguration: HotkeyConfiguration) {
        guard isViewLoaded else { return }
        modeControl.selectedSegment = ProxyMode.allCases.firstIndex(of: proxyConfiguration.mode) ?? 0
        proxyURLField.stringValue = proxyConfiguration.proxyURL
        updateVisibility()

        pendingHotkeyCode = hotkeyConfiguration.keyCode
        pendingHotkeyModifiers = hotkeyConfiguration.modifiers
        hotkeyToggle.state = hotkeyConfiguration.isEnabled ? .on : .off
        keyRecorder.configure(displayString: hotkeyConfiguration.displayString)
    }

    // MARK: - UI Construction

    private func setupUI() {
        // ── Tab switcher ──
        tabControl.selectedSegment = 0
        tabControl.target = self
        tabControl.action = #selector(tabChanged)

        // ── Proxy tab content ──
        setupProxyTab()
        proxyContainer.translatesAutoresizingMaskIntoConstraints = false

        // ── Hotkey tab content ──
        setupHotkeyTab()
        hotkeyContainer.translatesAutoresizingMaskIntoConstraints = false
        hotkeyContainer.isHidden = true

        // ── Button row ──
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

        // ── Root layout ──
        let rootStack = NSStackView(views: [tabControl, proxyContainer, hotkeyContainer, buttonRow])
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

            proxyContainer.leadingAnchor.constraint(equalTo: rootStack.leadingAnchor, constant: Layout.padding),
            proxyContainer.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor, constant: -Layout.padding),
            hotkeyContainer.leadingAnchor.constraint(equalTo: rootStack.leadingAnchor, constant: Layout.padding),
            hotkeyContainer.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor, constant: -Layout.padding),
            tabControl.leadingAnchor.constraint(equalTo: rootStack.leadingAnchor, constant: Layout.padding),
        ])

        updateVisibility()
    }

    private func setupProxyTab() {
        let subtitleLabel = NSTextField(labelWithString: "选择代理模式以连接 Codex 服务")
        subtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor

        let modeLabel = makeLabel("模式")
        modeControl.target = self
        modeControl.action = #selector(modeChanged)
        let modeRow = makeRow(label: modeLabel, control: modeControl)

        let proxyLabel = makeLabel("地址")
        proxyURLField.placeholderString = "http://127.0.0.1:7890"
        proxyURLField.target = self
        proxyURLField.action = #selector(valueChanged)
        let proxyRow = makeRow(label: proxyLabel, control: proxyURLField)

        helperLabel.font = .systemFont(ofSize: 11, weight: .regular)
        helperLabel.textColor = .secondaryLabelColor
        helperLabel.maximumNumberOfLines = 0
        helperLabel.lineBreakMode = .byWordWrapping

        let stack = NSStackView(views: [subtitleLabel, modeRow, proxyRow, helperLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Layout.sectionSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false

        proxyContainer.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: proxyContainer.topAnchor),
            stack.leadingAnchor.constraint(equalTo: proxyContainer.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: proxyContainer.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: proxyContainer.bottomAnchor),
        ])
    }

    private func setupHotkeyTab() {
        let subtitleLabel = NSTextField(labelWithString: "设置快捷键，在任意应用中快速展开顶部菜单栏")
        subtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor

        hotkeyToggle.target = self
        hotkeyToggle.action = #selector(hotkeyToggleChanged)

        keyRecorder.onChange = { [weak self] keyCode, modifiers in
            self?.pendingHotkeyCode = keyCode
            self?.pendingHotkeyModifiers = modifiers
        }
        keyRecorder.onClear = { [weak self] in
            self?.pendingHotkeyCode = 0
            self?.pendingHotkeyModifiers = 0
        }

        let menuLabel = NSTextField(labelWithString: "打开菜单")
        menuLabel.font = .systemFont(ofSize: 13, weight: .medium)
        menuLabel.textColor = .labelColor
        menuLabel.setContentHuggingPriority(.required, for: .horizontal)
        let toggleRow = makeRow(label: menuLabel, control: keyRecorder)

        let stack = NSStackView(views: [subtitleLabel, hotkeyToggle, toggleRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Layout.sectionSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false

        hotkeyContainer.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: hotkeyContainer.topAnchor),
            stack.leadingAnchor.constraint(equalTo: hotkeyContainer.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: hotkeyContainer.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: hotkeyContainer.bottomAnchor),
            keyRecorder.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
        ])
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

    // MARK: - Tab Switching

    @objc private func tabChanged() {
        let isProxy = tabControl.selectedSegment == 0
        proxyContainer.isHidden = !isProxy
        hotkeyContainer.isHidden = isProxy
    }

    // MARK: - Logic

    private func currentProxyConfiguration() -> ProxyConfiguration {
        let mode = ProxyMode.allCases[safe: modeControl.selectedSegment] ?? .automatic
        return ProxyConfiguration(mode: mode, proxyURL: proxyURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func currentHotkeyConfiguration() -> HotkeyConfiguration {
        return HotkeyConfiguration(
            keyCode: pendingHotkeyCode,
            modifiers: pendingHotkeyModifiers,
            isEnabled: hotkeyToggle.state == .on
        )
    }

    private func updateVisibility() {
        let configuration = currentProxyConfiguration()
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

    @objc private func hotkeyToggleChanged() {
        let enabled = hotkeyToggle.state == .on
        if enabled && pendingHotkeyCode == 0 {
            view.window?.makeFirstResponder(keyRecorder)
        }
    }

    @objc private func save() {
        let proxyConfig = currentProxyConfiguration()
        if proxyConfig.mode == .manual {
            guard Self.isValidProxyURL(proxyConfig.proxyURL) else {
                presentValidationError()
                return
            }
        }

        let hotkeyConfig = currentHotkeyConfiguration()
        if hotkeyConfig.isEnabled {
            guard hotkeyConfig.isValid else {
                presentHotkeyValidationError()
                return
            }
        }

        onSave?(proxyConfig, hotkeyConfig)
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

    private func presentHotkeyValidationError() {
        let alert = NSAlert()
        alert.messageText = "快捷键无效"
        alert.informativeText = "启用全局快捷键后，请先录入至少一个修饰键和一个按键。"
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
