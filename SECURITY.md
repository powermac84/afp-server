# Security and data handling

AFP Server is a local controller for Netatalk. Netatalk provides the AFP server and authentication stack; this app does not add encryption to AFP traffic. Use it on a trusted local network, and choose authentication methods appropriate for the clients you actually need.

## Privileges and changes

The GUI and Homebrew package operations run as the logged-in user. Merely opening the app does not request administrator access. Explicit server, account, configuration, or authentication-setup actions can invoke the native helper through macOS administrator authorization. Do not run the GUI as root.

The helper accepts a defined set of operations and validates request ownership, file types, and private permissions. Passwords are transferred through a private FIFO and are not placed in command arguments or intentionally written to the activity log. Password reset and account removal are restricted to sharing accounts marked as created by this app.

Optional GUI login, Netatalk boot startup, and metadata care are separate controls. Installing or updating Netatalk does not enable them. Package changes require a verified stopped server; the updater does not disconnect clients automatically.

## Package trust

Update checks contact the official Netatalk GitHub release endpoint over HTTPS. The installer accepts published stable releases and requires Homebrew's version, source URL, and source SHA-256 metadata to match the upstream release. Homebrew performs package download and verification. These checks do not replace trust in Homebrew, Netatalk, or their dependencies.

Updates require a click. Automatic checks run approximately daily while the app is open and can be disabled. A known installation outside Homebrew is not automatically replaced. If Homebrew has not caught up with the upstream release, the operation stops and explains the mismatch.

Missing PAM setup is a separate, authorized operation. It accepts the supported OpenDirectory policy and creates the dedicated Netatalk policy only when absent. A differing existing policy is preserved; the app does not recursively change system-directory ownership.

## Configuration and shared files

Configuration changes make backups and check for concurrent edits. Writes are staged and replaced atomically; restart failures trigger a rollback attempt. A failed rollback is reported, with the backup retained. A backup and a rollback attempt are not a substitute for your own recoverable backup.

Metadata restoration is scoped to the selected share. It copies only missing native attributes from existing AppleDouble data after verified backup, retains the source sidecars, and leaves conflicting native metadata unchanged. It cannot reconstruct resource-fork bytes that no longer exist. Restoration pauses when connected clients or unreadable session status prevent an idle-state decision.

Import uses a private staging directory, checks source stability and destination recognition, compares data and native metadata, and publishes with Netatalk's non-overwrite move. Failed or conflicting imports retain staging for inspection. CNID checks require an offline server; repair additionally requires a recognized backup location. The app does not perform a blind forced database reset.

Descriptor-based checks reduce symlink, hardlink, mount, and copy-race hazards. External `nad` still receives pathname arguments, so the app does not promise complete protection against deliberate concurrent path manipulation by a user with the same filesystem permissions. Treat the local app bundle and configuration as trusted administrative inputs.

## Logs and reports

Local diagnostics can contain account names, file paths, addresses, and server output. Review and redact them before sharing. Do not attach passwords, full account records, private configurations, or unreviewed diagnostic archives to a public issue.

For a sensitive vulnerability, use GitHub's private vulnerability-reporting option if it is enabled for this repository. Otherwise request a private reporting channel in an issue without posting secrets or exploit details. Include the app version, macOS version, and a minimal description of the affected operation.

See [VALIDATION.md](VALIDATION.md) for the tests actually performed and their limits.
