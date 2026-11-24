import SwiftUI
import Network
import ServiceManagement

enum Status {
    case idle, ok([Window]), failed(String)
}

@MainActor
final class Model: ObservableObject {
    static let refreshIntervals = [5, 10, 15, 30]
    private static let refreshIntervalKey = "refreshIntervalMinutes"

    @Published var refreshIntervalMinutes: Int {
        didSet {
            UserDefaults.standard.set(refreshIntervalMinutes, forKey: Self.refreshIntervalKey)
            scheduleAutoRefresh()
        }
    }

    @Published var country: String?
    @Published var geoKnown = false
    @Published var claude: Status = .idle
    @Published var codex: Status = .idle
    @Published var updatedAt: Date?
    @Published var loading = false
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled {
        didSet {
            guard launchAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do { launchAtLogin ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
            catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
        }
    }

    private var timer: Timer?
    private let monitor = NWPathMonitor()
    private var pendingNetRefresh: Task<Void, Never>?

    /// Запросы к лимитам разрешены только если страна определена и это не РФ.
    var allowed: Bool { geoKnown && country != nil && country != "RU" }

    init() {
        let savedInterval = UserDefaults.standard.integer(forKey: Self.refreshIntervalKey)
        refreshIntervalMinutes = Self.refreshIntervals.contains(savedInterval) ? savedInterval : 5
        // смена сети / включение-выключение VPN → перепроверить страну
        monitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor in self?.scheduleNetRefresh() }
        }
        monitor.start(queue: .global(qos: .utility))
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.scheduleNetRefresh() } }
        // NWPathMonitor вызывает обработчик и при запуске.
    }

    private func scheduleAutoRefresh() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(refreshIntervalMinutes * 60), repeats: false) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    private func scheduleNetRefresh() {
        pendingNetRefresh?.cancel()
        pendingNetRefresh = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { await refresh() }
        }
    }

    func refresh() async {
        guard !loading else { return }
        loading = true
        defer {
            loading = false
            scheduleAutoRefresh()
        }

        // страна проверяется прямо перед каждым запросом
        country = await Geo.country()
        geoKnown = true
        guard allowed else {
            claude = .idle
            codex = .idle
            return
        }
        async let c = Self.wrap { try await Claude.fetch() }
        async let x = Self.wrap { try await Codex.fetch() }
        (claude, codex) = await (c, x)
        updatedAt = Date()
    }

    private nonisolated static func wrap(_ f: () async throws -> [Window]) async -> Status {
        do { return .ok(try await f()) } catch { return .failed(error.localizedDescription) }
    }

    var labelImage: NSImage {
        if !geoKnown { return StatusImage.text("…") }
        guard let country else { return StatusImage.text("IP? ⏸") }
        if country == "RU" { return StatusImage.text("RU ⏸") }
        let c = values(claude, count: 2)
        var cx = codex
        if case .ok(let ws) = codex, let week = ws.first(where: { $0.name == "Неделя" }) { cx = .ok([week]) }
        return StatusImage.limits(claude: (c[0], c[1]), codex: values(cx, count: 1)[0])
    }

    private func values(_ s: Status, count: Int) -> [String] {
        switch s {
        case .idle: return Array(repeating: "…", count: count)
        case .failed: return Array(repeating: "!", count: count)
        case .ok(let ws):
            return (0..<count).map { $0 < ws.count ? fmtPercent(ws[$0].percent) : "–" }
        }
    }
}

@main
struct LimitsBarApp: App {
    @StateObject private var model = Model()

    var body: some Scene {
        MenuBarExtra {
            Panel(model: model)
        } label: {
            Image(nsImage: model.labelImage)
        }
        .menuBarExtraStyle(.window)
    }
}

struct Panel: View {
    @ObservedObject var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            geoRow
            if model.allowed {
                section("Claude", model.claude)
                section("Codex", model.codex)
            }
            Divider()
            HStack {
                if let t = model.updatedAt {
                    Text("Обновлено \(t.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(model.loading ? "…" : "Обновить") { Task { await model.refresh() } }
                    .disabled(model.loading)
            }
            Picker("Автообновление", selection: $model.refreshIntervalMinutes) {
                ForEach(Model.refreshIntervals, id: \.self) { minutes in
                    Text("\(minutes) мин").tag(minutes)
                }
            }
            Toggle("Запускать при входе", isOn: $model.launchAtLogin)
            Button("Выйти") { NSApp.terminate(nil) }
        }
        .padding(14)
        .frame(width: 280)
    }

    @ViewBuilder private var geoRow: some View {
        if !model.geoKnown {
            Text("Проверяю IP…").foregroundStyle(.secondary)
        } else if let c = model.country {
            if c == "RU" {
                Label("IP в РФ — запросы лимитов на паузе", systemImage: "pause.circle")
                    .foregroundStyle(.orange)
            } else {
                Text("IP: \(c)").font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Label("Не удалось определить страну IP — запросы на паузе", systemImage: "questionmark.circle")
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder private func section(_ title: String, _ s: Status) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            switch s {
            case .idle:
                Text("…").foregroundStyle(.secondary)
            case .failed(let m):
                Text(m).font(.caption).foregroundStyle(.red)
            case .ok(let ws):
                ForEach(ws) { w in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(w.name).font(.caption)
                            Spacer()
                            Text(fmtPercent(w.percent)).font(.caption).monospacedDigit()
                        }
                        ProgressView(value: min(w.percent, 100), total: 100).tint(color(w.percent))
                        if let r = w.resetsAt {
                            Text("сброс \(r.formatted(.relative(presentation: .named)))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func color(_ p: Double) -> Color { p >= 90 ? .red : p >= 70 ? .orange : .green }
}
