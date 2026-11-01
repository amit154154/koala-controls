# Privacy and permissions

[← Overview](../README.md)

Koala's host keeps settings and progress under `~/Library/Application Support/Mini Keyboard/`. It has no built-in cloud account or analytics backend. Streaming services opened by Koala have their own network/privacy behavior.

The local shortcut journal records action, invocation time, source (pad/laptop/phone/app), keyboard connection snapshot and result. Click and result share an ID. Ordinary typing, passwords, browsing content and credentials are not journaled. Remote text is transmitted to the Mac only when explicitly sent and is not meant to become activity-log content.

Phone identity and peer hashes live in `Phone Remote/`. TLS keys and pairing files are local secrets. They are not source files and are excluded from this repository. Pairing requires a code plus Mac approval; the API validates origin, command kind, bounds, timestamps and rates. The server is optional and local-network oriented. Do not expose it directly to the internet.

Audio capture is opt-in for experimental local captions. The intended pipeline captures selected playback, not microphone input, and does not save a recording or transcript. Initial model assets may need downloading. Caption quality/timing depends on OS and model behavior.

Accessibility enables window control and synthetic input. Input Monitoring supports the selected pad. Grant only the permissions for features you use; see [installation](INSTALL.md). Turning native shortcuts off or quitting restores tracked per-device remaps. Unexpected interrupted mappings have recovery-journal handling.

To remove the software, quit the host and remove both apps. Revoke phone access first if needed. Remove its profile/certificate from the phone if you no longer trust/use that Mac. Deleting local app-support data also removes settings, pairing and progress; back up what you want to retain.
