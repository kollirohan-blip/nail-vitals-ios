//
//  CaptureRecorder.swift
//  NailVitals
//
//  Saves each confirmed measurement (full photo + what the pipeline found +
//  what the user confirmed) to Documents/Captures/<timestamp>/ so real
//  captures can be copied to the Mac and replayed with Tools/photo-lab.
//  Manual dots placed carefully on the real cuticle are the ground truth
//  for tuning the automatic cuticle finder. Visible in the Files app.
//

import UIKit

/// Turn off before handing the app to anyone outside the team.
let saveCapturesForTesting = true

nonisolated struct CaptureRecord: Codable {
    nonisolated struct Joint: Codable { let x: Double; let y: Double; let confidence: Double }
    nonisolated struct Marker: Codable { let side: String; let angle: Double; let x: Double; let y: Double }

    let createdAt: Date
    let imageWidth: Int
    let imageHeight: Int
    let indexTip: Joint?
    let indexDIP: Joint?
    let indexPIP: Joint?
    let indexMCP: Joint?
    let thumbTip: Joint?
    let automaticMarkers: [Marker]
    let confirmed: Marker
    /// Nail, cuticle, skin -- only when the user placed the points themselves.
    let manualDots: [[Double]]?
}

nonisolated enum CaptureRecorder {
    static func save(image: UIImage, landmarks: HandLandmarks?, result: LovibondResult?,
                     confirmed: LovibondCandidate, manualDots: [CGPoint]?) {
        guard saveCapturesForTesting else { return }
        func joint(_ j: HandLandmarks.Joint?) -> CaptureRecord.Joint? {
            j.map { .init(x: Double($0.point.x), y: Double($0.point.y), confidence: Double($0.confidence)) }
        }
        func marker(_ c: LovibondCandidate) -> CaptureRecord.Marker {
            .init(side: c.side, angle: c.angleDegrees, x: Double(c.inflectionPoint.x), y: Double(c.inflectionPoint.y))
        }
        let record = CaptureRecord(
            createdAt: Date(),
            imageWidth: Int(image.size.width), imageHeight: Int(image.size.height),
            indexTip: joint(landmarks?.indexTip), indexDIP: joint(landmarks?.indexDIP),
            indexPIP: joint(landmarks?.indexPIP), indexMCP: joint(landmarks?.indexMCP),
            thumbTip: joint(landmarks?.thumbTip),
            automaticMarkers: result?.candidates.map(marker) ?? [],
            confirmed: marker(confirmed),
            manualDots: manualDots?.map { [Double($0.x), Double($0.y)] }
        )

        DispatchQueue.global(qos: .utility).async {
            do {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMMdd-HHmmss"
                let folder = try FileManager.default
                    .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                    .appendingPathComponent("Captures", isDirectory: true)
                    .appendingPathComponent(formatter.string(from: record.createdAt), isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                guard let jpeg = image.jpegData(compressionQuality: 0.95) else { return }
                try jpeg.write(to: folder.appendingPathComponent("photo.jpg"))
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                try encoder.encode(record).write(to: folder.appendingPathComponent("capture.json"))
            } catch {
                print("CaptureRecorder: save failed: \(error)")
            }
        }
    }
}
