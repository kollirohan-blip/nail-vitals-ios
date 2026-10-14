//
//  ReadingQuality.swift
//  NailVitals
//
//  The checks behind each reading, kept with it so the result can show
//  them: the photo's sharpness and background contrast, the finger's
//  posture as hand pose saw it when the photo was taken, and where the
//  joints came from. Every value is measured; nothing here is a score.
//

import Foundation

nonisolated struct ReadingQuality: Codable, Equatable {
    /// EdgeSharpness at the nail (retake below EdgeSharpness.minimum).
    var sharpness: Double?
    /// BackgroundContrast, CIELAB delta E (retake below BackgroundContrast.minimum).
    var backgroundContrast: Double?
    /// HandLandmarks.dipFlexionDegrees / pipFlexionDegrees when the photo was taken.
    var dipFlexion: Double?
    var pipFlexion: Double?
    /// HandLandmarks.knuckleSpread (how far the back of the hand is turned in).
    var knuckleSpread: Double?
    /// Which outline was measured: "crop", "whole" or "model".
    var outline: String?
    /// The joints came from hand pose (false: estimated from the outline,
    /// OutlineFingerFinder).
    var jointsFromHandPose: Bool?
    /// Hand pose's lowest index-finger joint confidence.
    var handPoseConfidence: Double?

    nonisolated enum Check: String, CaseIterable {
        case sharp, contrast, straight, sideOn

        var label: String {
            switch self {
            case .sharp: return "Sharp photo"
            case .contrast: return "Background contrast"
            case .straight: return "Finger straight"
            case .sideOn: return "Nail side-on"
            }
        }
    }

    /// Whether the check passed; nil when it wasn't measured.
    func passed(_ check: Check) -> Bool? {
        switch check {
        case .sharp:
            return sharpness.map { $0 >= EdgeSharpness.minimum }
        case .contrast:
            return backgroundContrast.map { $0 >= BackgroundContrast.minimum }
        case .straight:
            guard dipFlexion != nil || pipFlexion != nil else { return nil }
            return (dipFlexion.map { HandLandmarks.straightDipFlexion.contains($0) } ?? true)
                && (pipFlexion.map { HandLandmarks.straightPipFlexion.contains($0) } ?? true)
        case .sideOn:
            return knuckleSpread.map { $0 <= HandLandmarks.turnedKnuckleSpread }
        }
    }
}

/// How far a session's middle value moves from one session to the next on
/// the same finger: 95% of repeat sessions land within this of each other's
/// long-run value (1.96 x the SD of session middles). From photo-lab
/// --report on the saved captures (Oct 14): P1's right index, 12 sessions
/// of 3 readings between Sep 30 and Oct 5, SD of the middles 1.63 degrees
/// (profile), 2.24 (hyponychial), 0.029 (depth ratio). One person so far;
/// update when more people's repeat sessions are in.
nonisolated enum Repeatability {
    static let sessions = 12
    static let range95: [SignKind: Double] = [.lovibond: 3.2, .hyponychial: 4.4, .depthRatio: 0.057]
}
