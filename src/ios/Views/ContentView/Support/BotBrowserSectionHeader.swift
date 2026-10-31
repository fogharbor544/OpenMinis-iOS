import SwiftUI

/// Keep the browser's relative time whole while the Bot's name can truncate.
/// Accessibility sizes place the metadata on separate lines beside the menu.
struct BotBrowserSectionHeader<Actions: View>: View {
    let title: String
    let status: String?
    let isRunning: Bool
    private let actions: Actions
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(title: String, status: String?, isRunning: Bool, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.status = status
        self.isRunning = isRunning
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).lineLimit(2)
                    statusBadge
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                statusBadge
            }
            Menu { actions } label: {
                Image(systemName: "ellipsis")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("浏览器选项")
        }
        .textCase(nil)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if let status {
            let color: Color = isRunning ? .green : .secondary
            Text(status)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(color.opacity(0.15), in: Capsule())
                .fixedSize()
        }
    }
}
