import SwiftUI

/// Keeps the live conversation visible to the right as the sidebar slides in.
@MainActor final class SidebarDrawer: UIViewController, UIGestureRecognizerDelegate {
    private let panel: UIHostingController<ConsoleNavigator>
    private weak var conversation: UIView?
    private let backdrop = UIButton(type: .custom)
    private var onDismiss: (() -> Void)?
    private var progress: CGFloat = 0
    private var closing = false

    init(panel: ConsoleNavigator, conversation: UIView, onDismiss: @escaping () -> Void) {
        self.panel = UIHostingController(rootView: panel)
        self.conversation = conversation
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.accessibilityViewIsModal = true
        backdrop.backgroundColor = .black
        backdrop.isAccessibilityElement = false // The panel has its own accessible close button.
        backdrop.accessibilityIdentifier = "navigation.backdrop"
        backdrop.addAction(UIAction { [weak self] _ in self?.settle(open: false) }, for: .touchUpInside)
        backdrop.frame = view.bounds
        backdrop.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(backdrop)
        addChild(panel)
        view.addSubview(panel.view)
        panel.didMove(toParent: self)
        let swipe = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
        swipe.delegate = self
        view.addGestureRecognizer(swipe)
    }

    private var width: CGFloat { view.bounds.width * 0.55 }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        panel.view.bounds.size = CGSize(width: width, height: view.bounds.height)
        panel.view.center = CGPoint(x: width / 2, y: view.bounds.midY)
        apply(progress)
    }

    func track(openingDistance: CGFloat) {
        guard width > 0 else { return }
        apply(openingDistance / width)
    }

    private func apply(_ value: CGFloat) {
        progress = min(1, max(0, value))
        panel.view.transform = CGAffineTransform(translationX: (progress - 1) * width, y: 0)
        conversation?.transform = CGAffineTransform(translationX: progress * width, y: 0)
        backdrop.alpha = progress * 0.24
    }

    func settle(open: Bool, animated: Bool = true) {
        guard onDismiss != nil, !closing || !animated else { return }
        closing = !open
        let target: CGFloat = open ? 1 : 0
        guard animated, !UIAccessibility.isReduceMotionEnabled, view.window != nil else {
            UIView.performWithoutAnimation { apply(target) }
            didSettle(open: open)
            return
        }
        UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
            self.apply(target)
        } completion: { _ in self.didSettle(open: open) }
    }

    private func didSettle(open: Bool) {
        guard closing == !open, let onDismiss else { return }
        if open {
            UIAccessibility.post(notification: .screenChanged, argument: panel.view)
        } else {
            self.onDismiss = nil
            onDismiss()
        }
    }

    private func finishPan(velocity: CGFloat) {
        let projected = progress + velocity * 0.16 / width
        settle(open: projected >= 0.5)
    }

    func finishOpening(_ pan: UIScreenEdgePanGestureRecognizer) {
        if pan.state == .ended { finishPan(velocity: pan.velocity(in: view).x) }
        else { settle(open: false) }
    }

    @objc private func pan(_ gesture: UIPanGestureRecognizer) {
        guard !closing else { return }
        switch gesture.state {
        case .changed: apply(1 + gesture.translation(in: view).x / width)
        case .ended: finishPan(velocity: gesture.velocity(in: view).x)
        case .cancelled: settle(open: true)
        default: break
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard !closing, progress == 1, let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
        let velocity = pan.velocity(in: view)
        return velocity.x < -abs(velocity.y)
    }

    override func accessibilityPerformEscape() -> Bool { settle(open: false); return true }
}
