//
//  File:      CompactDisclosureStyle.swift
//  Created:   2026-10-16
//  Updated:   2026-10-16
//  Developer: SiliconScope contributors
//  Overview:  Shared disclosure presentation for compact Network and SSD metrics.
//  Notes:     Keeps button keyboard/accessibility behavior; focus changes only the chevron/title tint.
//             The local style avoids a native focus-ring outset at a popover boundary.
//
import SwiftUI

struct CompactDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        CompactDisclosureBody(configuration: configuration)
    }
}

private struct CompactDisclosureBody: View {
    let configuration: DisclosureGroupStyleConfiguration
    @FocusState private var keyboardFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.hair) {
            Button { configuration.isExpanded.toggle() } label: {
                HStack(spacing: Space.hair) {
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundStyle(keyboardFocused ? Theme.text : Theme.dim)
                        .accessibilityHidden(true)
                    configuration.label
                        .foregroundStyle(keyboardFocused ? Theme.text : Theme.dim)
                        .environment(\.compactDisclosureFocused, keyboardFocused)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
                .padding(.vertical, 1)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .focused($keyboardFocused)
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Expand or collapse details")
            if configuration.isExpanded { configuration.content }
        }
    }
}

private struct CompactDisclosureFocusKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var compactDisclosureFocused: Bool {
        get { self[CompactDisclosureFocusKey.self] }
        set { self[CompactDisclosureFocusKey.self] = newValue }
    }
}

/// A title-only focus cue: adjacent addresses and metric values keep their original color.
struct CompactDisclosureTitle: View {
    let title: String
    @Environment(\.compactDisclosureFocused) private var focused

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title).foregroundStyle(focused ? Theme.text : Theme.dim)
    }
}
