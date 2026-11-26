import SwiftUI

struct ConsoleSettings: Decodable {
    struct Identity: Decodable {
        let name: String
        let avatar: URL?
    }
    struct Control: Decodable, Identifiable {
        let id, sourceID, label, kind: String
        let selected, disabled, danger: Bool
    }
    struct Row: Decodable, Identifiable {
        let id, title, detail: String
        let values: [String]
        let avatar: URL?
        let controls: [Control]
    }
    struct Choices: Decodable {
        let title, close: String
        let options: [Control]
    }
    let title, section, close, theme: String
    let overview, hosted: Bool
    let identity: Identity
    let canvas: [CGFloat]?
    let sections, actions: [Control]
    let rows: [Row]
    let alerts: [String]
    let picker: Choices?

    var showsWebContent: Bool { hosted && !overview }

    var accountPreferences: [Row] {
        guard section == "settings-panel-account", let account = sections.first(where: { $0.sourceID == "settings-tab-account" }),
              rows.first?.title == account.label else { return [] }
        return rows.dropFirst().filter { row in
            row.controls.contains { $0.kind == "toggle" } ||
                (row.controls.isEmpty && !row.detail.isEmpty && !row.values.isEmpty)
        }
    }
}

struct ConsoleSettingsScreen: View {
    let page: ConsoleSettings
    let overview: () -> Void
    let perform: (String) -> Void

    private enum Level: Hashable { case section, choices }

    private var path: Binding<[Level]> {
        let levels: [Level] = page.overview ? [] : page.picker == nil ? [.section] : [.section, .choices]
        return Binding(get: { levels }, set: { newPath in
            guard newPath.count < levels.count else { return }
            if newPath.isEmpty { overview() }
            else if let picker = page.picker { perform(picker.close) }
        })
    }

    private var hostedBackground: Color {
        guard let rgb = page.canvas, rgb.count == 3 else { return Color(uiColor: .systemBackground) }
        return Color(red: rgb[0]/255, green: rgb[1]/255, blue: rgb[2]/255)
    }

