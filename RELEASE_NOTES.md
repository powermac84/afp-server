# AFP Server 1.4.1 — Classic Macs. Modern storage.

Vintage Macs still have things to say. AFP Server gives their file-sharing setup a native control panel on a modern Mac: start the server, choose the right share, see who's connected, keep Netatalk current, and look after the metadata that makes a Classic Mac file a Classic Mac file.

**Netatalk runs the AFP server. AFP Server is the macOS app that manages it.** Clients connect over AFP/TCP/IP.

## What's inside

- A native AppKit app with eight pages for server status, shares, connections, accounts, Classic metadata, settings, diagnostics and updates.
- **Install and update Netatalk from the app** using an existing Homebrew installation. The offered stable version, source URL and SHA-256 must match the official upstream release.
- **Daily update checks while the app is open**, with a manual Check now button. New versions install after your click, with the server stopped.
- Share configuration previews, verified backups, atomic writes, stale-edit protection and restart/rollback feedback.
- Separate GUI login, server boot and metadata-care controls.
- Conservative metadata restoration and verified `nad` import, including native FinderInfo/resource-fork preservation in a private staging folder before the final move.
- A separate administrator helper for explicit privileged actions. The graphical app and Homebrew package operations run as the normal user.

This public release uses generic account/network examples and excludes machine-specific diagnostics, logs and configuration files.

## Download and open

Download **`AFP-Server-1.4.1-macOS.zip`**, extract it and open **AFP Server.app**. Netatalk is installed separately through the app's Updates page; it is not bundled into the download.

This is a **universal macOS development build (Apple Silicon + Intel), ad-hoc signed and not Developer ID notarized**. Local verification used macOS 27.2. The macOS 13+ deployment target does not mean every older OS has been tested, and opening on another Mac has not been verified. Use macOS's individual-app approval flow if needed.

## What changes when you click Install or Update?

The app first requires stopped AFP/CNID daemons and saves verified configuration backups. It refreshes Homebrew metadata, compares it with the official stable release, performs the package operation as your user, then verifies the installed version and preserved settings. A missing supported authentication policy can be completed through a normal macOS administrator prompt.

It leaves the daemon stopped for review. It does not enable boot startup or install a package merely because an update check ran. If Homebrew is behind upstream, it explains the mismatch and leaves the package alone.

## Validation

The 1.4.0 functional baseline passed **24 XCTest methods normally and with ASan/UBSan**, eight-page UI verification, a real AFP protocol test server, and a real `nad` 4.6.1 import whose data and resource forks were checked through MacBinary export. Netatalk 4.6.1 was the tested package on 30 October 2026; the app checks live stable releases rather than pinning that version.

The public 1.4.1 source passed the same **24 tests normally and with ASan/UBSan** on 2 November 2026, and its universal Release build completed. See [VALIDATION.md](https://github.com/powermac84/afp-server/blob/v1.4.1/VALIDATION.md) for the separate baseline and public-release records.

A Classic Mac client/password login, Intel runtime, older-macOS sweep and real future-version package upgrade remain unverified. Use copies for the first metadata maintenance run on your own setup.

Independent project by Patrick Alan Banfield. Built around the work of [Netatalk](https://netatalk.io/) and [Homebrew](https://brew.sh/).
