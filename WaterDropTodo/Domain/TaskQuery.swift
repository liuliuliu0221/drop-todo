import Foundation

enum TaskQuery {
    static func active(_ tasks: [TaskRecord], tag: TaskTag?) -> [TaskRecord] {
        tasks
            .filter { task in
                task.status == .active && (tag == nil || task.tag == tag)
            }
            .sorted {
                if $0.deadline == $1.deadline {
                    return $0.createdAt < $1.createdAt
                }
                return $0.deadline < $1.deadline
            }
    }
}
