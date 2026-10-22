//  AppLabels.swift
//  Bobbly/UI — how apps are shown. FamilyControls apps are opaque tokens:
//  `Label(token)` renders the real icon and name. Named apps (Shortcuts
//  engine) use the catalog's SF Symbol as a stand-in icon.

import SwiftUI
import FamilyControls
import ManagedSettings

/// Renders an `UnlockSubject`: token → real app label, name → symbol + name.
struct AppSubjectLabel: View {
    let subject: UnlockSubject
    /// Used for name-less subjects ("this app", study session name).
    let fallbackName: String

    var body: some View {
        switch subject {
        case .application(let token):
            Label(token)
        case .appName(let name):
            Label(name, systemImage: AppCatalog.app(named: name)?.symbol ?? "app.dashed")
        case .studySession:
            Label(fallbackName, systemImage: "book.closed")
        }
    }
}

/// A named app's placeholder icon in a tinted rounded square.
struct AppGlyph: View {
    let systemImage: String
    var tint: Color = Theme.Palette.pond
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Picked FamilyControls apps, shown with their real icons.
struct TokenList: View {
    let tokens: Set<ApplicationToken>
    var limit: Int = 12

    var body: some View {
        let sorted = Array(tokens)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(sorted.prefix(limit), id: \.self) { token in
                Label(token)
                    .font(.body)
                    .foregroundStyle(Theme.Palette.ink)
            }
            if sorted.count > limit {
                Text("and \(sorted.count - limit) more")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.inkSecondary)
            }
        }
    }
}
