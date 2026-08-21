import Foundation

struct LiquidParameters: Sendable, Equatable {
    var dropletCount = 3
    var radius: Float = 0.085
    var threshold: Float = 0.92
    var perturbation: Float = 0.015
    var colorProgress: Float = 0.25
    var spacing: Float = 0.13
    var hoveredDroplet = -1
    var stretch: Float = 0
    var fallProgress: Float = 0
    var droplets: [LiquidDropletParameters] = []
    var theme: LiquidTheme = .notch

    static let maximumDropletCount = 8
}

struct LiquidDropletParameters: Identifiable, Sendable, Equatable {
    let id: UUID
    let normalizedX: Float
    let colorProgress: Float
    let halfLength: Float
}

extension LiquidParameters {
    static func notch(
        snapshot: NotchLayoutSnapshot,
        hoveredTaskID: UUID? = nil
    ) -> LiquidParameters {
        var parameters = LiquidParameters()
        parameters.droplets = snapshot.items.map {
            LiquidDropletParameters(
                id: $0.id,
                normalizedX: Float($0.resolvedX / max(snapshot.contentWidth, 1)),
                colorProgress: $0.colorProgress,
                halfLength: parameters.theme.halfLength(for: $0.importance)
            )
        }
        parameters.dropletCount = parameters.droplets.count
        parameters.radius = parameters.theme.radius(forDropletCount: parameters.dropletCount)
        parameters.threshold = parameters.theme.threshold
        parameters.perturbation = parameters.theme.perturbation
        parameters.colorProgress = parameters.droplets.map(\.colorProgress).max() ?? 0
        parameters.hoveredDroplet = parameters.droplets.firstIndex { $0.id == hoveredTaskID } ?? -1
        return parameters
    }
}
