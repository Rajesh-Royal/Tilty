import AppKit

/// A menu row with a label and an on/off switch, so a setting never looks like a command.
/// The menu stays open after a flip, so you can see the new state.
final class MenuSwitchView: NSView {

    private let toggle = NSSwitch()
    private let onChange: (Bool) -> Void

    init(title: String, isOn: Bool, isEnabled: Bool = true, onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 30))

        let label = NSTextField(labelWithString: title)
        label.font = .menuFont(ofSize: 0)
        label.textColor = isEnabled ? .labelColor : .disabledControlTextColor
        label.lineBreakMode = .byTruncatingTail

        toggle.controlSize = .small
        toggle.state = isOn ? .on : .off
        toggle.isEnabled = isEnabled
        toggle.target = self
        toggle.action = #selector(flipped)
        toggle.setAccessibilityLabel(title)

        for view in [label, toggle] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            toggle.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 12),
            toggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            toggle.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// A click anywhere on the row flips the switch, which is easier to hit on a trackpad.
    override func mouseUp(with event: NSEvent) {
        guard toggle.isEnabled else { return }
        toggle.state = toggle.state == .on ? .off : .on
        flipped()
    }

    @objc private func flipped() {
        onChange(toggle.state == .on)
    }
}
