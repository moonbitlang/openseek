import SwiftUI

struct ConsoleSkillsBar: View {
    struct Page: Decodable {
        struct Action: Decodable, Identifiable {
            let id, label: String
            let disabled, selected: Bool
        }
        let title, theme: String
        let close: Action
        let refresh: Action?
        let tabs: [Action]
        let detail: Bool
        var height: CGFloat { tabs.isEmpty ? 56 : 104 }
    }

    let page: Page
    let perform: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(verbatim: page.title).font(.headline).lineLimit(1)
                    .padding(.horizontal, 60).accessibilityAddTraits(.isHeader)
                HStack {
                    icon(page.close, symbol: page.detail ? "chevron.backward" : "xmark", identifier: "skills.close")
                        .accessibilityLabel(page.detail ? Text("Back") : Text(verbatim: page.close.label))
                    Spacer()
                    if let refresh = page.refresh {
                        icon(refresh, symbol: "arrow.clockwise", identifier: "skills.refresh")
                    }
                }
            }
            .frame(height: 56)
            if !page.tabs.isEmpty {
                Picker(page.title, selection: Binding(get: { page.tabs.first { $0.selected }?.id ?? "" }, set: perform)) {
                    ForEach(page.tabs) { tab in
                        Text(verbatim: tab.label).tag(tab.id)
                    }
                }
                .pickerStyle(.segmented)
                .consoleGlass(in: Capsule())
                .frame(height: 48)
            }
        }
        .padding(.horizontal, 16)
        .background(Color(uiColor: .systemBackground))
    }

    private func icon(_ action: Page.Action, symbol: String, identifier: String) -> some View {
        Button { perform(action.id) } label: {
            Image(systemName: symbol).font(.body.weight(.medium))
                .frame(width: 44, height: 44).contentShape(Circle())
        }
        .buttonStyle(.plain).consoleGlass(in: Circle(), interactive: true)
        .disabled(action.disabled).accessibilityLabel(Text(verbatim: action.label))
        .accessibilityIdentifier(identifier)
    }
}
