//
//  LearnView.swift
//  NailVitals
//
//  The Learn tab: how to hold your finger for a scan, the science behind
//  the clubbing signs (the same pages the camera and result screens open
//  as sheets), and the two beta tests with their explanations.
//

import SwiftUI

struct LearnView: View {
    @State private var showNailCheck = false
    @State private var showSchamroth = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    NavigationLink {
                        PoseGuideView(embedded: true)
                    } label: {
                        row(icon: "hand.point.up.left.fill", title: "How to scan",
                            text: "Hold your finger so the camera sees its side.")
                    }
                    NavigationLink {
                        AboutMeasurementsContent()
                            .navigationTitle("Clubbing")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        row(icon: "angle", title: "Clubbing",
                            text: "The three signs, their published cut-offs, and the studies behind them.")
                    }
                    Button { showNailCheck = true } label: {
                        row(icon: "hand.raised.fingers.spread", title: "Nail colour bands (beta)",
                            text: "Terry's and half-and-half nails: what they are, and a test from a photo of your nails.")
                    }
                    Button { showSchamroth = true } label: {
                        row(icon: "rhombus", title: "Schamroth window (beta)",
                            text: "The small gap between two nails held back to back, and a test for it.")
                    }
                    SafetyNote()
                        .padding(.top, 8)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .background(AppBackground())
            .navigationTitle("Learn")
            .fullScreenCover(isPresented: $showNailCheck) { NailCheckView() }
            .fullScreenCover(isPresented: $showSchamroth) { SchamrothView() }
        }
    }

    private func row(icon: String, title: String, text: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.85))
                .frame(width: 48, height: 48)
                .background(Color.primary.opacity(0.07), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.35))
        }
        .padding(16)
        .contentShape(.rect)
        .glassCard(cornerRadius: 22)
    }
}
