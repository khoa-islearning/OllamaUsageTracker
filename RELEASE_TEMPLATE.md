# Ollama Balance 1.2

## What's new

- Widget now shows a **usage pace line**: "≈ $2.10/day · dry ≈ Dec 20" — computed on-device from a rolling 7-day local history, so you no longer need to open the dashboard to know when you'll run out.
- Host app **Test connection** now records samples too and shows the same pace line + local sample count.
- Tapping the widget opens ollama.com; opening the app reloads the widget timeline instantly (no more stale snapshots after rebuilds).
- Pace appears once two samples exist at least a day apart (warm-up), from the 15-min widget refreshes and manual test clicks.

## Download

- Asset: `OllamaBalance-1.2.dmg`
- Requires **macOS 14+** and an Ollama Cloud account.

## Setup

Store your Ollama API key in the local login Keychain:

```bash
security add-generic-password -s ollama-api -a widget -w
```

Then add **Ollama Cloud Balance** from the macOS widget picker and choose **Always Allow** at the first Keychain prompt.

## Gatekeeper note

This development-signed release is not notarized. If macOS says the app is damaged, right-click it and choose **Open**, or run:

```bash
xattr -cr "/Applications/Ollama Balance.app"
```
