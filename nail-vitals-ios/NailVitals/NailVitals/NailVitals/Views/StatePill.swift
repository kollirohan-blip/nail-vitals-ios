//
//  StatePill.swift
//  NailVitals
//
//  How a result state looks everywhere: its color, its icon and its word,
//  together. About 1 in 12 men can't tell the green from the red, so the
//  color never carries the meaning alone.
//

import SwiftUI

extension SignState {
    var color: Color {
        switch self {
        case .typical: return Theme.aligned
        case .measureAgain: return Theme.adjusting
        case .worthDiscussing: return Theme.attention
        case .couldntCheck: return Theme.unmeasured
        }
    }
}

/// The tinted surface behind a state's text: the state color at 12%
/// (Classic) or 18% (Dark) over the card color, so the text keeps its
/// contrast wherever the pill sits.
private struct StateTint<S: Shape>: View {
    let color: Color
    let shape: S
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        shape.fill(Theme.card)
            .overlay(shape.fill(color.opacity(scheme == .dark ? 0.18 : 0.12)))
    }
}

/// A state as a small pill: icon and word in the state color.
struct StatePill: View {
    let state: SignState
    /// Shown instead of the state's own word ("your normal", "not seen").
    var text: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: state.symbol)
                .imageScale(.small)
            Text(text ?? state.label)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(state.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(StateTint(color: state.color, shape: Capsule()))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text ?? state.label)
    }
}

/// The report card's banner: the answer to "is this good or bad?" first.
struct StateBanner: View {
    let state: SignState
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: state.symbol)
                Text(title)
            }
            .font(.title3.weight(.semibold))
            .foregroundStyle(state.color)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(StateTint(color: state.color, shape: RoundedRectangle(cornerRadius: 20, style: .continuous)))
        .accessibilityElement(children: .combine)
    }
}
