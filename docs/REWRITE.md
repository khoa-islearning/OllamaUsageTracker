# The Rewrite — playbook for rebuilding Ollama Balance "the right way"

Goal: rebuild the app from scratch, manually, with industry-standard decisions — and end up at **the same capabilities** with a cleaner foundation. The working repo you're reading this in stays untouched as the **reference** (use it for parity diffs and "why did we do that?" lookups).

**Reading order reference:** `docs/code-walkthrough.html` (all source + side notes) and `docs/how-it-works.html` (architecture + incidents).

---

## Ground rules

1. **Fresh folder, fresh git repo** (e.g. `~/proj/ollama-balance-rewrite`). Reference stays at `~/proj/OllamaUsageTracker/OllamaUsageTracker`.
2. **Same capabilities, not same code.** Verify against this list at the end: widget (Small/Medium, 15-min refresh, pace line, tap → ollama.com), host setup panel (key detection, copyable commands, test connection with samples), release pipeline producing a *verified* DMG, GitHub release flow.
3. **Every step below exists because of a real incident** in the reference build. The mapping table at the bottom ties each step to what it prevents and how to verify it.
4. Time budget: one focused session, **3–5 hours** if you follow the checklist (the release script can be adapted, not rewritten).

---

## Phase 0 — Scaffold (prevents incidents 1 & 2)

1. Xcode → **File ▸ New ▸ Project ▸ macOS ▸ App**. Product `OllamaBalance`, org id `com.khoanguyenpersonalteam`, interface **SwiftUI**, **no** Core Data / tests checkboxes for now.
2. **File ▸ New ▸ Target ▸ Widget Extension** — name `OllamaBalanceWidget`, family Small/Medium, *uncheck* configurable. This template is the point of the phase: it creates the extension **target**, the `Info.plist` with `NSExtensionPointIdentifier = com.apple.widgetkit-extension`, the **Embed Foundation Extensions** copy phase, and the bundle-ID nesting (`…OllamaBalance.OllamaBalanceWidgetExtension`) for you.
   - *If the id differs from `com.khoanguyenpersonalteam.OllamaBalance.OllamaUsageBalanceExtension`, don't fix it manually — that's fine, nesting is what matters.*
3. Verify now, before writing code:
   ```bash
   xcodebuild -list -project OllamaBalance.xcodeproj          # 2 targets
   ⌘R on the widget scheme                                     # renders? containerBackground present in template view
   codesign -dv --entitlements :- <built .app> | plutil -p -    # app-sandbox: true
   ```
   **Incident map:** 1 (missing `INFOPLIST_FILE`) and 2 (un-nested bundle id) are prevented by the template. Verification = the two commands above.

## Phase 1 — Signing & capabilities (prevents incident 5)

For **both** targets, in Signing & Capabilities:

| Capability | Why | Generates |
| --- | --- | --- |
| App Sandbox (on by default) | distribution-safe | `com.apple.security.app-sandbox` |
| **Outgoing network (client)** | balance fetch + sandbox DNS masquerade | `com.apple.security.network.client` |
| **App Groups + `group.com.khoanguyenpersonalteam.OllamaBalance`** | shared storage for pace history | `com.apple.security.application-groups` |
| Keychain Sharing (optional) | only if you later add access groups | `keychain-access-groups` |

Verify with `codesign -d --entitlements :- <bundle> | plutil -p -` — **both** targets must show `network.client`. If the app ever reports *"hostname could not be found"*, that's the sandbox — not DNS.

Signing: team `AVT3QHA97L`, automatic. For personal dev-signed DMGs that's fine; if you ever add a paid membership, switch the release phase to **Developer ID + notarytool** (Phase 5).

## Phase 2 — Shared source (removes our deliberate duplicates)

In the reference we duplicated models (`BalanceResponse` / `HostBalanceResponse`) and the history store because of the folder-based target layout. This time:

