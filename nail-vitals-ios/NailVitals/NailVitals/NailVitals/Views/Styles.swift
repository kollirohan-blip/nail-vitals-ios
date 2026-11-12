//
//  Styles.swift
//  NailVitals
//
//  Shared styling: a solid capsule for the main action, a quiet text
//  button for secondary ones, and cards. Flat in both looks: white cards
//  with a hairline edge in Classic, dark gray cards on black in Dark.
//

import SwiftUI

/// Main action: solid capsule; dims when disabled.
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
                .shadow(color: .black.opacity(scheme == .light && isEnabled ? 0.12 : 0),
                        radius: configuration.isPressed ? 4 : 8, y: 3)
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

/// The home side's backdrop: plain light gray in Classic, black in Dark.
struct AppBackground: View {
    var body: some View {
        Theme.background.ignoresSafeArea()
    }
}

/// The safety line every result shows.
struct SafetyNote: View {
    var body: some View {
        Text("A screening aid, not a diagnosis. This tool flags a pattern that may be worth discussing with a doctor. It does not diagnose any condition.")
            .font(.footnote.weight(.medium))
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
    /// A card: white in Classic, dark gray in Dark.
    func glassCard(cornerRadius: CGFloat = 24) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius, kind: .glass))
    }

    /// A card on the camera side's screens; same surface as glassCard.
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
    /// A round control's surface: a white disc with a soft shadow in
    /// Classic, a dark gray disc in Dark.
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
            content.background {
                Circle()
                    .fill(Theme.card)
                    .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1))
            }
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
            case .glass, .panel:
                content
                    .background(Theme.card, in: shape)
                    .overlay(shape.stroke(Color.white.opacity(0.08), lineWidth: 1))
            case .tile:
                content.background(Color.white.opacity(0.06), in: shape)
            }
        }
    }
}
