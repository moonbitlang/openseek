import SwiftUI
import WebKit

@MainActor final class ConsoleNavigation: NSObject, WKScriptMessageHandler, UIGestureRecognizerDelegate {
    private weak var parent: ConsoleController?
    private weak var web: WKWebView?
    private var menuButton: UIButton?
    private var menuBounds: CGRect?
    private var composerGlass: UIVisualEffectView?
    private var composerLayout: (leading: NSLayoutConstraint, bottom: NSLayoutConstraint,
                                 width: NSLayoutConstraint, height: NSLayoutConstraint)?
    private var settings: UIHostingController<ConsoleSettingsScreen>?
    private var skillsBar: UIHostingController<ConsoleSkillsBar>?
    private var settingsCoversPage: Bool { settings?.rootView.page.showsWebContent == false }
    private var welcome: UIHostingController<WelcomeScreen>?
    private var drawer: SidebarDrawer?
    private lazy var edge = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(panFromEdge(_:)))
    private var model: NavigationModel?
    private var acting = false

    func attach(to parent: ConsoleController, web: WKWebView) {
        self.parent = parent
        self.web = web
        if let container = web.superview {
            let button = ConsoleMenuButton(action: UIAction { [weak self] _ in self?.openDrawer()?.settle(open: true) })
            container.addSubview(button)
            menuButton = button
        }
        if #available(iOS 26.0, *), let container = web.superview {
            let glass = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
            glass.cornerConfiguration = .uniformCorners(radius: 22)
            glass.isUserInteractionEnabled = false
            glass.accessibilityIdentifier = "composer.glass"
            glass.isHidden = true
            glass.translatesAutoresizingMaskIntoConstraints = false
            container.insertSubview(glass, belowSubview: web)
            composerGlass = glass
            let safe = parent.inputViewport
            let layout = (leading: glass.leftAnchor.constraint(equalTo: safe.leftAnchor),
                          bottom: glass.bottomAnchor.constraint(equalTo: safe.bottomAnchor),
                          width: glass.widthAnchor.constraint(equalToConstant: 0),
                          height: glass.heightAnchor.constraint(equalToConstant: 0))
            composerLayout = layout
            NSLayoutConstraint.activate([layout.leading, layout.bottom, layout.width, layout.height])
        }
        edge.edges = .left
        edge.delegate = self
        edge.isEnabled = false
        parent.view.addGestureRecognizer(edge)
        NotificationCenter.default.addObserver(self, selector: #selector(updateTransparency),
            name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil)
        guard let url = Bundle.main.url(forResource: "ConsoleNavigation", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8),
              let cssURL = Bundle.main.url(forResource: "ConsoleMobile", withExtension: "css"),
              let css = try? String(contentsOf: cssURL, encoding: .utf8),
              let surfacesURL = Bundle.main.url(forResource: "ConsoleSurfaces", withExtension: "js"),
              let surfaces = try? String(contentsOf: surfacesURL, encoding: .utf8),
              let options = try? JSONSerialization.data(withJSONObject: ["style": css, "nativeMenu": menuButton != nil,
                  "glassMenu": composerGlass != nil]) else { return }
        let script = "((mobile) => {\n" + surfaces + "\n" + source + "\n})(" + String(decoding: options, as: UTF8.self) + ");"
        let scripts = web.configuration.userContentController
        scripts.add(self, contentWorld: .defaultClient, name: "consoleNavigation")
        scripts.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.webView === web,
              Console.isPage(message.frameInfo.request.url), Console.isPage(web?.url),
              let body = message.body as? [String: Any], let event = body["event"] as? String else { return }
        if event == "ready" {
            updateTransparency()
            parent?.consoleDidRender()
            return
        }
        if event == "login", let visible = body["visible"] as? Bool {
            if visible { parent?.retireAccountIfSignedOut() }
            showWelcome(visible)
            return
        }
        if event == "composer" {
            updateComposer(body["data"] as? [String: Any])
            return
        }
        if event == "settings" {
            let data = body["data"] as? [String: Any]
            let page = data.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
                .flatMap { try? JSONDecoder().decode(ConsoleSettings.self, from: $0) }
            showSettings(page)
            return
        }
        if event == "skills" {
            let page = (body["data"] as? [String: Any]).flatMap { try? JSONSerialization.data(withJSONObject: $0) }
                .flatMap { try? JSONDecoder().decode(ConsoleSkillsBar.Page.self, from: $0) }
            showSkillsBar(page)
            return
        }
        guard event == "open" || event == "update" else { return }
        guard let data = body["data"] as? [String: Any],
              let json = try? JSONSerialization.data(withJSONObject: data),
              let catalog = try? JSONDecoder().decode(ConsoleCatalog.self, from: json) else {
            resetCatalog()
            if event == "open" { perform("webSidebar", nil) }
            return
        }
        if let model { model.catalog = catalog }
        else { model = NavigationModel(catalog) }
        if event == "update", let menuButton {
            let commands = body["commands"] as? [String] ?? []
            if commands != (menuButton.menu?.children.map(\.title) ?? []) {
                let actions = commands.map { title in
                    UIAction(title: title) { [weak self] _ in self?.perform("header", title) }
                }
                menuButton.menu = actions.isEmpty ? nil : UIMenu(children: actions)
                menuButton.accessibilityHint = actions.isEmpty ? nil : String(localized: "Touch and hold for conversation actions.")
            }
            if let frame = body["menu"] as? [String: Any], let x = frame["x"] as? CGFloat,
               let y = frame["y"] as? CGFloat, let size = frame["size"] as? CGFloat {
                menuBounds = CGRect(x: x, y: y, width: size, height: size)
                let covered = frame["covered"] as? Bool == true
                if menuButton.isUserInteractionEnabled == covered, let web, let container = web.superview {
                    // Let WebKit draw the modal scrim over the actual glass button.
                    if covered { container.insertSubview(menuButton, belowSubview: web) }
                    else { container.insertSubview(menuButton, aboveSubview: web) }
                    menuButton.isUserInteractionEnabled = !covered
                    menuButton.isAccessibilityElement = !covered
                }
                switch body["theme"] as? String {
                case "dark": menuButton.overrideUserInterfaceStyle = .dark
                case "light": menuButton.overrideUserInterfaceStyle = .light
                default: menuButton.overrideUserInterfaceStyle = .unspecified
                }
            } else { menuBounds = nil }
            layoutControls()
        }
        edge.isEnabled = menuButton?.isUserInteractionEnabled != false
        if event == "open" { openDrawer()?.settle(open: true) }
    }

    func layoutControls() {
        guard let web else { return }
        if let skillsBar, let parent {
            let frame = parent.view.safeAreaLayoutGuide.layoutFrame
            skillsBar.view.frame = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: skillsBar.rootView.page.height)
        }
        if let host = settings, let view = parent?.view {
            host.view.frame = host.rootView.page.showsWebContent ?
                CGRect(x: 0, y: view.safeAreaInsets.top, width: view.bounds.width, height: 56) : view.bounds
        }
        let inset = web.scrollView.adjustedContentInset
        menuButton?.isHidden = menuBounds == nil
        if let menuBounds {
            menuButton?.frame = web.convert(menuBounds.offsetBy(dx: inset.left, dy: inset.top), to: menuButton?.superview)
        }
    }

    private func updateComposer(_ data: [String: Any]?) {
        guard let web, let glass = composerGlass, let layout = composerLayout else { return }
        if let data, let x = data["x"] as? CGFloat, let bottom = data["bottom"] as? CGFloat,
           let width = data["width"] as? CGFloat, let height = data["height"] as? CGFloat,
           let rgb = data["color"] as? [CGFloat], rgb.count == 3 {
            layout.leading.constant = x
            layout.bottom.constant = -bottom
            layout.width.constant = width
            layout.height.constant = height
            let color = UIColor(red: rgb[0]/255, green: rgb[1]/255, blue: rgb[2]/255, alpha: 1)
            parent?.setComposerCanvas(color, dialogDim: data["dialogDim"] as? CGFloat)
            switch data["appearance"] as? String {
            case "dark": web.overrideUserInterfaceStyle = .dark
            case "light": web.overrideUserInterfaceStyle = .light
            default: web.overrideUserInterfaceStyle = .unspecified
            }
            if glass.isHidden {
                web.isOpaque = false
                web.backgroundColor = .clear
                web.underPageBackgroundColor = .clear
            }
            glass.overrideUserInterfaceStyle = data["theme"] as? String == "dark" ? .dark : .light
            glass.isHidden = false
        } else if !glass.isHidden {
            glass.isHidden = true
            web.isOpaque = true
            web.backgroundColor = nil
            web.underPageBackgroundColor = nil
            web.overrideUserInterfaceStyle = .unspecified
            parent?.setComposerCanvas(nil)
        }
    }

    private func showSkillsBar(_ page: ConsoleSkillsBar.Page?) {
        guard let parent else { return }
        guard let page else {
            guard let skillsBar else { return }
            skillsBar.willMove(toParent: nil)
            skillsBar.view.removeFromSuperview()
            skillsBar.removeFromParent()
            self.skillsBar = nil
            return
        }
        let bar = ConsoleSkillsBar(page: page) { [weak self] id in
            self?.web?.callAsyncJavaScript("return window.consoleSkillsAction?.(id)", arguments: ["id": id],
                in: nil, in: .defaultClient, completionHandler: nil)
        }
        if let skillsBar {
            skillsBar.rootView = bar
        } else {
            let host = UIHostingController(rootView: bar)
            host.safeAreaRegions = []
            parent.addChild(host)
            parent.view.addSubview(host.view)
            host.didMove(toParent: parent)
            skillsBar = host
        }
        skillsBar?.overrideUserInterfaceStyle = page.theme == "dark" ? .dark : page.theme == "light" ? .light : .unspecified
        layoutControls()
    }

    private func showSettings(_ page: ConsoleSettings?) {
        guard let parent else { return }
        guard let page else {
            guard let settings else { return }
            settings.willMove(toParent: nil)
            settings.view.removeFromSuperview()
            settings.removeFromParent()
            self.settings = nil
            parent.conversationView.accessibilityElementsHidden = drawer != nil || welcome != nil
            return
        }
        let screen = ConsoleSettingsScreen(page: page, overview: { [weak self] in
            self?.web?.callAsyncJavaScript("window.consoleSettingsOverview?.()", arguments: [:],
                in: nil, in: .defaultClient, completionHandler: nil)
        }) { [weak self] id in
            self?.web?.callAsyncJavaScript("return window.consoleSettingsAction?.(id)", arguments: ["id": id],
                in: nil, in: .defaultClient, completionHandler: nil)
        }
        if let settings {
            settings.rootView = screen
        } else {
            let host = UIHostingController(rootView: screen)
            parent.addChild(host)
            parent.view.addSubview(host.view)
            host.didMove(toParent: parent)
            settings = host
            UIAccessibility.post(notification: .screenChanged, argument: host.view)
        }
        layoutControls()
        settings?.view.accessibilityViewIsModal = !page.showsWebContent
        parent.conversationView.accessibilityElementsHidden = !page.showsWebContent || drawer != nil || welcome != nil
        settings?.overrideUserInterfaceStyle = page.theme == "dark" ? .dark : page.theme == "light" ? .light : .unspecified
    }

    func reset() {
        updateComposer(nil)
        showSkillsBar(nil)
        showSettings(nil)
        resetCatalog()
        showWelcome(false)
    }

    @objc private func updateTransparency() {
        guard let web, Console.isPage(web.url) else { return }
        web.callAsyncJavaScript("document.documentElement.toggleAttribute('data-ios-opaque', reduce)",
            arguments: ["reduce": UIAccessibility.isReduceTransparencyEnabled], in: nil, in: .defaultClient,
            completionHandler: nil)
    }

    func showWelcome(_ visible: Bool) {
        guard let parent else { return }
        if !visible {
            welcome?.willMove(toParent: nil)
            welcome?.view.removeFromSuperview()
            welcome?.removeFromParent()
            welcome = nil
            parent.conversationView.accessibilityElementsHidden = drawer != nil || settingsCoversPage
        } else if welcome == nil {
            resetCatalog()
            let host = UIHostingController(rootView: WelcomeScreen { [weak parent] method in parent?.beginSignIn(method: method) })
            parent.addChild(host)
            host.view.translatesAutoresizingMaskIntoConstraints = false
            parent.view.addSubview(host.view)
            NSLayoutConstraint.activate([
                host.view.topAnchor.constraint(equalTo: parent.view.topAnchor),
                host.view.bottomAnchor.constraint(equalTo: parent.view.bottomAnchor),
                host.view.leadingAnchor.constraint(equalTo: parent.view.leadingAnchor),
                host.view.trailingAnchor.constraint(equalTo: parent.view.trailingAnchor)
            ])
            host.didMove(toParent: parent)
            welcome = host
            parent.conversationView.accessibilityElementsHidden = true
            UIAccessibility.post(notification: .screenChanged, argument: host.view)
        }
    }

    private func resetCatalog() {
        model = nil
        menuBounds = nil
        menuButton?.isHidden = true
        edge.isEnabled = false
        drawer?.settle(open: false, animated: false)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        drawer == nil && welcome == nil && parent?.presentedViewController == nil && model != nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === edge, let web, let otherView = other.view else { return false }
        // Give a drag starting on the left edge to the sidebar. WebKit keeps
        // its other gestures, including navigation from the opposite edge.
        return other is UIPanGestureRecognizer && otherView.isDescendant(of: web)
    }

    @objc private func panFromEdge(_ gesture: UIScreenEdgePanGestureRecognizer) {
        let distance = gesture.translation(in: parent?.view).x
        switch gesture.state {
        case .began: openDrawer()?.track(openingDistance: distance)
        case .changed: drawer?.track(openingDistance: distance)
        case .ended, .cancelled, .failed: drawer?.finishOpening(gesture)
        default: break
        }
    }

    private func openDrawer() -> SidebarDrawer? {
        guard let parent, let web, let model, parent.presentedViewController == nil,
              drawer == nil, welcome == nil else { return nil }
        parent.view.endEditing(true)
        let panel = ConsoleNavigator(model: model, perform: { [weak self] action, id in
            self?.perform(action, id)
        }, close: { [weak self] in self?.drawer?.settle(open: false) })
        let host = SidebarDrawer(panel: panel, conversation: parent.conversationView) { [weak self] in
            guard let self, let drawer else { return }
            drawer.willMove(toParent: nil)
            drawer.view.removeFromSuperview()
            drawer.removeFromParent()
            self.drawer = nil
            self.parent?.conversationView.accessibilityElementsHidden = self.welcome != nil || self.settingsCoversPage
            if self.settings == nil {
                UIAccessibility.post(notification: .screenChanged, argument: self.menuButton?.isHidden == false ? self.menuButton : web)
            }
        }
        host.overrideUserInterfaceStyle = menuButton?.overrideUserInterfaceStyle ?? .unspecified
        drawer = host
        parent.addChild(host)
        host.view.frame = parent.view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        parent.view.addSubview(host.view)
        host.didMove(toParent: parent)
        host.view.layoutIfNeeded()
        parent.conversationView.accessibilityElementsHidden = true
        return host
    }

    private func perform(_ action: String, _ id: String?) {
        guard !acting, let web else { return }
        acting = true
        Task {
            defer { acting = false }
            let result = try? await web.callAsyncJavaScript(
                "return window.consoleNavigationAction?.(action, id) ?? false",
                arguments: ["action": action, "id": id ?? ""], in: nil, contentWorld: .defaultClient)
            if result as? Bool == true {
                if action != "more" && action != "retry" { drawer?.settle(open: false) }
            } else if let drawer, drawer.presentedViewController == nil {
                let alert = UIAlertController(title: String(localized: "This item is no longer available."), message: nil, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                drawer.present(alert, animated: true)
            }
        }
    }
}
