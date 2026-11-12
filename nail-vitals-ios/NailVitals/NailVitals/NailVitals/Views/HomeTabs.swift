//
//  HomeTabs.swift
//  NailVitals
//
//  The app's home side: four tabs. Home starts a check-up (HomeView);
//  History holds every check-up and the trends; Learn has the guides; Ask
//  is the chat. Neutral colors here: color only marks result states.
//

import SwiftUI

enum AppTab: Hashable {
    case home, history, learn, ask
}

struct HomeTabs: View {
    @ObservedObject var history: ScanHistory
    /// The start button zooms open into the camera.
    var transition: Namespace.ID? = nil
    let onStartScan: () -> Void
    /// Scans a printed model finger on a stand (no hand to detect).
    var onStartModelScan: () -> Void = {}

    @State private var tab: AppTab = .home

    var body: some View {
        TabView(selection: $tab) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                HomeView(history: history, transition: transition, onStartScan: onStartScan,
                         onStartModelScan: onStartModelScan, onShowHistory: { tab = .history })
            }
            Tab("History", systemImage: "clock.arrow.circlepath", value: AppTab.history) {
                HistoryView(history: history)
            }
            Tab("Learn", systemImage: "book.closed.fill", value: AppTab.learn) {
                LearnView()
            }
            Tab("Ask", systemImage: "bubble.left.and.text.bubble.right.fill", value: AppTab.ask) {
                // A fresh chat for each new result.
                AskAssistantView(context: AssistantContext(readings: history.latest?.signs ?? [],
                                                           hand: history.latest.flatMap { MeasuredHand(rawValue: $0.hand) } ?? .right),
                                 embedded: true)
                    .id(history.latest?.id)
            }
        }
        .tint(.primary)
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

/// The logo, small: a mini app icon (the finger with its cuticle angle on a
/// rounded tile, white in Classic and dark gray in Dark, like the real
/// icon) and the name.
struct BrandMark: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tile = RoundedRectangle(cornerRadius: 9, style: .continuous)
        HStack(spacing: 10) {
            ZStack {
                FingerProfileShape()
                    .stroke(Color.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                LovibondAngleMark()
                    .stroke(Theme.aligned, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            .frame(width: 18, height: 22)
            .offset(x: -1, y: 1)
            .frame(width: 32, height: 32)
            .background(scheme == .dark ? Color(red: 0.13, green: 0.14, blue: 0.16) : .white, in: tile)
            .overlay(tile.stroke(Color.primary.opacity(0.1), lineWidth: 1))
            Text("Nail Vitals")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Marks the scan button as where the camera zooms open from.
struct ScanTransitionSource: ViewModifier {
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: "scan", in: namespace)
        } else {
            content
        }
    }
}
