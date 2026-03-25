import SwiftUI

/// Shared metrics for pill/capsule toolbar controls (macOS).
enum AudidoToolbarButtonMetrics {
    static let font: Font = .callout
    static let horizontalPadding: CGFloat = 12
    static let verticalPadding: CGFloat = 6
}

extension View {
    /// Gray capsule with border — Select, Done, Select all, secondary actions.
    func audidoToolbarNeutralCapsule() -> some View {
        font(AudidoToolbarButtonMetrics.font)
            .padding(.horizontal, AudidoToolbarButtonMetrics.horizontalPadding)
            .padding(.vertical, AudidoToolbarButtonMetrics.verticalPadding)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color(NSColor.separatorColor), lineWidth: 1))
    }

    /// Red capsule, white label — primary record action, destructive bulk actions.
    func audidoToolbarRedCapsule() -> some View {
        font(AudidoToolbarButtonMetrics.font)
            .padding(.horizontal, AudidoToolbarButtonMetrics.horizontalPadding)
            .padding(.vertical, AudidoToolbarButtonMetrics.verticalPadding)
            .foregroundStyle(.white)
            .background(Color.red)
            .clipShape(Capsule())
    }

    /// Outlined capsule on window background — e.g. Upload audio in toolbar.
    func audidoToolbarOutlineCapsule() -> some View {
        font(AudidoToolbarButtonMetrics.font)
            .padding(.horizontal, AudidoToolbarButtonMetrics.horizontalPadding)
            .padding(.vertical, AudidoToolbarButtonMetrics.verticalPadding)
            .foregroundStyle(.primary)
            .background(Color(NSColor.windowBackgroundColor))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color(NSColor.separatorColor), lineWidth: 1))
    }

    /// Filled capsule with arbitrary accent — AI actions, meeting start, etc.
    func audidoToolbarFilledCapsule(background: Color, foreground: Color = .white) -> some View {
        font(AudidoToolbarButtonMetrics.font)
            .padding(.horizontal, AudidoToolbarButtonMetrics.horizontalPadding)
            .padding(.vertical, AudidoToolbarButtonMetrics.verticalPadding)
            .foregroundStyle(foreground)
            .background(background)
            .clipShape(Capsule())
    }
}
