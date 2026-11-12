import AppKit
import Security
import SwiftUI

private enum SetupCommand {
    static let addKey = "security add-generic-password -s ollama-api -a widget -w"
    static let deleteKey = "security delete-generic-password -s ollama-api"
    static let repairGatekeeper = "xattr -cr \"/Applications/Ollama Balance.app\""
}

private enum KeychainPresence {
    case unchecked
    case found
    case locked
    case missing
    case error(OSStatus)
}

struct SetupPanel: View {
    @State private var keychainPresence: KeychainPresence = .unchecked
    @State private var hasCheckedOnAppear = false
    @State private var isStep1Expanded = true
    @State private var isStep2Expanded = false
    @State private var isStep3Expanded = false
    @State private var showsRotateKey = false
    @State private var showsTroubleshooting = false
    @State private var isTesting = false
    @State private var testMessage: String?
    @State private var testSucceeded = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statusRow
                    setupSteps
                    troubleshooting(proxy: proxy)
                    connectionTest
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            guard !hasCheckedOnAppear else { return }
            hasCheckedOnAppear = true
            refreshKeychainPresence()
        }
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            Image(systemName: statusSymbol)
                .foregroundStyle(statusColor)
                .imageScale(.large)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.headline)
                if case .error(let status) = keychainPresence {
                    Text("Keychain returned error \(status).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
            Button("Re-check", action: refreshKeychainPresence)
                .controlSize(.small)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var setupSteps: some View {
        VStack(spacing: 12) {
            SetupCard(number: 1, title: "Store your API key", isExpanded: $isStep1Expanded) {
                Text("Run this command in Terminal:")
                    .font(.callout)
                CommandBox(command: SetupCommand.addKey)
                Text("Terminal will prompt for the key. Paste your Ollama API key there—never in this window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(showsRotateKey ? "Hide rotate key" : "Rotate key") {
                    showsRotateKey.toggle()
                }
                .controlSize(.small)

                if showsRotateKey {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("To replace an existing key, delete the old item, then add the new one:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        CommandBox(command: SetupCommand.deleteKey)
                        CommandBox(command: SetupCommand.addKey)
                    }
                    .padding(.top, 4)
                }
            }
            .id("step-1")

            SetupCard(number: 2, title: "Add the widget", isExpanded: $isStep2Expanded) {
                Text("Click the clock in the menu bar → Edit Widgets → + → search “Ollama Cloud Balance” → add (Small/Medium).")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SetupCard(number: 3, title: "Approve once", isExpanded: $isStep3Expanded) {
                Text("On the widget’s or app’s first Keychain read, macOS may ask for access. Click Always Allow. This approval is required and only needs to be done once.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func troubleshooting(proxy: ScrollViewProxy) -> some View {
        DisclosureGroup(isExpanded: $showsTroubleshooting) {
            VStack(spacing: 8) {
                TroubleshootingRow(title: "“App is damaged” / Gatekeeper") {
                    Text("In Finder, right-click the app and choose Open. If needed, run:")
                        .font(.callout)
                    CommandBox(command: SetupCommand.repairGatekeeper)
                }

                TroubleshootingRow(title: "Widget missing from the picker") {
                    Text("Log out and back in, or run the widget once from Xcode, then check the widget picker again.")
                        .font(.callout)
                }

                TroubleshootingRow(title: "“Invalid API key” on the widget") {
                    Text("Rotate the API key using Step 1, then use Re-check above.")
                        .font(.callout)
                    Button("Show Step 1 rotate instructions") {
                        isStep1Expanded = true
                        showsRotateKey = true
                        withAnimation {
                            proxy.scrollTo("step-1", anchor: .top)
                        }
                    }
                    .controlSize(.small)
                }
            }
            .padding(.top, 10)
        } label: {
            Label("Troubleshooting", systemImage: "wrench.and.screwdriver")
                .font(.headline)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var connectionTest: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button(action: startConnectionTest) {
                    Text(isTesting ? "Testing…" : "Test connection")
                }
                .disabled(isTesting)

                if isTesting {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let testMessage {
                Text(testMessage)
                    .font(.callout)
                    .foregroundStyle(testSucceeded ? Color.primary : Color.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Optional. This reads your key and contacts Ollama only when you click the button.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var statusTitle: String {
        switch keychainPresence {
        case .unchecked: return "Checking Keychain…"
        case .found: return "API key found in Keychain"
        case .locked: return "API key exists (locked)"
        case .missing: return "No API key yet"
        case .error: return "Keychain status unavailable"
        }
    }

    private var statusSymbol: String {
        switch keychainPresence {
        case .unchecked: return "key.horizontal"
        case .found: return "checkmark.circle.fill"
        case .locked: return "lock.fill"
        case .missing, .error: return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch keychainPresence {
        case .found: return .green
        case .locked, .missing, .error: return .orange
        case .unchecked: return .secondary
        }
    }

    private func refreshKeychainPresence() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "ollama-api",
            kSecAttrAccount as String: "widget",
            kSecReturnData as String: false,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            keychainPresence = .found
        case errSecItemNotFound:
            keychainPresence = .missing
        case errSecInteractionNotAllowed:
            keychainPresence = .locked
        default:
            keychainPresence = .error(status)
        }
    }

    private func startConnectionTest() {
        guard !isTesting else { return }
        isTesting = true
        testMessage = nil
        testSucceeded = false
        Task { await testConnection() }
    }

    private func testConnection() async {
        defer { isTesting = false }

        let keyResult = readAPIKey()
        if keyResult.status == errSecItemNotFound {
            testMessage = "No API key yet — complete Step 1 first."
            return
        }
        if keyResult.status == errSecInteractionNotAllowed {
            testMessage = "Keychain is locked. Unlock it, then try again."
            return
        }
        guard keyResult.status == errSecSuccess else {
            testMessage = "Keychain access failed (error \(keyResult.status))."
            return
        }
        guard let key = keyResult.key, !key.isEmpty else {
            testMessage = "The Keychain item does not contain a readable API key."
            return
        }

        var request = URLRequest(url: URL(string: "https://ollama.com/api/balance")!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                testMessage = "Ollama returned an invalid response."
                return
            }
            if httpResponse.statusCode == 401 {
                testMessage = "Invalid API key — rotate it (Step 1)."
                return
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                testMessage = "Ollama returned HTTP \(httpResponse.statusCode)."
                return
            }

            let balance = try JSONDecoder().decode(HostBalanceResponse.self, from: data)
            guard let renewalDate = parseRenewalDate(balance.included.period.until) else {
                testMessage = "Ollama returned an invalid renewal date."
                return
            }

            let remaining = balance.included.balanceUSD + balance.purchased.balanceUSD
            let renewal = renewalDate.formatted(.dateTime.month(.abbreviated).day())
            testMessage = "\(usd(remaining)) of \(usd(balance.included.allowanceUSD)) · renews \(renewal)"
            testSucceeded = true
        } catch let error as URLError {
            testMessage = "Network error: \(error.localizedDescription)"
        } catch is DecodingError {
            testMessage = "Ollama returned an unexpected balance response."
        } catch {
            testMessage = "Connection failed: \(error.localizedDescription)"
        }
    }

    private func readAPIKey() -> (key: String?, status: OSStatus) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "ollama-api",
            kSecAttrAccount as String: "widget",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return (nil, status) }
        guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            return (nil, errSecSuccess)
        }
        return (key, errSecSuccess)
    }

    private func parseRenewalDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private func usd(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }
}

private struct SetupCard<Content: View>: View {
    let number: Int
    let title: String
    @Binding var isExpanded: Bool
    let content: Content

    init(
        number: Int,
        title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.number = number
        self.title = title
        self._isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content
                .font(.callout)
                .padding(.top, 10)
        } label: {
            HStack(spacing: 10) {
                Text("\(number)")
                    .font(.caption.weight(.bold))
                    .frame(width: 24, height: 24)
                    .background(Color.accentColor.opacity(0.15), in: Circle())
                Text(title)
                    .font(.headline)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct TroubleshootingRow<Content: View>: View {
    let title: String
    @State private var isExpanded = false
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(.top, 8)
        } label: {
            Text(title)
                .font(.callout)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct CommandBox: View {
    let command: String
    @State private var copied = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(command)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(copied ? "Copied ✓" : "Copy", action: copyCommand)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .fixedSize()
        }
        .padding(8)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
    }

    private func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

private struct HostBalanceResponse: Decodable {
    let included: Included
    let purchased: Purchased

    struct Included: Decodable {
        let balanceUSD: Double
        let allowanceUSD: Double
        let period: Period

        enum CodingKeys: String, CodingKey {
            case balanceUSD = "balance_usd"
            case allowanceUSD = "allowance_usd"
            case period
        }
    }

    struct Purchased: Decodable {
        let balanceUSD: Double

        enum CodingKeys: String, CodingKey {
            case balanceUSD = "balance_usd"
        }
    }

    struct Period: Decodable {
        let until: String
    }
}

#Preview {
    SetupPanel()
        .frame(width: 420)
}
