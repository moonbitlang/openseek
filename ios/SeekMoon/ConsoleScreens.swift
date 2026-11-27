import SwiftUI

struct WelcomeScreen: View {
    let signIn: (SignInMethod) -> Void

    var body: some View {
        GeometryReader { bounds in
            ScrollView {
                VStack(spacing: 36) {
                    VStack(spacing: 16) {
                        Image("WelcomeMark")
                            .resizable().frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 15))
                            .accessibilityHidden(true)
                        Text("Welcome to SeekMoon")
                            .font(.largeTitle.bold()).multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                    }
                    VStack(spacing: 12) {
                        Button { signIn(.email) } label: {
                            Text("Continue with email").frame(maxWidth: .infinity, minHeight: 36)
                        }
                        .loginButton(prominent: true).accessibilityIdentifier("welcome.email")
                        Button { signIn(.github) } label: {
                            Text("Continue with GitHub").frame(maxWidth: .infinity, minHeight: 36)
                        }
                        .loginButton(prominent: false).accessibilityIdentifier("welcome.github")
                    }
                    .controlSize(.large).font(.headline)
                }
                .frame(maxWidth: 400).padding(24)
                .frame(maxWidth: .infinity, minHeight: bounds.size.height)
            }
        }
        .background(Color(uiColor: .systemBackground))
    }
}

struct ConsoleCatalog: Decodable {
    struct Chat: Decodable, Identifiable {
        let id, title: String
        let current: Bool
    }
    struct Project: Decodable, Identifiable {
        let id, title, host: String
        let offline, canCreate, hasMore: Bool
        let chats: [Chat]
    }
    struct Tool: Decodable, Identifiable {
        let id, title: String
        let enabled: Bool
        var symbol: String {
            switch id {
            case "skills": "puzzlepiece.extension"
            case "scheduled": "calendar.badge.clock"
            default: "square.grid.2x2"
            }
        }
    }
    let chats: [Chat]
    let tools: [Tool]
    let projects: [Project]
    let canCreate, canImport, canRetry, inWorkspace: Bool
    let notice, account: String
    let avatar: URL?
}

final class NavigationModel: ObservableObject {
    @Published var catalog: ConsoleCatalog
    init(_ catalog: ConsoleCatalog) { self.catalog = catalog }
}

struct ConsoleNavigator: View {
    @ObservedObject var model: NavigationModel
    let perform: (String, String?) -> Void
    let close: () -> Void
    @State private var showWorkspaces: Bool
    @State private var expandedProject: String?
    @State private var query = ""
    @FocusState private var searching: Bool

