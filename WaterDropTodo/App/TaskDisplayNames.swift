import Foundation

extension TaskTag {
    var displayName: String {
        switch self {
        case .work: "工作"
        case .life: "生活"
        case .inspiration: "灵感"
        }
    }
}

extension Urgency {
    var displayName: String {
        switch self {
        case .low: "低"
        case .medium: "中"
        case .high: "高"
        }
    }
}
