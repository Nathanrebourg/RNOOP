import Foundation

enum PerformanceDashboardDestination: Equatable {
    case metric(String), stepsAverage, hydration, coupled, coach
}

enum PerformanceDashboardPolicy {
    static func destination(for card: DashboardCard) -> PerformanceDashboardDestination {
        switch card {
        case .hrv: .metric("hrv")
        case .restingHr: .metric("rhr")
        case .respiratory: .metric("resp_rate")
        case .steps: .metric("steps")
        case .stepsAverage30: .stepsAverage
        case .stress: .metric("stress")
        case .fitnessAge: .metric("fitness_age")
        case .vo2max: .metric("vo2max")
        case .vitality: .metric("vitality")
        case .bloodOxygen: .metric("spo2")
        case .skinTemp: .metric("skin_temp")
        case .sleep: .metric("sleep_total_min")
        case .calories: .metric("active_kcal")
        case .hydration: .hydration
        case .coupled: .coupled
        case .coach: .coach
        }
    }
}
