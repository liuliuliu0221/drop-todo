import Foundation
import simd

struct LiquidTheme: Sendable, Equatable {
    let radius: Float
    let mediumDensityRadius: Float
    let highDensityRadius: Float
    let hoverScale: Float
    let lowImportanceHalfLength: Float
    let mediumImportanceHalfLength: Float
    let highImportanceHalfLength: Float
    let threshold: Float
    let perturbation: Float
    let surfaceY: Float
    let surfaceDepth: Float
    let dropletY: Float
    let opacity: Float
    let clearBlue: SIMD3<Float>
    let deepBlue: SIMD3<Float>
    let asphalt: SIMD3<Float>

    static let notch = LiquidTheme(
        radius: 0.065,
        mediumDensityRadius: 0.057,
        highDensityRadius: 0.050,
        hoverScale: 2.00,
        lowImportanceHalfLength: 0.028,
        mediumImportanceHalfLength: 0.0505,
        highImportanceHalfLength: 0.070,
        threshold: 1.28,
        perturbation: 0.01,
        surfaceY: 0.12,
        surfaceDepth: 0.12,
        dropletY: 0.22,
        opacity: 0.94,
        clearBlue: SIMD3(0.19, 0.83, 0.98),
        deepBlue: SIMD3(0.02, 0.19, 0.62),
        asphalt: SIMD3(0.015, 0.02, 0.035)
    )

    func radius(forDropletCount count: Int) -> Float {
        switch count {
        case ...3: radius
        case 4...5: mediumDensityRadius
        default: highDensityRadius
        }
    }

    func halfLength(for importance: Urgency) -> Float {
        switch importance {
        case .low: lowImportanceHalfLength
        case .medium: mediumImportanceHalfLength
        case .high: highImportanceHalfLength
        }
    }

    func centerY(forHalfLength halfLength: Float) -> Float {
        let attachmentY = dropletY - highImportanceHalfLength
        return attachmentY + halfLength
    }
}
