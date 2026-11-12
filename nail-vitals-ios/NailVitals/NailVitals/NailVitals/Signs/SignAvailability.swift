//
//  SignAvailability.swift
//  NailVitals
//
//  Which signs the app shows. A sign is added here only after it passes
//  its written accuracy test (docs/superpowers/specs, "New signs:
//  measurement and accuracy tests"). A sign that isn't listed doesn't
//  appear anywhere, even when a saved check-up holds a result for it.
//

import Foundation

nonisolated enum SignAvailability {
    static let enabled: Set<NailSign> = [.clubbing]
}
