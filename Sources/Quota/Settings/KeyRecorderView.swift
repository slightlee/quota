import AppKit

/// A custom text field that captures keyboard shortcuts.
/// Click to start recording, press a key combination to set it.
final class KeyRecorderView: NSView {
    var onChange: ((UInt32, UInt32) -> Void)?
    var onClear: (() -> Void)?

    private var isRecording = false
    private var currentDisplay: String?

    private let labelField = NSTextField(labelWithString: "")
    private let clearButton = NSButton()

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public

    func configure(displayString: String?) {
        currentDisplay = displayString
        updateLabel()
    }

    // MARK: - Setup

    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        // Label
        labelField.font = .systemFont(ofSize: 13)
        labelField.alignment = .center
        labelField.lineBreakMode = .byTruncatingTail
        labelField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(labelField)

        // Clear button
        clearButton.bezelStyle = .inline
        clearButton.title = "✕"
        clearButton.font = .systemFont(ofSize: 11, weight: .medium)
        clearButton.target = self
        clearButton.action = #selector(clearPressed)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.isHidden = true
        addSubview(clearButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),

            labelField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            labelField.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -4),
            labelField.centerYAnchor.constraint(equalTo: centerYAnchor),

            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 20),
        ])

        updateLabel()
    }

    // MARK: - Interaction

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        startRecording()
    }

    override func becomeFirstResponder() -> Bool {
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        return true
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        layer?.borderColor = NSColor.separatorColor.cgColor
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        // Require at least one modifier key
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let carbonMods = HotkeyKeymap.carbonModifiers(from: modifiers)
        guard carbonMods != 0 else { return }

        let keyCode = UInt32(event.keyCode)
        onChange?(keyCode, carbonMods)
        configure(displayString: HotkeyKeymap.displayString(keyCode: keyCode, modifiers: carbonMods))
        stopRecording()
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else { return }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let symbols = HotkeyKeymap.modifierSymbols(from: modifiers)
        labelField.stringValue = symbols.isEmpty ? L.pressHotkey : symbols
    }

    // MARK: - Private

    private func startRecording() {
        isRecording = true
        labelField.stringValue = L.pressHotkey
        labelField.textColor = .secondaryLabelColor
        clearButton.isHidden = true
    }

    private func stopRecording() {
        isRecording = false
        updateLabel()
    }

    private func updateLabel() {
        if let display = currentDisplay, !display.isEmpty {
            labelField.stringValue = display
            labelField.textColor = .labelColor
            clearButton.isHidden = false
        } else {
            labelField.stringValue = isRecording ? L.pressHotkey : L.clickToRecordHotkey
            labelField.textColor = .tertiaryLabelColor
            clearButton.isHidden = true
        }
    }

    @objc private func clearPressed() {
        currentDisplay = nil
        onClear?()
        updateLabel()
    }
}
