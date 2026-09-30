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
    var body: some Scene {
        WindowGroup {
            if showDetectionLab {
                DetectionLabView()
            } else {
                ContentView()
            }
        }
    }
}
