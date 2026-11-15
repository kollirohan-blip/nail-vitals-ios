// ContentView.swift
//
// The app's root: the home tabs, with a guided assessment opening
// full-screen over them. A finished assessment is saved to the history and
// shows on Home. First launch shows the welcome screens.

import SwiftUI

struct ContentView: View {
    /// False while the opening animation still covers the screen.
    var splashFinished = true

    @StateObject private var history = ScanHistory()
    @State private var scanning = false
    /// A printed model finger on a stand: measured like a finger, kept out of the history.
    @State private var scanningModel = false
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var showWelcome = false
    @Namespace private var scanTransition

    var body: some View {
        HomeTabs(history: history, transition: scanTransition, onStartScan: { scanning = true },
                 onStartModelScan: { scanningModel = true })
            .environment(\.startAssessment, { scanning = true })
            .fullScreenCover(isPresented: $scanningModel) {
                ScanView(modelMode: true, onClose: { scanningModel = false }, onSessionDone: { _, _ in scanningModel = false })
            }
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
            // What the app is, where photos go, which finger: once, on
            // first launch. How to hold the finger is shown the first time
            // the camera opens (ScanView).
            .fullScreenCover(isPresented: $showWelcome) {
                WelcomeView {
                    hasSeenWelcome = true
                    showWelcome = false
                }
            }
            .onAppear(perform: showWelcomeOnFirstLaunch)
            .onChange(of: splashFinished) { _, _ in showWelcomeOnFirstLaunch() }
    }

    private func showWelcomeOnFirstLaunch() {
        if splashFinished && !hasSeenWelcome && !showWelcome {
            showWelcome = true
        }
    }
}

#Preview {
    ContentView()
}
