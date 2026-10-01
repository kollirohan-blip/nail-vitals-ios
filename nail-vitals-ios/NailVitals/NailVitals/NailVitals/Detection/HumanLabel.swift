//
//  HumanLabel.swift
//  NailVitals
//
//  A person's hand-placed points on a saved capture (Label mode), and the
//  three signs they give -- the "human" side of the app-vs-human check.
//  Plain geometry, shared by the app and Tools/photo-lab.
//
//  Points, all on the side-view photo:
//    cuticle       where the nail meets the skin fold (B)
//    nail          on the nail's edge, partway to the tip
//    skin          on the skin fold's edge, about as far below the cuticle
//    crease        nail-side edge level with the last joint's crease (A):
//                  the fold line on the pad side where the fingertip
//                  bends, carried straight across to the nail side
//    freeEdge      nail-side edge where the nail ends at the tip (C)
//    cuticleAcross opposite edge, straight across from the cuticle
//    creaseAcross  opposite edge, straight across from the crease
//

import CoreGraphics
import Foundation

nonisolated struct HumanLabel: Codable, Equatable {
    nonisolated enum Point: String, CaseIterable, Codable {
        case cuticle, nail, skin, crease, freeEdge, cuticleAcross, creaseAcross

        /// Instruction shown while placing this point.
        var instruction: String {
            switch self {
            case .cuticle: return "Tap the cuticle: where the nail meets the skin fold, on the nail's edge."
            case .nail: return "Tap the nail's edge about halfway from the cuticle to the tip."
            case .skin: return "Tap the skin's edge below the cuticle, about as far as the last point is above it."
            case .crease: return "Find the fold line on the pad side where the fingertip bends (the last joint's crease). Tap the nail-side edge straight across from it."
            case .freeEdge: return "Tap the nail-side edge where the nail ends at the tip."
            case .cuticleAcross: return "Tap the opposite edge of the finger, straight across from the cuticle."
            case .creaseAcross: return "Tap the pad-side edge right at that fold line."
            }
        }

        var shortName: String {
            switch self {
            case .cuticle: return "Cuticle"
            case .nail: return "Nail"
            case .skin: return "Skin"
            case .crease: return "Crease"
            case .freeEdge: return "Nail tip"
            case .cuticleAcross: return "Across cuticle"
            case .creaseAcross: return "Across crease"
            }
        }
    }

    var labeler: String
    var labeledAt: Date
    /// Image pixels of the full photo, top-left origin, keyed by Point raw value.
    var points: [String: [Double]]
    var profile: Double?
    var hyponychial: Double?
    var depthRatio: Double?

    init(labeler: String, labeledAt: Date = Date(), points: [Point: CGPoint]) {
        self.labeler = labeler
        self.labeledAt = labeledAt
        self.points = Dictionary(uniqueKeysWithValues: points.map { ($0.key.rawValue, [Double($0.value.x), Double($0.value.y)]) })
        let signs = Self.signs(points)
        profile = signs.profile
        hyponychial = signs.hyponychial
        depthRatio = signs.depthRatio
    }

    func point(_ p: Point) -> CGPoint? {
        points[p.rawValue].flatMap { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil }
    }

    /// All placed points, for recomputing the signs (e.g. after the
    /// formulas change) rather than trusting the saved values.
    var placedPoints: [Point: CGPoint] {
        Dictionary(uniqueKeysWithValues: Point.allCases.compactMap { p in point(p).map { (p, $0) } })
    }

    /// The three signs from the points, computed the way the app does:
    /// outside angles at the cuticle, inside judged against the finger
    /// outlined by the points themselves.
    static func signs(_ p: [Point: CGPoint]) -> (profile: Double?, hyponychial: Double?, depthRatio: Double?) {
        guard let b = p[.cuticle] else { return (nil, nil, nil) }
        // Distal phalanx: down the nail side, across, up the pad side.
        let outline = [p[.freeEdge], p[.nail], b, p[.skin], p[.crease], p[.creaseAcross], p[.cuticleAcross]].compactMap { $0 }
        let inside: (CGPoint) -> Bool? = { outline.count >= 4 ? polygonContains(outline, $0) : nil }

        let profile = p[.nail].flatMap { n in p[.skin].flatMap { s in
            AngleAnalyzer.outsideAngle(nailPoint: n, cuticle: b, skinPoint: s, isInsideFinger: inside)
        } }
        let hyponychial = p[.freeEdge].flatMap { c in p[.crease].flatMap { a in
            AngleAnalyzer.outsideAngle(nailPoint: c, cuticle: b, skinPoint: a, isInsideFinger: inside)
        } }
        var ratio: Double?
        if let ba = p[.cuticleAcross], let a = p[.crease], let aa = p[.creaseAcross] {
            let joint = hypot(a.x - aa.x, a.y - aa.y)
            if joint > 0 { ratio = Double(hypot(b.x - ba.x, b.y - ba.y) / joint) }
        }
        return (profile, hyponychial, ratio)
    }

    private static func polygonContains(_ polygon: [CGPoint], _ p: CGPoint) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let a = polygon[i], c = polygon[j]
            if (a.y > p.y) != (c.y > p.y), p.x < (c.x - a.x) * (p.y - a.y) / (c.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }
}
