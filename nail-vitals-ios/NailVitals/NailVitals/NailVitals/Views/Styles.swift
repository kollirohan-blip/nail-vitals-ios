//
//  Styles.swift
//  NailVitals
//
//  Shared styling: a solid capsule for the main action, a quiet text
//  button for secondary ones, and cards. Dark uses glowing color and glass;
//  Classic (white) uses plain white cards with a hairline edge.
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
        @Environment(\.colorScheme) private var scheme

        var body: some View {
            configuration.label
                .font(.system(size: 16, weight: .semibold))
                // Bright fills in Dark take black text; deep fills in Classic, white.
                .foregroundColor(scheme == .dark ? .black : .white)
                .padding(.horizontal, 28)
                .padding(.vertical, 13)
                .background(Capsule().fill(color))
                .shadow(color: scheme == .dark ? color.opacity(isEnabled ? 0.6 : 0) : .black.opacity(isEnabled ? 0.12 : 0),
                        radius: configuration.isPressed ? 4 : (scheme == .dark ? 12 : 8),
                        y: scheme == .dark ? 0 : 3)
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
            .foregroundColor(.primary.opacity(configuration.isPressed ? 0.5 : 0.85))
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
    }
}

/// The home side's backdrop: graphite with faint emerald and violet glows
/// in Dark; plain light gray in Classic.
struct AppBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            if scheme == .dark {
                Color(red: 0.055, green: 0.06, blue: 0.075)
                RadialGradient(colors: [Theme.aligned.opacity(0.10), .clear], center: .topLeading, startRadius: 20, endRadius: 460)
                RadialGradient(colors: [Theme.violet.opacity(0.14), .clear], center: .bottomTrailing, startRadius: 20, endRadius: 500)
            } else {
                Color(red: 0.953, green: 0.953, blue: 0.965)   // #F3F3F6
            }
        }
        .ignoresSafeArea()
    }
}

/// The safety line every result shows.
struct SafetyNote: View {
    var body: some View {
        Text("This tool flags a pattern that may be worth discussing with a doctor. It does not diagnose any condition.")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.primary.opacity(0.6))
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
                .foregroundStyle(Color.primary.opacity(0.6))
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.65))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .glassCard()
    }
}

extension View {
    /// Liquid Glass card in Dark (the home side); white card in Classic.
    func glassCard(cornerRadius: CGFloat = 24) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius, kind: .glass))
    }

    /// Frosted-glass card with a faint edge highlight in Dark; white card
    /// in Classic.
    func glassPanel(cornerRadius: CGFloat = 20) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius, kind: .panel))
    }

    /// A small tile inside a screen (sign chips): faint fill in Dark, white
    /// with a hairline edge in Classic.
    func tileBackground(cornerRadius: CGFloat = 14) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius, kind: .tile))
    }
}

extension View {
    /// A round control's surface: interactive glass in Dark; a white disc
    /// with a soft shadow in Classic.
    func roundSurface() -> some View {
        modifier(RoundSurface())
    }
}

private struct RoundSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        if scheme == .light {
            content.background {
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(Color.black.opacity(0.06), lineWidth: 1))
                    .shadow(color: .black.opacity(0.08), radius: 14, y: 5)
            }
        } else {
            content.glassEffect(.regular.interactive(), in: .circle)
        }
    }
}

private struct CardBackground: ViewModifier {
    enum Kind { case glass, panel, tile }

    let cornerRadius: CGFloat
    let kind: Kind
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if scheme == .light {
            content
                .background(Color.white, in: shape)
                .overlay(shape.stroke(Color.black.opacity(0.07), lineWidth: 1))
                .shadow(color: .black.opacity(kind == .tile ? 0 : 0.05), radius: 12, y: 4)
        } else {
            switch kind {
            case .glass:
                content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            case .panel:
                content
                    .background(.ultraThinMaterial, in: shape)
                    .overlay(shape.stroke(Color.white.opacity(0.12), lineWidth: 1))
            case .tile:
                content.background(Color.white.opacity(0.06), in: shape)
            }
        }
    }
}
