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

/// The home side's backdrop: graphite with faint emerald and violet glows.
struct AppBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.06, blue: 0.075)
            RadialGradient(colors: [Theme.aligned.opacity(0.10), .clear], center: .topLeading, startRadius: 20, endRadius: 460)
            RadialGradient(colors: [Theme.violet.opacity(0.14), .clear], center: .bottomTrailing, startRadius: 20, endRadius: 500)
        }
        .ignoresSafeArea()
    }
}

/// The safety line every result shows.
struct SafetyNote: View {
    var body: some View {
        Text("This tool flags a pattern that may be worth discussing with a doctor. It does not diagnose any condition.")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.5))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}

/// A glass card for screens with nothing to show yet.
struct EmptyStateCard: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.white.opacity(0.6))
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .glassCard()
    }
}

extension View {
    /// Liquid Glass card (the home side).
    func glassCard(cornerRadius: CGFloat = 24) -> some View {
        glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }

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
