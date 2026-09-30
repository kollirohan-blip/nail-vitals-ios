//
//  PreviewMapping.swift
//  NailVitals
//
//  Image pixels -> view points for the live camera preview, which uses
//  aspect-fill scaling (the image is scaled to cover the view and the
//  overflow is cropped equally on both sides).
//

import CoreGraphics

struct PreviewMapping {
    let scale: CGFloat
    let offset: CGPoint

    init(imageSize: CGSize, viewSize: CGSize) {
        scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        offset = CGPoint(x: (viewSize.width - imageSize.width * scale) / 2,
                         y: (viewSize.height - imageSize.height * scale) / 2)
    }

    func toView(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * scale + offset.x, y: p.y * scale + offset.y)
    }
}
