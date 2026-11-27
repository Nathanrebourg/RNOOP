#if os(iOS)
import SwiftUI
import MarkdownUI
import StrandDesign

struct PerformanceCoachSession: Identifiable {
    let context: PerformanceContext
    let engine: AICoachEngine
    var id: String { context.id }
}

/// Contextual histories are deliberately in-memory; the general coach's saved transcript is untouched.
@MainActor
final class PerformanceCoachSessions: ObservableObject {
    private var sessions: [String: AICoachEngine] = [:]
    private var order: [String] = []

    func session(context: PerformanceContext, repo: Repository, settings: AICoachEngine) -> PerformanceCoachSession {
        let engine = sessions[context.id] ?? AICoachEngine(repo: repo, persistsConversation: false)
        Self.copySettings(from: settings, to: engine)
        sessions[context.id] = engine
        order.removeAll { $0 == context.id }
        order.append(context.id)
        while order.count > 8 { sessions.removeValue(forKey: order.removeFirst()) }
        return PerformanceCoachSession(context: context, engine: engine)
    }

    static func copySettings(from settings: AICoachEngine, to engine: AICoachEngine) {
        engine.provider = settings.provider
        engine.model = settings.model
        engine.customBaseURL = settings.customBaseURL
        engine.customAuthHeader = settings.customAuthHeader
        engine.customConnected = settings.customConnected
        engine.dataConsent = settings.dataConsent
        engine.includeOnDeviceSignals = settings.includeOnDeviceSignals
        engine.multimodalChartEnabled = settings.multimodalChartEnabled
    }

    func removeAll() { sessions.removeAll(); order.removeAll() }
}

struct PerformanceCoachSheet: View {
    let session: PerformanceCoachSession
    @ObservedObject private var engine: AICoachEngine
    @EnvironmentObject private var repo: Repository
    @StateObject private var snapshotModel = PerformanceSnapshotModel()
    @EnvironmentObject private var settings: AICoachEngine
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var showSetup = false
    @State private var showClear = false
    @FocusState private var inputFocused: Bool
    @AppStorage("noop.coachEnabled") private var enabled = true

    init(session: PerformanceCoachSession) {
        self.session = session
        _engine = ObservedObject(wrappedValue: session.engine)
    }

    private var subject: String {
        session.context.metric.map(PerformanceFormat.title) ?? session.context.domain.title
    }
    private var suggestions: [String] {
        switch session.context.domain {
        case .sleep: [String(localized: "Help me understand this night"), String(localized: "How should I read sleep consistency?")]
        case .recovery, .health: [String(localized: "Explain these measurements"), String(localized: "How do these measurements compare to my reference?")]
        case .effort, .activities: [String(localized: "Help me understand this day's effort"), String(localized: "Explain the recorded activities")]
        case .trend: [String(localized: "Explain this trend and its missing days"), String(localized: "How should I read this period's average?")]
        case .today:
            [String(localized: "How does my sleep relate to my recovery today?"),
             String(localized: "How should I interpret today’s strain alongside recovery?"),
             String(localized: "What should I know about my sleep, recovery and strain together?")]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack {
                Text(subject).font(StrandFont.caption)
                Spacer()
                Text(PerformanceFormat.date(session.context.day)).font(StrandFont.footnote)
            }.foregroundStyle(StrandPalette.textSecondary).padding(NoopMetrics.space4)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                        if engine.messages.isEmpty {
                            introduction
                            if let snapshot = snapshotModel.snapshot, snapshot.context.day == session.context.day {
                                scoreSummary(snapshot)
                            }
                        }
                        ForEach(engine.messages) { message in
                            messageRow(message)
                        }
                        if let error = engine.errorText {
                            PerformancePanel { Text(error).font(StrandFont.subhead).foregroundStyle(StrandPalette.statusCritical) }
                        }
                        if engine.sending { ProgressView("Coach is replying…").font(StrandFont.caption) }
                        if engine.isConfigured && !engine.sending {
                            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                                ForEach(suggestions, id: \.self) { question in
                                    Button { send(question) } label: {
                                        Text(question).font(StrandFont.subhead).multilineTextAlignment(.leading)
                                            .padding(NoopMetrics.space3)
                                            .background(PerformanceDesign.coach.opacity(0.08), in: RoundedRectangle(cornerRadius: PerformanceDesign.panelRadius))
                                            .overlay(RoundedRectangle(cornerRadius: PerformanceDesign.panelRadius).strokeBorder(PerformanceDesign.coach.opacity(0.25), lineWidth: NoopMetrics.hairlineWidth))
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                        Color.clear.frame(height: NoopMetrics.space1).id("coach-bottom")
                    }.padding(NoopMetrics.space4)
                }
                .onChange(of: engine.messages.last?.text) { _, _ in proxy.scrollTo("coach-bottom", anchor: .bottom) }
                .onChange(of: engine.sending) { _, _ in proxy.scrollTo("coach-bottom", anchor: .bottom) }
            }
            composer
        }
        .background(PerformanceBackground())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(engine.sending)
        .sheet(isPresented: $showSetup, onDismiss: {
            PerformanceCoachSessions.copySettings(from: settings, to: engine)
        }) { NavigationStack { CoachView(configurationOnly: true) } }
        .confirmationDialog("Clear this conversation?", isPresented: $showClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { engine.clearConversation() }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: settings.dataConsent) { _, value in engine.dataConsent = value }
        .onChange(of: enabled) { _, on in if !on { dismiss() } }
        .task(id: session.context.id) {
            await snapshotModel.load(repo: repo, context: session.context)
        }
    }

