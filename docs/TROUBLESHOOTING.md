# Troubleshooting

[← Overview](../README.md)

## The pad types keys instead of shortcuts

Confirm the selected device, native mode, learned input and enabled shortcuts. Press Apply shortcuts. Check Accessibility and Input Monitoring for the **installed** app. Hubs can reset mappings without changing device IDs; reconnect recovery verifies/reapplies them. Inspect `runtime-status.json` in the app-support folder.

Keep the same signing identity when updating. If macOS genuinely rejects a stale permission entry, refresh that specific entry and reopen; do not routinely clear TCC databases. Ad-hoc rebuilds can invalidate approvals. F11/F14/F15 are intentionally excluded from relay keys because of Show Desktop/brightness conflicts.

## Laptop shortcuts do nothing / conflict with an editor

Enable MacBook shortcuts in Setup. Command–Option–7 is physical **8** (Claude), not whole-desk setup. Hold Command–Option alone for the guide. Quitting/disabling releases registrations. Some editors use Command–Option–brackets for folding/indentation; adjust your assignments if needed. Secure input can suspend global shortcuts.

## Windows open on the wrong screen

Desktop workspace actions use the pointer's display; media prefers Sidecar; TV uses its own selected display. Mobile workspace actions use native Spaces. These are intentionally different rules. Check extended vs mirrored display configuration and the TV target. Persistent TV selection uses UUIDs, not transient numeric IDs.

## GDN fullscreen is not visible

Resume/select its real player first, then use TV Full screen. Keep the TV home and watch rail out of the player's fullscreen Space. Avoid calling shared-layout placement in response to every Space notification. If a player is stuck in in-window fullscreen, Escape can reset it. The page's “Exit Fullscreen” label alone is not proof that the native window is fullscreen.

## The MacBook is black

Click the black Mac screen or use Show Mac screen from the phone. End TV/disconnect to restore it. Blacking out is optional and off by default in the public build.

## The phone cannot connect

Use the current URL from the Mac UI, same local network, awake host and port 9472. Check VPN/guest Wi-Fi isolation/firewall, certificate trust and pairing approval. USB is not sufficient. Reopen/refresh the PWA after an app update. Do not disable certificate validation or port-forward the server.

## Audio slider unavailable / captions late

Some outputs control their volume in hardware. Pair AirPods in macOS first. Captions are experimental; turn them off if timing is unsuitable. They are separate from streaming-service subtitle tracks.

## Diagnostic files

In `~/Library/Application Support/Mini Keyboard/`: `runtime-status.json`, `tv-display-status.json`, `tv-caption-status.json`, `mobile-space-status.json`, `media-layout-status.json`. They can help isolate routing/permission state. Do not publish your entire app-support folder when filing an issue.
