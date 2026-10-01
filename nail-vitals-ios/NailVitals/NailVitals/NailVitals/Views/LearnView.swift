//
//  LearnView.swift
//  NailVitals
//
//  The Learn tab: how to hold your finger for a scan, and the science
//  behind the three signs (the same pages the camera and result screens
//  open as sheets).
//

import SwiftUI

struct LearnView: View {
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
                            .navigationTitle("The science")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        row(icon: "book.closed.fill", title: "The science",
                            text: "The three signs, their published cut-offs, and the studies behind them.")
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
        }
    }

    private func row(icon: String, title: String, text: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 48, height: 48)
                .glassEffect(.regular, in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Text(text)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(16)
        .contentShape(.rect)
        .glassCard(cornerRadius: 22)
    }
}