    private var header: some View {
        HStack(spacing: NoopMetrics.space3) {
            PerformanceCoachSymbol()
            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                Text("Coach NROOP").font(StrandFont.headline)
                Text(engine.provider.displayName).font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
            }
            Spacer()
            Menu {
                Button("Coach settings", systemImage: "gearshape") { showSetup = true }
                Button("New conversation", systemImage: "plus.bubble") { showClear = true }.disabled(engine.messages.isEmpty || engine.sending)
            } label: { Image(systemName: "ellipsis").frame(width: PerformanceDesign.controlDiameter, height: PerformanceDesign.controlDiameter) }
            Button { dismiss() } label: { Image(systemName: "xmark").frame(width: PerformanceDesign.controlDiameter, height: PerformanceDesign.controlDiameter) }
                .disabled(engine.sending).accessibilityLabel("Close Coach")
        }.foregroundStyle(StrandPalette.textPrimary).padding(NoopMetrics.space4)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space3) {
            Text(String(localized: "Ask NROOP anything")).font(StrandFont.title2)
            Text("This conversation keeps the screen, day and period you are viewing. No request is sent until you ask a question.")
                .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
            if !engine.isConfigured {
                Text("Connect your existing AI provider to receive answers.").font(StrandFont.subhead)
                Button("Configure Coach") { showSetup = true }.buttonStyle(.borderedProminent)
            } else if !settings.dataConsent {
                Text("Your measurements are not shared. You can ask general questions or change this in Coach settings.")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                Button("Coach settings") { showSetup = true }.font(StrandFont.subhead)
            }
        }
    }

    private func scoreSummary(_ snapshot: PerformanceSnapshot) -> some View {
        PerformancePanel {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                Text("Scores for this day").font(StrandFont.overline)
                HStack {
                    ForEach([PerformanceContext.Domain.sleep, .recovery, .effort], id: \.self) { domain in
                        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                            Text(domain.title).font(StrandFont.caption)
                            Text(domain == .effort ? PerformanceFormat.effort(snapshot.value(domain.metricKey)) : PerformanceFormat.number(snapshot.value(domain.metricKey)))
                                .font(StrandFont.headline).monospacedDigit()
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Text("Calculated on this device. Missing scores are shown as —.")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
            }
        }
    }

    private func messageRow(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            Text(message.role == .assistant ? String(localized: "Coach NROOP") : String(localized: "You"))
                .font(StrandFont.overline).foregroundStyle(PerformanceDesign.coach)
            Markdown(message.text).markdownTheme(.strand)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(message.role == .user ? NoopMetrics.space3 : 0)
        .background(message.role == .user ? PerformanceDesign.coach.opacity(0.08) : .clear,
                    in: RoundedRectangle(cornerRadius: PerformanceDesign.panelRadius))
    }

    private var composer: some View {
        VStack(spacing: NoopMetrics.space2) {
            HStack(alignment: .bottom, spacing: NoopMetrics.space2) {
                TextField(String(localized: "Ask NROOP anything…"), text: $draft, axis: .vertical)
                    .font(StrandFont.body).lineLimit(1...5).focused($inputFocused)
                    .disabled(!engine.isConfigured || engine.sending || !enabled)
                Button { send(draft) } label: {
                    Image(systemName: "arrow.up").font(StrandFont.headline)
                        .frame(width: PerformanceDesign.controlDiameter, height: PerformanceDesign.controlDiameter)
                        .background(PerformanceDesign.coach, in: RoundedRectangle(cornerRadius: PerformanceDesign.panelRadius))
                        .foregroundStyle(PerformanceDesign.bottom)
                }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || engine.sending || !engine.isConfigured || !enabled)
                    .accessibilityLabel("Send question")
            }
            .padding(NoopMetrics.space3)
            .background(PerformanceDesign.coach.opacity(0.08), in: RoundedRectangle(cornerRadius: PerformanceDesign.panelRadius))
            Text(settings.dataConsent
                 ? String(localized: "Only a dated text summary is shared with your configured provider.")
                 : String(localized: "Measurement sharing is off."))
                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary).multilineTextAlignment(.center)
        }.padding(NoopMetrics.space4)
    }

    private func send(_ question: String) {
        guard enabled, engine.isConfigured, !engine.sending else { return }
        let text = String(question.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4000))
        guard !text.isEmpty else { return }
        draft = ""
        inputFocused = false
        Task { await engine.send(text, screenContext: session.context) }
    }
}

