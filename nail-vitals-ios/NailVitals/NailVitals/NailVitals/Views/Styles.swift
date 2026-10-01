//
//  Styles.swift
//  NailVitals
//
//  Shared neon medical-tech styling: a glowing capsule for the main action,
//  a quiet text button for secondary ones, and a frosted-glass panel.
//

import SwiftUI

/// Main action: solid glowing capsule; dims when disabled.
struct GlowButtonStyle: ButtonStyle {
    var color: Color = Theme.aligned

    func makeBody(configuration: Configuration) -> some View {
        GlowButtonBody(configuration: configuration, color: color)
    }

    private struct GlowButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let color: Color
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.black)
                .padding(.horizontal, 28)
                .padding(.vertical, 13)
                .background(Capsule().fill(color))
                .shadow(color: color.opacity(isEnabled ? 0.6 : 0), radius: configuration.isPressed ? 4 : 12)
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .opacity(isEnabled ? 1 : 0.4)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
        }
    }
}

/// Secondary action: plain text that dims while pressed.
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white.opacity(configuration.isPressed ? 0.5 : 0.85))
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
    }
}

extension View {
    /// Frosted-glass card with a faint edge highlight.
    func glassPanel(cornerRadius: CGFloat = 20) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}
