import AppKit

final class MenuBarLimitView: NSView {
    private var model: String = "Codex"
    private var plan: String = ""
    private var fiveHour = LimitWindowDisplay(kind: .fiveHour, usedPercent: 0, remainingPercent: 0, resetsAt: nil)
    private var weekly = LimitWindowDisplay(kind: .weekly, usedPercent: 0, remainingPercent: 0, resetsAt: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 260, height: 105)
    }

    func update(with state: RateLimitDisplayState) {
        fiveHour = state.fiveHour
        weekly = state.weekly
        needsDisplay = true
    }

    func configureModel(_ model: String, plan: String) {
        self.model = model
        self.plan = plan
        needsDisplay = true
    }

    func reloadLocalizedText() {
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width
        let pad: CGFloat = 14
        let topSectionY: CGFloat = bounds.height - 44
        let bottomSectionY: CGFloat = bounds.height - 86

        // Header
        let headerAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: NSColor.labelColor
        ]
        let planAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: NSColor.systemBlue
        ]
        let headerStr = NSMutableAttributedString(string: model, attributes: headerAttr)
        if !plan.isEmpty {
            headerStr.append(NSAttributedString(string: " \(plan)", attributes: planAttr))
        }
        headerStr.draw(at: NSPoint(x: pad, y: bounds.height - 20))

        // Sections
        drawSection(fiveHour, at: NSPoint(x: pad, y: topSectionY), width: w - pad * 2)
        drawSection(weekly, at: NSPoint(x: pad, y: bottomSectionY), width: w - pad * 2)
    }

    private func drawSection(_ data: LimitWindowDisplay, at origin: NSPoint, width: CGFloat) {
        let barH: CGFloat = 4
        let barX = origin.x
        let barY = origin.y

        let titleAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let remainAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ]
        let percentAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]

        let remainText = L.remaining
        let maxPercentText = "100%"
        let clamped = min(max(data.remainingPercent, 0), 100)
        let percentText = "\(Int(clamped.rounded()))%"
        let remainSize = (remainText as NSString).size(withAttributes: remainAttr)
        let maxPercentSize = (maxPercentText as NSString).size(withAttributes: percentAttr)

        let barGap: CGFloat = 10
        let textGap: CGFloat = 4
        let barW = max(0, width - barGap - remainSize.width - textGap - maxPercentSize.width)

        // Title
        data.title.draw(at: NSPoint(x: barX, y: barY + 6), withAttributes: titleAttr)

        // Bar background
        let barRect = NSRect(x: barX, y: barY, width: barW, height: barH)
        let bgPath = NSBezierPath(roundedRect: barRect, xRadius: 2, yRadius: 2)
        NSColor.tertiaryLabelColor.setFill()
        bgPath.fill()

        // Bar fill
        let fillW = barW * (clamped / 100)
        if fillW > 0 {
            let fillRect = NSRect(x: barX, y: barY, width: fillW, height: barH)
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 2, yRadius: 2)
            barColor(for: clamped).setFill()
            fillPath.fill()
        }

        // Remaining label
        let remainX = barX + barW + barGap
        remainText.draw(at: NSPoint(x: remainX, y: barY - 2), withAttributes: remainAttr)

        // Percentage
        let percentX = remainX + remainSize.width + textGap
        percentText.draw(at: NSPoint(x: percentX, y: barY - 2), withAttributes: percentAttr)

        // Reset time
        let resetAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ]
        data.resetText.draw(at: NSPoint(x: barX, y: barY - 16), withAttributes: resetAttr)
    }

    private func barColor(for percent: Double) -> NSColor {
        switch percent {
        case 0..<20: return .systemRed
        case 20..<45: return .systemOrange
        default: return .systemGreen
        }
    }
}