struct PerformanceTabBar: View {
    @Binding var selection: Int
    let coachEnabled: Bool
    let openCoach: () -> Void
    @EnvironmentObject private var router: NavRouter
    private let tabs: [(Int, LocalizedStringKey, String)] = [(0,"Home","house"),(1,"Health","heart"),(4,"More","ellipsis")]
    var body: some View {
        HStack(spacing: NoopMetrics.space2) {
            HStack(spacing: NoopMetrics.space1) {
                ForEach(tabs, id: \.0) { tag, title, symbol in
                    if tag == 4 {
                        Button { router.requestQuickActions() } label: {
                            Image(systemName: "plus.circle.fill").font(StrandFont.title2)
                                .frame(maxWidth: .infinity, minHeight: PerformanceDesign.navigationHeight)
                        }.buttonStyle(.plain).accessibilityLabel("Quick actions")
                    }
                    Button { selection = tag } label: {
                        VStack(spacing: NoopMetrics.space1) {
                            Image(systemName: symbol).font(StrandFont.headline)
                            Text(title).font(StrandFont.overline).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(selection == tag ? StrandPalette.textPrimary : StrandPalette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: PerformanceDesign.navigationHeight)
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityAddTraits(selection == tag ? .isSelected : [])
                }
            }
            .padding(.horizontal, NoopMetrics.space2)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: PerformanceDesign.navigationRadius))
            .overlay(RoundedRectangle(cornerRadius: PerformanceDesign.navigationRadius).strokeBorder(PerformanceDesign.coach.opacity(0.14), lineWidth: NoopMetrics.hairlineWidth))
            if coachEnabled {
                Button(action: openCoach) { PerformanceCoachSymbol(diameter: 50).shadow(color: .black.opacity(0.4), radius: 6, y: 2).frame(width: PerformanceDesign.coachDiameter + 6, height: PerformanceDesign.navigationHeight) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open contextual Coach")
            }
        }
    }
}
#endif
