import SwiftUI

final class ConsoleMenuButton: UIButton {
    init(action: UIAction) {
        super.init(frame: .zero)
        var glass: UIButton.Configuration
        if #available(iOS 26.0, *) { glass = .glass() } else { glass = .gray() }
        glass.cornerStyle = .capsule
        glass.contentInsets = .zero
        glass.baseForegroundColor = .label
        let glyph = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 11)).image { _ in
            for bar in [CGRect(x: 0, y: 0, width: 20, height: 2), CGRect(x: 0, y: 9, width: 13, height: 2)] {
                UIBezierPath(roundedRect: bar, cornerRadius: 1).fill()
            }
        }
        glass.image = glyph.withRenderingMode(.alwaysTemplate)
        configuration = glass
        accessibilityIdentifier = "navigation.open"
        accessibilityLabel = String(localized: "Navigation")
        isHidden = true
        addAction(action, for: .primaryActionTriggered)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: min(0, (bounds.width - 44) / 2), dy: min(0, (bounds.height - 44) / 2)).contains(point)
    }
}

/// Shared control surfaces for the iPhone shell, including older iOS versions.
extension View {
    @ViewBuilder func consoleGlass(in shape: some InsettableShape, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }

    @ViewBuilder func loginButton(prominent: Bool) -> some View {
        if #available(iOS 26.0, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }
}
