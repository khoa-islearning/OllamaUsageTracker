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
    var error: String? = nil
}

// MARK: - Provider

struct BalanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> BalanceEntry {
        BalanceEntry(date: .now, remaining: 59.89, allowance: 60, renews: "Dec 4")
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
        }
        .configurationDisplayName("Ollama Cloud Balance")
        .description("Shows remaining Ollama Cloud credit and renewal date.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
