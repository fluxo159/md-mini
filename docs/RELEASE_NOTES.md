# MD Mini 1.0.2

**Your tabs return after Command-Q.**

- Reopen the previous tab order and selected document at the next launch.
- Restore unsaved edits and untitled drafts without writing over the original files.
- Read clean files fresh from disk; retain conflict protection for recovered edits.
- Recover local text when a file is missing, and avoid duplicating a file opened through Finder.
- Store the session atomically with owner-only permissions. If saving it fails, quit is cancelled.
- Closing a tab explicitly still uses the standard save/discard review. Empty startup tabs are omitted.

Normal quit and relaunch were checked with three tabs, a selected middle tab, and an unsaved draft in another tab. The draft returned and the original file remained unchanged. Automated checks also cover missing files, Finder reopen, persistence failures, and clean-file updates.

Download **MD-Mini-macOS-arm64.zip**, unzip, and replace the installed **MD Mini.app** in Applications. The interface is in Russian; English and Russian instructions are in the repository.

Targets macOS 13+. Tested on macOS 27.2.1 with Swift 6.4.2. Older macOS versions and Intel Macs have not been tested. The binary is signed ad hoc, not Apple-notarized. The archive checksum is in `SHA256SUMS.txt`.

Latest-edit crash recovery is not implemented; the session is saved on normal quit.