    var body: some View {
        NavigationStack(path: path) {
            settingsHome
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { perform(page.close) } label: { Label("Close", systemImage: "xmark") }
                            .accessibilityIdentifier("settings.close")
                    }
                }
                .navigationDestination(for: Level.self) { level in
                    Group {
                        if page.showsWebContent {
                            hostedBackground
                                .toolbarBackground(hostedBackground, for: .navigationBar)
                                .toolbarBackground(.visible, for: .navigationBar)
                        } else {
                            form(choices: level == .choices ? page.picker : nil)
                        }
                    }
                    .navigationTitle(Text(verbatim: level == .choices ? page.picker?.title ?? page.title : page.title))
                    .navigationBarTitleDisplayMode(.inline)
                }
        }
    }

    private var settingsHome: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let account = page.sections.first(where: { $0.sourceID == "settings-tab-account" }) {
                    sectionButton(account, account: true)
                        .consoleGlass(in: RoundedRectangle(cornerRadius: 23))
                }
                let others = page.sections.filter { $0.sourceID != "settings-tab-account" }
                if !others.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(others) { section in
                            sectionButton(section, account: false)
                            if section.id != others.last?.id { Divider().padding(.leading, 56) }
                        }
                    }.consoleGlass(in: RoundedRectangle(cornerRadius: 23))
                }
                if !page.accountPreferences.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(page.accountPreferences) { row in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(verbatim: row.title)
                                    Spacer()
                                    actions(row.controls)
                                }
                                if !row.detail.isEmpty {
                                    Text(verbatim: row.detail).font(.footnote).foregroundStyle(.secondary)
                                }
                                ForEach(Array(row.values.enumerated()), id: \.offset) { _, value in
                                    Text(verbatim: value).font(.footnote).foregroundStyle(.secondary)
                                }
                            }.padding(16)
                            if row.id != page.accountPreferences.last?.id { Divider().padding(.leading, 16) }
                        }
                    }.consoleGlass(in: RoundedRectangle(cornerRadius: 23))
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func sectionButton(_ section: ConsoleSettings.Control, account: Bool) -> some View {
        Button { perform(section.id) } label: {
            HStack(spacing: 12) {
                if account && !page.identity.name.isEmpty {
                    AccountAvatar(name: page.identity.name, url: page.identity.avatar)
                } else {
                    Image(systemName: symbol(for: section.sourceID)).frame(width: 32)
                }
                Text(verbatim: section.label)
                Spacer(minLength: 8)
                if account && !page.identity.name.isEmpty {
                    Text(verbatim: page.identity.name).font(.subheadline).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.tail)
                }
                Image(systemName: "chevron.forward").font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary).accessibilityHidden(true)
            }
            .padding(.horizontal, 16).padding(.vertical, 8).frame(minHeight: 54).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(section.disabled).accessibilityIdentifier(section.sourceID)
    }

    private func symbol(for id: String) -> String {
        switch id {
        case "settings-tab-account": "person.crop.circle"
        case "settings-tab-general": "slider.horizontal.3"
        case "settings-tab-devices": "desktopcomputer"
        case "settings-tab-archived-chats": "archivebox"
        case "settings-tab-engine": "cpu"
        default: "gearshape"
        }
    }

    private func form(choices: ConsoleSettings.Choices?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let picker = choices {
                    VStack(spacing: 0) {
                        ForEach(picker.options) { option in
                            Button { perform(option.id) } label: {
                                HStack {
                                    Text(verbatim: option.label)
                                    Spacer()
                                    if option.selected { Image(systemName: "checkmark").foregroundStyle(.tint) }
                                }.padding(.horizontal, 16).frame(minHeight: 50).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).disabled(option.disabled)
                            .accessibilityAddTraits(option.selected ? .isSelected : [])
                            if option.id != picker.options.last?.id { Divider().padding(.leading, 16) }
                        }
                    }.consoleGlass(in: RoundedRectangle(cornerRadius: 20))
                } else {
                    if !page.actions.isEmpty {
                        ViewThatFits(in: .horizontal) {
                            HStack { actions(page.actions) }
                            VStack(alignment: .leading) { actions(page.actions) }
                        }
                    }
                    let preferences = Set(page.accountPreferences.map(\.id))
                    ForEach(page.rows.filter { !preferences.contains($0.id) }) { row in
                        VStack(alignment: .leading, spacing: 9) {
                            Text(verbatim: row.title).font(.headline)
                            if !row.detail.isEmpty {
                                Text(verbatim: row.detail).font(.subheadline).foregroundStyle(.secondary)
                            }
                            if !row.values.isEmpty || row.avatar != nil {
                                HStack {
                                    if let url = row.avatar {
                                        AccountAvatar(name: row.values.first ?? "", url: url)
                                    }
                                    ForEach(Array(row.values.enumerated()), id: \.offset) { _, value in
                                        Text(verbatim: value)
                                    }
                                }
                            }
                            if !row.controls.isEmpty && row.controls.allSatisfy({ $0.kind == "segment" }) {
                                Picker(row.title, selection: Binding(
                                    get: { row.controls.first { $0.selected }?.id ?? "" }, set: perform)) {
                                    ForEach(row.controls) { c in Text(verbatim: c.label).tag(c.id) }
                                }.pickerStyle(.segmented)
                            } else {
                                actions(row.controls)
                            }
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .consoleGlass(in: RoundedRectangle(cornerRadius: 20))
                    }
                    ForEach(Array(page.alerts.enumerated()), id: \.offset) { _, alert in
                        Text(verbatim: alert).foregroundStyle(.red)
                    }
                }
            }.padding(16)
        }
        .id(choices?.close ?? page.section)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    @ViewBuilder private func actions(_ controls: [ConsoleSettings.Control]) -> some View {
        ForEach(controls) { control in
            if control.kind == "toggle" {
                Toggle(control.label, isOn: Binding(get: { control.selected }, set: { _ in perform(control.id) }))
                    .labelsHidden().disabled(control.disabled)
            } else {
                Button(role: control.danger ? .destructive : nil) { perform(control.id) } label: {
                    HStack(spacing: 8) {
                        Text(verbatim: control.label)
                        if control.kind == "picker" { Image(systemName: "chevron.up.chevron.down").font(.caption) }
                    }.padding(.horizontal, 4).frame(minHeight: 32)
                    .foregroundStyle(control.danger ? Color.red : Color.primary)
                }
                .loginButton(prominent: false).disabled(control.disabled)
                .accessibilityIdentifier(control.sourceID.isEmpty ? "" : "settings.control." + control.sourceID)
            }
        }
    }
}
