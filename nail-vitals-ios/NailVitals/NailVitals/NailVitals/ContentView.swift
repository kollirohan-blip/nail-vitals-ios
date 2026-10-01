// ContentView.swift
//
// The app's root: the Home screen, with a guided scan opening full-screen
// over it. A finished scan is saved to the history and shows on Home.

import SwiftUI

struct ContentView: View {
    /// False while the opening animation still covers the screen.
    var splashFinished = true

    @StateObject private var history = ScanHistory()
    @State private var scanning = false
    @AppStorage("hasSeenPoseGuide") private var hasSeenPoseGuide = false
    @State private var showGuide = false
    @Namespace private var scanTransition

    var body: some View {
        HomeView(history: history, transition: scanTransition, onStartScan: { scanning = true })
            .fullScreenCover(isPresented: $scanning) {
                ScanView(
                    onClose: { scanning = false },
                    onSessionDone: { readings, hand in
                        history.add(readings: readings, hand: hand)
                        scanning = false
                    }
                )
                .navigationTransition(.zoom(sourceID: "scan", in: scanTransition))
            }
            .sheet(isPresented: $showGuide, onDismiss: { hasSeenPoseGuide = true }) {
                PoseGuideView()
            }
            .onAppear(perform: showGuideOnFirstLaunch)
            .onChange(of: splashFinished) { _, _ in showGuideOnFirstLaunch() }
    }

    private func showGuideOnFirstLaunch() {
        if splashFinished && !hasSeenPoseGuide && !showGuide {
            showGuide = true
        }
    }
}

#Preview {
    ContentView()
}
