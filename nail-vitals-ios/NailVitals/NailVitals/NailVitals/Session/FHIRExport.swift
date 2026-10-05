//
//  FHIRExport.swift
//  NailVitals
//
//  One scan as an HL7 FHIR R4 Observation, the structured format hospital
//  record systems exchange, so a result can be handed to a clinic as data
//  rather than a screenshot. The three signs are components with their
//  published cut-offs as reference ranges. The sign codes are this app's
//  own (a local code system): we didn't find standard codes for these
//  angles. No name or other identity is included; the export is a file the
//  user chooses to share, nothing is sent anywhere by the app.
//

import Foundation

nonisolated enum FHIRExport {
    /// Placeholder identifier for the app's local codes (example.org is
    /// reserved for this kind of use).
    static let signSystem = "http://example.org/nail-vitals/CodeSystem/clubbing-signs"
    static let ucum = "http://unitsofmeasure.org"

    static func observation(for session: ScanSession) -> [String: Any] {
        let readings = session.signs
        let assessment = ClubbingAssessment(readings: readings)
        let noDip = readings.filter(\.noCuticleDip).count * 2 > readings.count
        let hand = MeasuredHand(rawValue: session.hand)?.label ?? "Right"
        let date = ISO8601DateFormatter().string(from: session.date)

        // Decimal values so the JSON says 166.9, not 166.90000000000001.
        func quantity(_ value: Double, _ kind: SignKind) -> [String: Any] {
            kind == .depthRatio
                ? ["value": NSDecimalNumber(string: String(format: "%.3f", value)), "unit": "ratio", "system": ucum, "code": "1"]
                : ["value": NSDecimalNumber(string: String(format: "%.1f", value)), "unit": "deg", "system": ucum, "code": "deg"]
        }
        func code(_ kind: SignKind) -> String {
            switch kind {
            case .lovibond: return "profile-angle"
            case .hyponychial: return "hyponychial-angle"
            case .depthRatio: return "depth-ratio"
            }
        }
        let components: [[String: Any]] = SignKind.allCases.compactMap { kind in
            guard let value = assessment.values[kind] else { return nil }
            return [
                "code": ["coding": [["system": signSystem, "code": code(kind), "display": kind.title]],
                         "text": "\(kind.plainName) (\(kind.title))"],
                "valueQuantity": quantity(value, kind),
                "interpretation": [["text": kind.status(of: value) == .above ? "Above cut-off" : "At or below cut-off"]],
                "referenceRange": [[
                    "high": quantity(kind.threshold, kind),
                    "text": "Clubbing is considered above \(kind.formattedThreshold) (Myers & Farquhar, JAMA 2001)",
                ]],
            ]
        }
        let readingList = readings.compactMap(\.lovibond).map { String(format: "%.1f", $0) }.joined(separator: ", ")
        var notes = [["text": "This tool flags a pattern that may be worth discussing with a doctor. It does not diagnose any condition."]]
        if noDip {
            notes.append(["text": "No dip where the nail meets the skin: Lovibond's angle obliterated (180 or more)."])
        }

        return [
            "resourceType": "Observation",
            "id": session.id.uuidString.lowercased(),
            "meta": ["tag": [["system": "http://example.org/nail-vitals/CodeSystem/status", "code": "research-prototype",
                              "display": "Research prototype, not for diagnosis"]]],
            "status": "final",
            "category": [["coding": [["system": "http://terminology.hl7.org/CodeSystem/observation-category",
                                      "code": "exam", "display": "Exam"]]]],
            "code": ["coding": [["system": signSystem, "code": "finger-clubbing-screen", "display": "Finger clubbing screen from a side photo"]],
                     "text": "Finger clubbing screen (Nail Vitals)"],
            "effectiveDateTime": date,
            "bodySite": ["text": "\(hand) index finger"],
            "method": ["text": "Side-view smartphone photo; middle of \(readings.count) readings (nail angle readings: \(readingList))"],
            "device": ["display": "Nail Vitals iOS app (research prototype)"],
            "interpretation": [["text": assessment.verdict.label]],
            "note": notes,
            "component": components,
        ]
    }

    /// Writes the observation to a temporary .json file for sharing.
    static func file(for session: ScanSession) throws -> URL {
        let data = try JSONSerialization.data(withJSONObject: observation(for: session), options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        let day = session.date.formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nail-vitals-\(day).fhir.json")
        try data.write(to: url, options: .atomic)
        return url
    }
}
