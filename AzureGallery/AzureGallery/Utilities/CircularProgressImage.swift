import UIKit

/// Renders a circular progress indicator as a `UIImage`.
///
/// - Parameters:
///   - progress: Fraction complete, clamped to 0...1.
///   - size: Width and height of the resulting square image.
/// - Returns: A rendered `UIImage` with a gray track and blue progress arc.
func circularProgressImage(progress: Double, size: CGFloat = 25) -> UIImage {
    let clamped = min(max(progress, 0), 1)
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
    return renderer.image { ctx in
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        let lineWidth: CGFloat = size * 0.15
        let insetRect = rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let center = CGPoint(x: size / 2, y: size / 2)
        let radius = insetRect.width / 2

        // Gray track
        let trackPath = UIBezierPath(
            arcCenter: center,
            radius: radius,
            startAngle: 0,
            endAngle: .pi * 2,
            clockwise: true
        )
        trackPath.lineWidth = lineWidth
        UIColor.systemGray4.setStroke()
        trackPath.stroke()

        // Blue progress arc (starts at 12 o'clock = -pi/2)
        guard clamped > 0 else { return }
        let startAngle: CGFloat = -.pi / 2
        let endAngle: CGFloat = startAngle + (.pi * 2 * clamped)
        let progressPath = UIBezierPath(
            arcCenter: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: true
        )
        progressPath.lineWidth = lineWidth
        progressPath.lineCapStyle = .round
        UIColor.systemBlue.setStroke()
        progressPath.stroke()
    }
}
