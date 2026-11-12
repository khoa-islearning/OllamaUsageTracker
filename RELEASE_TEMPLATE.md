# Ollama Balance <version>

## What's new

- <!-- Add user-facing changes here. -->

## Download

- Asset: `OllamaBalance-<version>.dmg`
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
