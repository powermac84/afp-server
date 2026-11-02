# Validation

These results describe work actually run on a local Mac. They are a test record, not a guarantee for every Mac, filesystem, Netatalk release, or Classic client.

## Functional baseline

The functionality carried into the public release was validated in **AFP Server 1.4.0 on 30 October 2026**, using Apple Silicon, macOS 27.2, Xcode 27.2, and Apple's macOS 27.2 SDK. Netatalk 4.6.1 was installed through Homebrew.

Public-release verification is recorded separately below. These baseline results must not be read as a test of a later binary merely because it contains the same functionality.

| Check | Observed result |
| --- | --- |
| Native Xcode tests | 24 XCTest methods passed; zero failures. |
| AddressSanitizer + UndefinedBehaviorSanitizer | The same 24 methods passed; no reported sanitizer findings. |
| Test coverage by suite | 3 core/layout methods, 1 administrative safety method, 14 metadata/import methods, and 6 package methods. Several methods contain multiple checks. |
| Objective-C layout regression | The native object-header layout guard and repeated configuration initialization/release checks passed. The core self-check remains on the normal launch path. |
| AppleDouble/path parser | 17,604 assertions and 100,000 malformed-input fuzz cases passed with both sanitizers. |
| AppKit and LaunchServices | All eight pages were built, rendered, and visually reviewed. Table values, control targets, read-only discovery, and the embedded helper self-check passed. |
| Ordinary app launch | The app opened from Downloads without test arguments, completed launching, and displayed a normal window. |
| Local signatures and ZIP | Strict recursive code-signing verification passed for the app, its embedded helper, and the app extracted from the ZIP. The extracted app's core self-check also passed. |

The administrative test exercises twelve checks on disposable files, including stale-write rejection, symlink/hardlink refusal, password-channel permissions, and create-only PAM policy handling. Package tests include five disposable configuration backup/migration cases.

## Public release 1.4.1

The public source replaces personal account and network examples with generic examples and updates the app version to 1.4.1. The following checks were repeated on **2 November 2026** on the same Apple Silicon/macOS 27.2/Xcode 27.2 environment:

| Check | Observed result |
| --- | --- |
| Native Xcode tests | All 24 XCTest methods passed; zero failures. |
| AddressSanitizer + UndefinedBehaviorSanitizer | All 24 methods passed; zero failures and no reported sanitizer findings. |
| Release build | Xcode completed the Release build successfully. |
| Architectures | `lipo -archs` reported both `x86_64` and `arm64` for the app executable and its embedded helper. Only the Apple Silicon code was run locally. |

This record does not repeat the real AFP server or `nad` integration checks listed below; those belong to the 1.4.0 functional baseline. A successful source build and test suite alone do not establish download, ZIP extraction, signature verification, or launch on another Mac.

## Real Netatalk checks

**AFP handshake:** Homebrew's Netatalk test started a temporary server using its own configuration and an available TCP port. `asip-status` received the expected AFP reply. The test server was stopped afterward.

**Live release check:** The app's native update backend contacted the official Netatalk release endpoint, identified installed and stable versions as 4.6.1, and confirmed matching Homebrew source metadata. The existing PAM configuration matched the packaged policy. The installer backend's already-current path returned successfully without reinstalling or starting the server.

**Real metadata import:** An isolated SQLite-backed test share exercised actual `nad` destination recognition, copy, and move operations. After import:

- `nad` reported file type `TEXT`, creator `ttxt`, and an assigned CNID.
- A MacBinary export contained the expected 21-byte data fork.
- Its 8-byte resource fork matched the original bytes exactly.
- No AFP/CNID test process remained afterward. Existing shares were not used for these writes.

This test exposed and led to a fix for native FinderInfo/resource-fork loss when importing a source outside an AFP volume. The app now preserves missing native attributes on the staged copy before final verification and publication.

## Not established by these tests

- Classic Mac login, password authentication, Finder appearance, and a complete Classic-client file-transfer session.
- Intel execution or compatibility with older macOS releases. The deployment target alone is not evidence of runtime compatibility.
- Launch of the downloaded binary on a different Mac. The distributed local build is ad-hoc signed, not Developer-ID notarized.
- A real future Netatalk version upgrade: the installed version was already current. Release/formula validation and backup/migration behavior were tested, but an actual version transition was not available.
- Live changes to existing accounts, ACLs, share data, startup registrations, or a production CNID database. Privileged PAM creation was tested on disposable files; the real machine already had a matching policy.
- Full resistance to a malicious local user changing pathnames while an external `nad` process operates.

Machine-specific logs, account details, addresses, and crash reports are intentionally excluded from this public test summary.


### Final 1.4.1 download artifact

On 2 November 2026, the public Release build also passed:

- Strict recursive code-signature verification of the app and embedded helper.
- The 23-check core self-test in both the main executable and embedded helper.
- LaunchServices launch, read-only local discovery and rendering of all eight AppKit pages. All eight rendered pages were visually inspected for clipping and overlaps. No server/account changes were made by this UI test; it does not establish an AFP listener.
- A binary/source check for the development machine's private home path, private network example and account placeholder; none were present in the publication set.
- ZIP integrity testing, extraction and strict recursive signature verification of the extracted app.

The release archive contains the app only. Debug-symbol bundles, private test reports, live screenshots, account details, configuration files and backups are excluded. Its SHA-256 is published alongside it. These checks do not establish Gatekeeper acceptance or runtime compatibility on another Mac.