1. Create `Shared/` group; add files to **both** targets (File Inspector → Target Membership; the widget template's folder-reference makes this a checkbox, not surgery):
   - `WireModels.swift` — `BalanceResponse` (snake_case) **and** the `BalanceEntry` timeline-entry struct
   - `HistoryStore.swift` — App-Group `UserDefaults`-backed (see note) rolling samples (30-day window, <5-min dedupe, 200 cap) + `pace()` (7-day window, **peak-based** burn so top-ups don't under-count)
   - `API.swift` — `balanceURL`, keychain service/account constants, `keychainRead()` / `probe()` (attributes-only vs secret, returning `Result`)
2. **History via App Group** — the upgrade: `UserDefaults(suiteName: "group.com.khoanguyenpersonalteam.OllamaBalance")` storing a JSON `[Sample]`. Same protocol as the reference's keychain hack, standard mechanism, and no extra consent round-trips. Delete the `ollama-api-history` keychain item from the reference install when you switch:
   ```bash
   security delete-generic-password -s ollama-api-history -a widget
   ```
3. Verify: build once; unit-test the pure parts first (Phase 6) — pace math is now testable for real because it's shared.

## Phase 3 — Widget, top-down in "registry → data → pixels" order

1. **Registration**: `kind = "OllamaBalanceWidget"` (persistence key — don't rename later), `supportedFamilies([.systemSmall, .systemMedium])`, `.widgetURL(URL(string: "https://ollama.com"))` **on the view**, not the configuration.
2. **Data**: `TimelineProvider` — placeholder (realistic demo entry), snapshot, timeline with `policy: .after(now + 15 min)`; on success: **record sample into the App Group**, compute pace, put `paceDay`/`runsOut` on the entry.
3. **Pixels**: containerBackground (template included it — keep), headline currency text, allowance progress clamped with `min(spent/allowance, 1)`, teal pace caption (only if pace exists), purchased-credit chip.
4. Errors as entries; never an empty timeline; no `Date()`/IO in the view body.

**Incident map:** 3 (missing `containerBackground` ⇒ warning card) prevented here. Widget logic otherwise matches reference 1:1 — use Stop 03–07 of the walkthrough as the spec.

## Phase 4 — Host app (UI + the reload mechanism)

1. `MyApp → WindowGroup { ContentView { SetupPanel } }` with the window contract (`380/420/520`).
2. `SetupPanel` exactly as reference Stops 08–15: presence probe (attributes-only), status trio, copyable commands from a single `enum`, troubleshooting, single-flight **Test connection** that records a sample too and shows the sample count.
3. **`WidgetCenter.shared.reloadAllTimelines()`** on appear and after each successful test — this is a *keep* (it fixed the "stale snapshot after rebuild" incident), now trivial because both targets are in the same project again.

## Phase 5 — Release pipeline (industry signing)

Adapt the reference `scripts/make_release.sh` (keep constants/guards, don't re-derive):

1. Version bump, `xcodebuild archive`, export, staging (`ditto` + `/Applications` symlink), `hdiutil` create — as-is.
2. **Keep the verify + mount test** — `hdiutil verify` then attach-and-assert (app symlink, `.appex` inside). Non-negotiable.
3. Signing decision, now explicit:
   - No paid membership → keep `method: development` DMG + the documented `xattr -cr` escape hatch (what we have today).
   - Paid membership → export with profile `Developer ID`, then:
     ```bash
     xcrun notarytool submit dist/OllamaBalance-1.2.dmg \
       --keychain-profile "notary" --wait
     xcrun stapler staple dist/OllamaBalance-1.2.dmg
     ```
4. Then `gh release create vX dist/OllamaBalance-X.dmg --title … --notes-file RELEASE_TEMPLATE.md --latest`.

**Incident map:** 4 (bash 3.2 `set -u` empty-array expansion) prevented by not splicing empty arrays — the reference script already branches signed/unsigned; keep that shape.

## Phase 6 — Quality gates & the parity ritual

Unit tests (new, and arguably the biggest win):
- `pace()` against a fixture: top-up mid-window, flat week, no samples, ≥1-day boundary.
- Decoding: captured `balance.json` fixture → structs.
- Presence: `errSecItemNotFound` → `.missing`, `interactionNotAllowed` → `.locked` (inject the status, don't hit a real keychain).

Parity ritual — run in **both** repo folders and diff:

```bash
xcodebuild -project <proj> -scheme <app-scheme> -destination 'platform=macOS' build
codesign -d --entitlements :- <built .app> | plutil -p -      # diff entitlements
codesign -d --entitlements :- <built .appex> | plutil -p -
make release VERSION=2.0.0-rc && hdiutil verify dist/*.dmg    # mount test included
```

Definition of done:
- [ ] Widget renders small + medium with pace after one cold day of history
- [ ] App launch / test click forces a reload (fresh snapshot in seconds)
- [ ] Entitlements: sandbox + network.client on both targets, app-group on both
- [ ] DMG passes `hdiutil verify` + mount assertions; install-from-DMG works
- [ ] Unit tests green (pace + decode)
- [ ] No keychain history item; history lives in the App Group

---

## Incident → step map

| # | Original incident | Prevented by | Verify |
| --- | --- | --- | --- |
| 1 | Build failed: `INFOPLIST_FILE` pointed at a nonexistent folder | Widget-Extension template (Phase 0) | first build passes |
| 2 | `Embedded binary's bundle identifier is not prefixed with the parent app's` | same | `pluginkit -m -v -i <ext-id>` shows one clean record |
| 3 | Warning card instead of widget (no `containerBackground`; stale registration) | Phase 3 step 3 + install-from-DMG | widget renders after `killall chronod` re-drive |
| 4 | "Stale snapshot after rebuilds" | App holds the reload: `WidgetCenter` on open/test (Phase 4) | open app → fresh timeline in seconds |
| 5 | App test failed with fake DNS error | `network.client` on the app target (Phase 1) | entitlements dump shows it on both targets |

## Known upgrades vs the reference (do NOT copy these backwards)

- Keychain-as-database for pace history → **App Group** (Phase 2)
- Duplicate decoders / twin history stores → **shared source** (Phase 2)
- Dev-signed DMG → **Developer ID + notarytool** when a paid account exists (Phase 5)
- Zero tests → unit tests on the pure layer (Phase 6)

## What we intentionally keep identical

Widget data model, provider contract (exactly-once completion, errors-as-entries), keychain coordinate conventions (`ollama-api` / `widget`), App Sandbox posture, keychain `Always Allow` UX, DMG verify + mount ritual, release ergonomics (`make release VERSION=`).

---

*Reference repo for parity: this one (`main`, tag `v1.1`/`v1.2`). Generated docs: `docs/how-it-works.html`, `docs/code-walkthrough.html`.*
