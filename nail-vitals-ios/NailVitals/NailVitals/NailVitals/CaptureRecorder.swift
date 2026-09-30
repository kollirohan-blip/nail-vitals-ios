//
//  CaptureRecorder.swift
//  NailVitals
//
//  Saves every analyzed capture to Documents/Captures/<timestamp>/ so real
//  captures can be copied to the Mac (Tools/pull-captures.sh) and replayed
//  with Tools/photo-lab:
//    photo.jpg          full-resolution photo
//    capture.json       hand-pose joints + automatic markers (or failure)
//    confirmation.json  added only if the user confirms a reading; manual
//                       dots there are the ground truth for tuning
//  Saved at analysis time, not on confirm, so captures the user backs out
//  of are kept too. Visible in the Files app.
//

import UIKit

/// Turn off before handing the app to anyone outside the team.
let saveCapturesForTesting = true

nonisolated struct CaptureJoint: Codable {
    let x: Double
    let y: Double
    let confidence: Double
}

nonisolated struct CaptureMarker: Codable {
    let side: String
    let angle: Double
    let x: Double
    let y: Double
}

nonisolated struct CaptureRecord: Codable {
    let createdAt: Date
    let imageWidth: Int
    let imageHeight: Int
    let indexTip: CaptureJoint?
    let indexDIP: CaptureJoint?
    let indexPIP: CaptureJoint?
    let indexMCP: CaptureJoint?
    let thumbTip: CaptureJoint?
    let automaticMarkers: [CaptureMarker]
    let failure: String?
}

nonisolated struct ConfirmationRecord: Codable {
    let confirmedAt: Date
    let confirmed: CaptureMarker
    /// Nail, cuticle, skin -- only when the user placed the points themselves.
    let manualDots: [[Double]]?
}

nonisolated enum CaptureRecorder {
    /// Writes the photo and analysis; returns the capture's folder so a later
    /// confirmation can be added to it.
    static func saveAnalysis(image: UIImage, landmarks: HandLandmarks?, result: LovibondResult?, failure: String?) -> URL? {
        guard saveCapturesForTesting else { return nil }
        func joint(_ j: HandLandmarks.Joint?) -> CaptureJoint? {
            j.map { CaptureJoint(x: Double($0.point.x), y: Double($0.point.y), confidence: Double($0.confidence)) }
        }
        let record = CaptureRecord(
            createdAt: Date(),
            imageWidth: Int(image.size.width), imageHeight: Int(image.size.height),
            indexTip: joint(landmarks?.indexTip), indexDIP: joint(landmarks?.indexDIP),
            indexPIP: joint(landmarks?.indexPIP), indexMCP: joint(landmarks?.indexMCP),
            thumbTip: joint(landmarks?.thumbTip),
            automaticMarkers: result?.candidates.map(marker) ?? [],
            failure: failure
        )

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        guard let folder = try? FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Captures", isDirectory: true)
            .appendingPathComponent(formatter.string(from: record.createdAt), isDirectory: true),
              (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil
        else { return nil }

        DispatchQueue.global(qos: .utility).async {
            do {
                if let jpeg = image.jpegData(compressionQuality: 0.95) {
                    try jpeg.write(to: folder.appendingPathComponent("photo.jpg"))
                }
                try encoder().encode(record).write(to: folder.appendingPathComponent("capture.json"))
            } catch {
                print("CaptureRecorder: save failed: \(error)")
            }
        }
        return folder
    }

    static func saveConfirmation(in folder: URL?, confirmed: LovibondCandidate, manualDots: [CGPoint]?) {
        guard saveCapturesForTesting, let folder else { return }
        let record = ConfirmationRecord(
            confirmedAt: Date(),
            confirmed: marker(confirmed),
            manualDots: manualDots?.map { [Double($0.x), Double($0.y)] }
        )
        DispatchQueue.global(qos: .utility).async {
            do {
                try encoder().encode(record).write(to: folder.appendingPathComponent("confirmation.json"))
            } catch {
                print("CaptureRecorder: confirmation save failed: \(error)")
            }
        }
    }

    private static func marker(_ c: LovibondCandidate) -> CaptureMarker {
        CaptureMarker(side: c.side, angle: c.angleDegrees, x: Double(c.inflectionPoint.x), y: Double(c.inflectionPoint.y))
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
