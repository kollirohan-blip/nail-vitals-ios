//
//  IntroView.swift
//  NailVitals
//
//  The first-launch intro: three picture cards, one idea each, so someone
//  can scan with nobody there to explain. Also opened from the camera's
//  menu ("How to hold your finger"). The full written guide stays in the
//  Learn tab (PoseGuideView).
//

import SwiftUI

struct IntroView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private let cards: [(title: String, text: String)] = [
        ("Point your index finger up, side-on", "The camera needs the side of your finger, not the flat of your nail."),
        ("Fit it in the frame", "A glow wraps your finger. When it turns green, the photo takes itself."),
        ("Hold steady for 3 photos", "Rest your elbow on a table. It takes about a minute."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") { dismiss() }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .opacity(page < cards.count - 1 ? 1 : 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

            TabView(selection: $page) {
                ForEach(cards.indices, id: \.self) { i in
                    VStack(spacing: 26) {
                        art(i)
                            .frame(height: 280)
                        VStack(spacing: 10) {
                            Text(cards[i].title)
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(.primary)
                            Text(cards[i].text)
                                .font(.system(size: 17))
                                .foregroundStyle(Color.primary.opacity(0.65))
                        }
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 32)
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 8) {
                ForEach(cards.indices, id: \.self) { i in
                    Capsule()
                        .fill(Color.primary.opacity(i == page ? 0.85 : 0.2))
                        .frame(width: i == page ? 22 : 8, height: 8)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: page)

            Button(page < cards.count - 1 ? "Next" : "Start") {
                if page < cards.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    dismiss()
                }
            }
            .buttonStyle(GlowButtonStyle(color: .primary))
            .padding(.top, 26)
            .padding(.bottom, 30)
        }
        .background(AppBackground())
    }

    @ViewBuilder
    private func art(_ i: Int) -> some View {
        switch i {
        case 0: SideOnArt()
        case 1: FrameArt()
        default: ThreePhotosArt()
        }
    }
}

/// A side-on finger (right) next to one with the nail facing the camera
/// (wrong).
private struct SideOnArt: View {
    var body: some View {
        HStack(spacing: 36) {
            finger(good: true) {
                FingerProfileShape()
                    .stroke(Color.primary, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            finger(good: false) {
                FingerFrontShape()
                    .stroke(Color.primary.opacity(0.35), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func finger(good: Bool, @ViewBuilder drawing: () -> some View) -> some View {
        VStack(spacing: 14) {
            drawing()
                .frame(width: 100, height: 180)
            Image(systemName: good ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 30))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, good ? Theme.aligned : Theme.attention)
        }
    }
}

/// The camera's frame with a finger inside it, glowing green.
private struct FrameArt: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).stroke(Color.primary.opacity(0.15), lineWidth: 2))
                .frame(width: 180, height: 280)
            CornerMarks(arm: 18)
                .stroke(Color.primary.opacity(0.45), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 96, height: 170)
                .offset(y: 16)
            ZStack {
                FingerProfileShape()
                    .fill(Theme.aligned.opacity(0.16))
                FingerProfileShape()
                    .stroke(Theme.aligned, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .shadow(color: Theme.aligned.opacity(0.5), radius: 6)
            }
            .frame(width: 70, height: 150)
            .offset(y: 30)
            Label("Hold still", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.aligned)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.07), in: Capsule())
                .offset(y: -96)
        }
    }
}

/// Three readings, each checked off.
private struct ThreePhotosArt: View {
    var body: some View {
        HStack(spacing: 18) {
            ForEach(1...3, id: \.self) { n in
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(Theme.aligned, lineWidth: 4)
                        Image(systemName: "checkmark")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Theme.aligned)
                    }
                    .frame(width: 70, height: 70)
                    Text("\(n)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.55))
                }
            }
        }
    }
}

#Preview {
    IntroView()
}
