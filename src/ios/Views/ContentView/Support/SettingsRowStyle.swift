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
    }
}

/// Short values align on the trailing edge; longer values move beneath the
/// label instead of squeezing the title or disappearing at accessibility sizes.
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
        if dynamicTypeSize.isAccessibilitySize {
            stacked
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    SettingsRowLabel(title: title, systemImage: systemImage, color: color)
                        .fixedSize()
                    Spacer(minLength: 8)
                    detail.fixedSize()
                }
                stacked
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
