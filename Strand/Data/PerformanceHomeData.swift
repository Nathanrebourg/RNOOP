import Foundation

enum PerformanceHomeData {
    static func merged(_ primary: [ResolvedMetricPoint], fallback: [ResolvedMetricPoint],
                       from: String, through: String) -> [ResolvedMetricPoint] {
        var byDay: [String: ResolvedMetricPoint] = [:]
        for point in primary + fallback where point.day >= from && point.day <= through && point.value.isFinite {
            if byDay[point.day] == nil { byDay[point.day] = point }
        }
        return byDay.values.sorted { $0.day < $1.day }
    }

    static func latest(_ points: [ResolvedMetricPoint], through: String) -> ResolvedMetricPoint? {
        points.filter { $0.day <= through && $0.value.isFinite }.max { $0.day < $1.day }
    }
}
