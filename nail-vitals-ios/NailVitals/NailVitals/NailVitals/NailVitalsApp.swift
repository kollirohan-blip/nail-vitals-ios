//
//  NailVitalsApp.swift
//  NailVitals
//
//  Created by Sowjanya Kolli on 8/14/26.
//

import SwiftUI

/// true = open the Detection Lab test screen instead of the normal app.
let showDetectionLab = false

/// true = show the hand-pose numbers under the capture button (testing only).
let showDebugReadout = false

@main
struct NailVitalsApp: App {
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showDetectionLab {
                    DetectionLabView()
                } else {
                    ContentView()
                }
                if showSplash {
                    SplashView { showSplash = false }
                        .zIndex(1)
                }
            }
        }
    }
}
