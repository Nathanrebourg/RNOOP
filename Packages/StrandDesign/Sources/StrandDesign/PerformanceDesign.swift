import SwiftUI

/// Tokens for the approved compact iPhone performance experience, isolated from the existing themes.
public enum PerformanceDesign {
    public static let top = Color(light: "#E2E9ED", dark: "#0A0E14")
    public static let middle = Color(light: "#F1F4F6", dark: "#0A0E14")
    public static let bottom = Color(light: "#F8FAFB", dark: "#0A0E14")
    public static let panelTop = Color(light: "#FFFFFF", dark: "#1A1F26")
    public static let panelBottom = Color(light: "#E7EDF0", dark: "#1A1F26")
    public static let sleep = Color(light: "#426F8C", dark: "#4A90E2")
    public static let effort = Color(light: "#087BA4", dark: "#007AFF")
    public static let recoveryHigh = Color(light: "#168347", dark: "#2ECC71")
    public static let recoveryMedium = Color(light: "#997A00", dark: "#FFCC00")
    public static let recoveryLow = Color(light: "#C62828", dark: "#FF3B30")
    public static let coach = Color(light: "#31536F", dark: "#B7D5EF")
    public static let panelRadius: CGFloat = 14
    public static let navigationRadius: CGFloat = 25
    public static let smallRing: CGFloat = 104
    public static let largeRing: CGFloat = 252
    public static let smallStroke: CGFloat = 9
    public static let largeStroke: CGFloat = 18
    public static let scoreSize: CGFloat = 66
    public static let compactScoreSize: CGFloat = 29
    public static let suffixSize: CGFloat = 25
    public static let compactSuffixSize: CGFloat = 14
    public static let wordmarkSize: CGFloat = 19
    public static let brandTracking: CGFloat = 3
    public static let labelTracking: CGFloat = 1
    public static let controlDiameter: CGFloat = 44
    public static let coachDiameter: CGFloat = 54
    public static let coachSymbolDiameter: CGFloat = 32
    public static let navigationHeight: CGFloat = 64
    public static let productHeight: CGFloat = 300
    public static let chartHeight: CGFloat = 228
    public static let compactChartHeight: CGFloat = 140
    public static let stageChartHeight: CGFloat = 108
    public static let historyDays = [7, 28, 180]
    public static let chartStroke: CGFloat = 2
}

public struct PerformanceBackground: View {
    public init() {}
    public var body: some View {
        LinearGradient(stops: [.init(color: PerformanceDesign.top, location: 0),
                               .init(color: PerformanceDesign.middle, location: 0.28),
                               .init(color: PerformanceDesign.bottom, location: 1)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
        .ignoresSafeArea()
    }
}

public struct PerformancePanel<Content: View>: View {
    private let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        content
            .padding(NoopMetrics.space4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [PerformanceDesign.panelTop, PerformanceDesign.panelBottom],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: PerformanceDesign.panelRadius))
            .overlay(RoundedRectangle(cornerRadius: PerformanceDesign.panelRadius)
                .strokeBorder(StrandPalette.textPrimary.opacity(0.045), lineWidth: NoopMetrics.hairlineWidth))
    }
}
