# Ollama Balance 1.1

## What's new

- Initial public release: Notification-Center widget (Small/Medium) showing your Ollama Cloud remaining balance, allowance progress, purchased credit, and renewal date.
- Auto-refresh every 15 minutes; turns **orange above 80% spent**, with a purchased-credit chip as a visual differentiator.
- Host app doubles as a self-service setup panel: key-presence detection (no prompts at launch), one-click copyable Terminal commands, troubleshooting, and an on-click **Test connection**.
- One-command release pipeline: `make release VERSION=x.y` → verified DMG with GitHub Release commands printed.
- Zero third-party Swift dependencies; the API key lives only in your local login Keychain.

## Download

- Asset: `OllamaBalance-1.1.dmg`
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
