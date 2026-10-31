import SwiftUI

/// The established Settings badge, shared by settings, profiles and actions.
/// The badge stays compact; the surrounding native row owns the touch target.
struct SettingsActionIcon: View {
    let systemImage: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 9))
            .foregroundStyle(.white)
            .frame(width: 21, height: 21)
            .background(color, in: Circle())
            .accessibilityHidden(true)
    }
}

struct SettingsRowLabel: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label {
            Text(LocalizedStringKey(title))
                .font(.body)
        } icon: {
            SettingsActionIcon(systemImage: systemImage, color: color)
        }
        .labelStyle(.titleAndIcon)
    }
}

/// Keep a stable row in native lists and controls. Instruction previews and
/// accessibility text use a vertical arrangement; ordinary values can wrap.
struct SettingsDetailRow: View {
    let title: String
    let systemImage: String
    let color: Color
    let value: String
    var valueColor: Color = .secondary
    var valueSymbol: String? = nil
    var valueLineLimit: Int? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize || valueLineLimit != nil {
            stacked
        } else {
            HStack(spacing: 12) {
                SettingsRowLabel(title: title, systemImage: systemImage, color: color)
                    .fixedSize()
                Spacer(minLength: 8)
                detail
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsRowLabel(title: title, systemImage: systemImage, color: color)
            detail
                .lineLimit(valueLineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 29)
        }
    }

    private var detail: some View {
        HStack(spacing: 5) {
            if let valueSymbol {
                Image(systemName: valueSymbol)
                    .accessibilityHidden(true)
            }
            Text(value)
        }
        .font(.subheadline)
        .foregroundStyle(valueColor)
    }
}
