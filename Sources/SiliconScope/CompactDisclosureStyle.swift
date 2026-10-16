//
//  File:      CompactDisclosureStyle.swift
//  Created:   2026-10-16
//  Updated:   2026-10-16
//  Developer: SiliconScope contributors
//  Overview:  Shared disclosure presentation for compact Network and SSD metrics.
//  Notes:     Keeps button keyboard/accessibility behavior; focus is an internal underline.
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
                        .foregroundStyle(Theme.dim)
                        .accessibilityHidden(true)
                    configuration.label.frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
                .padding(.vertical, 1)
                .overlay(alignment: .bottom) {
                    if keyboardFocused {
                        Rectangle().fill(Theme.dim).frame(height: 1)
                    }
                }
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
