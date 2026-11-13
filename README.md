# Ollama Balance

<img width="408" height="531" alt="image" src="https://github.com/user-attachments/assets/de0e87f9-ef7e-485e-bd99-c55641239be0" />


A small macOS app and WidgetKit widget that show your remaining Ollama Cloud balance, included allowance, purchased credit, and renewal date using API key in the login Keychain.

<!-- screenshot here -->

## Requirements

- macOS 14 or later
- An [Ollama Cloud](https://ollama.com/cloud) account and API key

## Install

### Option A: Download a release

1. Download the latest `OllamaBalance-<version>.dmg` from **Releases**.
2. Open the DMG and drag **Ollama Balance.app** onto the **Applications** link.
3. Eject the DMG, then open the app from `/Applications`.

Development-signed downloads are not notarized. If Gatekeeper blocks the app, see [Troubleshooting](#troubleshooting).

### Option B: Build from source

```bash
git clone https://github.com/YOUR_USERNAME/OllamaUsageTracker.git
cd OllamaUsageTracker
open OllamaUsageTracker.xcodeproj
```

In Xcode, select the project and set your signing team for the app and widget under **Signing & Capabilities**. Select the `OllamaUsageRemainingBalanceWidget` scheme and press **⌘R** to run the widget, or run `OllamaUsageTracker` to open the setup panel.

## Setup

### 1. Store your API key

Open Terminal and run:

```bash
security add-generic-password -s ollama-api -a widget -w
```

Terminal prompts for the key. Paste your Ollama API key into Terminal, not into the app window. On the widget's first read, choose **Always Allow** when macOS asks for Keychain access.

To rotate an existing key, delete the old item and add the replacement:

```bash
security delete-generic-password -s ollama-api   # key rotation
```

```bash
security add-generic-password -s ollama-api -a widget -w
```

### 2. Add the widget

Click the **clock in the menu bar** → **Edit Widgets** → **+** → search for **Ollama Cloud Balance** → add the Small or Medium widget.

### 3. Test the connection

Open the app and use **Test connection**. The test runs only when clicked and displays the remaining balance, included allowance, and renewal date.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Widget is not in the picker | Run the widget scheme once, then log out of macOS and log back in before checking the picker again. |
| Widget shows “Invalid API key” | Rotate the key with the commands in [Setup](#setup), then click **Re-check** in the app. |
| Keychain prompts again after rebuilding | Click **Always Allow** again; a newly signed build can have a different code-signing identity. |
| macOS says the app is “damaged” | Right-click the app and choose **Open**. If needed, run the `xattr` command below. |
| API returns HTTP 401 | The key is invalid or expired. Rotate it and verify that the new item uses service `ollama-api` and account `widget`. |
| Connection test fails | If the widget works but the app says “A server with the specified hostname could not be found”, the app sandbox was missing the outgoing-network entitlement (`com.apple.security.network.client`). It is enabled in the project now — rebuild with Xcode. Otherwise check the network connection and confirm that `https://ollama.com/api/balance` is reachable. |

Gatekeeper workaround:

```bash
xattr -cr "/Applications/Ollama Balance.app"     # Gatekeeper fix
```

## Release a new version

Create, verify, and mount-test a DMG with one command:

```bash
make release VERSION=1.1
```

The DMG is written to `dist/`. Edit `RELEASE_TEMPLATE.md`, then use the exact `gh release create` command printed by the script.

Other useful commands:

```bash
make build
make clean
```

## Privacy

Your API key lives only in your local login Keychain. The app and widget send it only to `ollama.com` as the authorization credential for the balance request. This repository contains no API keys or other secrets.

## Attribution, version, and license

Created by **Khoa Nguyen**. Current release: **1.1**. Distributed under the [MIT License](LICENSE). The license copyright is `2026 Khoa Nguyen`; adjust the name in `LICENSE` if you publish a fork or need a different attribution.
