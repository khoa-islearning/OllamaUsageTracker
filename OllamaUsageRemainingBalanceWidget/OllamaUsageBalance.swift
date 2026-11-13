import WidgetKit
import SwiftUI
import Security

// MARK: - Keychain

enum Keychain {
    static let service = "ollama-api"
    static let account = "widget"

    static func readKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
}

// MARK: - Local usage history (keychain-backed, shared with the host app)

enum HistoryStore {
    static let service = "ollama-api-history"
    static let account = "widget"
    static let window: TimeInterval = 30 * 24 * 3600

    struct Sample: Codable {
        let date: Date
        let remaining: Double
        var purchased: Double = 0
    }

    static func read() -> [Sample] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data,
              let samples = try? JSONDecoder().decode([Sample].self, from: d) else { return [] }
        return samples
    }

    static func record(date: Date, remaining: Double, purchased: Double) {
        var samples = read()
        samples.removeAll { date.timeIntervalSince($0.date) < 5 * 60 }  // new sample supersedes one <5 min old
        samples.append(Sample(date: date, remaining: remaining, purchased: purchased))
        samples = samples.filter { date.timeIntervalSince($0.date) <= window }
        write(Array(samples.suffix(200)))
    }

    static func count() -> Int { read().count }

    /// burn rate from the 7-day window; peak-based so purchased top-ups don't look like "less burn"
    static func pace(now: Date, remaining: Double) -> (perDay: Double, runsOut: Date?)? {
        let week = read().filter { now.timeIntervalSince($0.date) <= 7 * 24 * 3600 }
        guard week.count >= 2, let first = week.first, let last = week.last else { return nil }
        let days = now.timeIntervalSince(first.date) / 86400
        guard days >= 1 else { return nil }
        let peak = week.map(\.remaining).max() ?? first.remaining
        let perDay = max(0, peak - last.remaining) / days
        guard perDay > 0.01 else { return nil }
        return (perDay, now.addingTimeInterval(last.remaining / perDay * 86400))
    }

    private static func write(_ samples: [Sample]) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let data = (try? JSONEncoder().encode(samples)) ?? Data()
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        if SecItemUpdate(base as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var create = base
            create[kSecValueData as String] = data
            create[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(create as CFDictionary, nil)
        }
    }
}

// MARK: - API model (matches ollama.com/api/balance exactly)

struct BalanceResponse: Codable {
    let included: Included
    let purchased: Purchased

    struct Included: Codable {
        let balance_usd: Double
        let allowance_usd: Double
        let period: Period
    }
    struct Purchased: Codable {
        let balance_usd: Double
    }
    struct Period: Codable {
        let from: String
        let until: String
    }
}

struct BalanceEntry: TimelineEntry {
    let date: Date
    var remaining: Double = 0
    var allowance: Double = 0
    var purchased: Double = 0
    var renews: String = ""
    var paceDay: Double = 0
    var runsOut: Date? = nil
    var error: String? = nil
}

// MARK: - Provider

struct BalanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> BalanceEntry {
        BalanceEntry(date: .now, remaining: 59.89, allowance: 60,
                     renews: "Dec 4", paceDay: 2.10,
                     runsOut: .now.addingTimeInterval(14 * 86400))
    }
    func getSnapshot(in context: Context, completion: @escaping (BalanceEntry) -> Void) {
        fetchBalance(completion)
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<BalanceEntry>) -> Void) {
        fetchBalance { entry in
            let next = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func fetchBalance(_ done: @escaping (BalanceEntry) -> Void) {
        guard let key = Keychain.readKey(), !key.isEmpty,
              let url = URL(string: "https://ollama.com/api/balance") else {
            done(BalanceEntry(date: .now,
                error: "No API key in Keychain.\nRun:\nsecurity add-generic-password -s ollama-api -a widget -w"))
            return
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            var entry = BalanceEntry(date: .now)
            if let http = resp as? HTTPURLResponse, http.statusCode == 401 {
                entry.error = "Invalid API key — rotate it and re-run the Keychain command"
            } else if let data,
                      let r = try? JSONDecoder().decode(BalanceResponse.self, from: data) {
                let until = ISO8601DateFormatter().date(from: r.included.period.until)
                entry.remaining = r.included.balance_usd + r.purchased.balance_usd
                entry.allowance = r.included.allowance_usd
                entry.purchased = r.purchased.balance_usd
                entry.renews = until?.formatted(.dateTime.month(.abbreviated).day()) ?? ""
                HistoryStore.record(date: entry.date, remaining: entry.remaining,
                                    purchased: entry.purchased)
                if let pace = HistoryStore.pace(now: entry.date, remaining: entry.remaining) {
                    entry.paceDay = pace.perDay
                    entry.runsOut = pace.runsOut
                }
            } else {
                entry.error = "Fetch failed"
            }
            DispatchQueue.main.async { done(entry) }
        }.resume()
    }
}

// MARK: - View

struct BalanceWidgetView: View {
    var entry: BalanceEntry

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        if let err = entry.error {
            VStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                Text(err)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding()
        } else {
            let spent = entry.allowance - (entry.remaining - entry.purchased)
            let warning = entry.allowance > 0 && spent / entry.allowance > 0.8

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "cloud")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                    Text("Ollama Cloud")
                        .font(.headline)
                    Spacer()
                    if !entry.renews.isEmpty {
                        Text("renews \(entry.renews)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(entry.remaining, format: .currency(code: "USD"))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(warning ? Color.orange : Color.primary)
                if entry.allowance > 0 {
                    ProgressView(value: min(spent / entry.allowance, 1.0))
                        .progressViewStyle(.linear)
                    Text("of \(entry.allowance, format: .currency(code: "USD")) included")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if entry.paceDay > 0, let dry = entry.runsOut {
                    Text("≈ \(entry.paceDay, format: .currency(code: "USD"))/day · dry ≈ \(dry, format: .dateTime.month(.abbreviated).day())")
                        .font(.caption2)
                        .foregroundStyle(.teal)
                }
                if entry.purchased > 0 {
                    Text("+$\(entry.purchased, specifier: "%.2f") purchased credit")
                        .font(.caption2)
                        .foregroundStyle(.teal)
                }
            }
            .padding(12)
        }
    }
}

// MARK: - Widget

@main
struct OllamaBalanceWidget: Widget {
    let kind = "OllamaBalanceWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BalanceProvider()) { entry in
            BalanceWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "https://ollama.com"))
        }
        .configurationDisplayName("Ollama Cloud Balance")
        .description("Remaining Ollama Cloud credit and renewal date, with usage pace.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