    init(model: NavigationModel, perform: @escaping (String, String?) -> Void, close: @escaping () -> Void) {
        self.model = model
        self.perform = perform
        self.close = close
        _showWorkspaces = State(initialValue: model.catalog.inWorkspace)
        _expandedProject = State(initialValue: model.catalog.projects.first { $0.chats.contains(where: \.current) }?.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ViewThatFits(in: .horizontal) {
                    Text(verbatim: "SeekMoon").font(.headline).fixedSize()
                    Image("WelcomeMark").resizable().frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 6)).accessibilityLabel("SeekMoon")
                }.accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button(action: close) {
                    Image(systemName: "sidebar.left").frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .consoleGlass(in: Circle(), interactive: true)
                .accessibilityLabel("Close sidebar").accessibilityIdentifier("navigation.close")
            }
            .padding(.leading, 12).padding(.trailing, 2)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search", text: $query)
                    .accessibilityLabel("Search recent chats")
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .focused($searching).submitLabel(.search).onSubmit { searching = false }
                    .accessibilityIdentifier("navigation.search")
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(minWidth: 44, minHeight: 44)
                    }
                        .accessibilityLabel("Clear search")
                }
            }
            .padding(.leading, 9).padding(.trailing, query.isEmpty ? 8 : 0).frame(minHeight: 44)
            .consoleGlass(in: Capsule())
            .padding(.horizontal, 8).padding(.vertical, 6)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if query.isEmpty {
                        Button { perform("newCloud", nil) } label: { actionLabel("New chat", icon: "square.and.pencil") }
                            .disabled(!model.catalog.canCreate).accessibilityHint("Start a cloud conversation").accessibilityIdentifier("navigation.newCloud")
                        Button { perform("importCloud", nil) } label: {
                            actionLabel("Import conversation", icon: "square.and.arrow.down")
                        }
                        .disabled(!model.catalog.canImport).accessibilityHint("Import into Cloud chats")
                        .accessibilityIdentifier("navigation.importCloud")
                        Button { showWorkspaces.toggle() } label: {
                            HStack {
                                actionLabel("Workspaces", icon: "folder")
                                disclosure(expanded: showWorkspaces)
                            }
                            .contentShape(Rectangle())
                        }
                        .accessibilityValue(showWorkspaces ? Text("Expanded") : Text("Collapsed"))
                        .accessibilityIdentifier("navigation.workspaces")
                        if showWorkspaces { workspaces }
                        ForEach(model.catalog.tools.filter { $0.id != "settings" }) { tool in
                            Button { perform("tool", tool.id) } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: tool.symbol).frame(width: 18)
                                    Text(verbatim: tool.title)
                                }.padding(.horizontal, 7).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                            }.disabled(!tool.enabled).accessibilityIdentifier("navigation." + tool.id)
                        }
                    }
                    Text("Recent chats").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        .padding(.top, 17).padding(.bottom, 4).padding(.horizontal, 11)
                        .accessibilityAddTraits(.isHeader)
                    let recent = model.catalog.chats.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
                    chatRows(recent, identifier: "navigation.recentChat")
                    if !model.catalog.notice.isEmpty {
                        Text(verbatim: model.catalog.notice).font(.callout).foregroundStyle(.secondary).padding(.horizontal, 11)
                        if model.catalog.canRetry { Button("Retry") { perform("retry", nil) }.padding(11) }
                    } else if recent.isEmpty {
                        note(query.isEmpty ? "No cloud conversations yet." : "No matching conversations.")
                    }
                }
                .padding(.horizontal, 4).padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)

            HStack(spacing: 4) {
                if !model.catalog.account.isEmpty {
                    AccountAvatar(name: model.catalog.account, url: model.catalog.avatar)
                    Text(verbatim: model.catalog.account).font(.subheadline.weight(.semibold))
                        .lineLimit(1).truncationMode(.tail)
                        .accessibilityIdentifier("navigation.account")
                }
                Spacer(minLength: 0)
                if let settings = model.catalog.tools.first(where: { $0.id == "settings" }) {
                    Button { perform("tool", settings.id) } label: {
                        Image(systemName: "gearshape").frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .disabled(!settings.enabled).accessibilityLabel(Text(verbatim: settings.title))
                    .accessibilityIdentifier("navigation.settings")
                }
            }
            .padding(.leading, 7).padding(.trailing, 2)
            .consoleGlass(in: Capsule())
            .padding(.horizontal, 6).padding(.vertical, 5)
        }
        .foregroundStyle(.primary).buttonStyle(.plain)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
    }

    @ViewBuilder private var workspaces: some View {
        if model.catalog.projects.isEmpty {
            note("On your Mac, open a project and turn on Remote access with the same account.")
        }
        ForEach(model.catalog.projects) { project in
            Button {
                expandedProject = expandedProject == project.id ? nil : project.id
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: project.title).lineLimit(2)
                        if !project.host.isEmpty { Text(verbatim: project.host).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    if project.offline { Text("Offline").font(.caption).foregroundStyle(.secondary) }
                    disclosure(expanded: expandedProject == project.id)
                }
                .padding(.leading, 11).frame(minHeight: 44).contentShape(Rectangle())
            }
            if expandedProject == project.id {
                VStack(alignment: .leading, spacing: 0) {
                    if project.canCreate {
                        Button { perform("newWork", project.id) } label: { actionLabel("New workspace chat", icon: "square.and.pencil") }
                    }
                    chatRows(project.chats, identifier: "navigation.workspaceChat")
                    if project.hasMore { Button("Show more") { perform("more", project.id) }.padding(10) }
                    if project.chats.isEmpty { note("No conversations in this workspace.") }
                }
                .padding(.leading, 9)
            }
        }
    }

    private func actionLabel(_ title: LocalizedStringKey, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).frame(width: 18)
            Text(title).fontWeight(.medium)
        }.padding(.horizontal, 7).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
    }

    private func disclosure(expanded: Bool) -> some View {
        Image(systemName: expanded ? "chevron.down" : "chevron.right")
            .font(.caption.weight(.medium)).foregroundStyle(.secondary).padding(.trailing, 7).accessibilityHidden(true)
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary).padding(.horizontal, 11).padding(.vertical, 6)
    }

    private func chatRows(_ chats: [ConsoleCatalog.Chat], identifier: String) -> some View {
        ForEach(chats) { chat in
            Button { perform("chat", chat.id) } label: {
                Text(verbatim: chat.title).lineLimit(2).multilineTextAlignment(.leading)
                    .padding(.horizontal, 11).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .background(chat.current ? Color(uiColor: .secondarySystemFill) : .clear, in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
            }
            .accessibilityAddTraits(chat.current ? .isSelected : [])
            .accessibilityIdentifier(identifier)
        }
    }
}

struct AccountAvatar: View {
    let name: String
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Text(verbatim: String(name.prefix(1)).uppercased())
                    .font(.subheadline.bold()).foregroundStyle(.tint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.accentColor.opacity(0.13))
            }
        }.frame(width: 32, height: 32).clipShape(Circle()).accessibilityHidden(true)
    }
}
