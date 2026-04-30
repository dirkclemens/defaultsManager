# defaultsManager

A native macOS app for browsing, editing, backing up, and restoring macOS `defaults` settings — the same hidden preferences that power users manage via the `defaults` command-line tool.

> ⚠️ **Use with caution.** Changing system defaults can affect the stability and behavior of macOS. Always create a backup before making changes.

---

## Features

- **Browse 234 curated settings** across 25 categories and 51 macOS domains
- **3-column layout** — category → setting → detail
- **Live system values** — reads the actual current value from your system
- **Edit values** with context-aware controls (toggle, segmented, radio, text field)
- **Documented defaults** — each entry includes description, type, and the Apple-documented default value
- **Backup & Restore**
  - Per-entry backup/restore in the detail view
  - Full-system backup via `defaults export` (one plist per domain)
  - Full-system restore via `defaults import`
- **Restart prompts** — after applying a change, the app tells you what needs to restart (Dock, Finder, SystemUIServer) and lets you do it with one click
- **System Settings deep links** — jump directly to the related preference pane
- **Source links** — each entry links to the community source where it was documented
- **Editable database** — the settings database is a plain JSON file stored in `~/Library/Application Support/defaultsManager/`. Add your own entries or modify existing ones; the app merges updates from new app versions without overwriting your customisations.

---

## Screenshots

![screenshot](./screenshot.png)

---

## Requirements

| | |
|---|---|
| **macOS** | 14.0 (Sonoma) or later |
| **Architecture** | Apple Silicon & Intel |

---

## Installation

### Build from source

1. Clone the repository:
   ```bash
   git clone https://github.com/dirkclemens/defaultsManager.git
   cd defaultsManager
   ```
2. Open `defaultsManager.xcodeproj` in Xcode.
3. Select the **defaultsManager** scheme and your Mac as the run destination.
4. Press **⌘R** to build and run.

> **Note:** The app requires `ENABLE_APP_SANDBOX = NO` to send signals to system processes (Finder, Dock, SystemUIServer) and to run `defaults export/import`. This is intentional for a developer tool of this nature.

---

## Usage

### Browsing settings

Select a **category** in the left sidebar, then a **setting** in the middle column to see its full detail — description, current system value, documented default, and sources.

### Editing a value

1. Open a setting in the detail view.
2. Use the editor (toggle, radio buttons, or text field) to set the new value.
3. Click **Apply** (or ⌘↩).
4. If a restart is required (e.g. Dock, Finder), a banner appears with a **Restart Now** button.

### Backup & Restore

| Action | Where |
|---|---|
| Back up a single setting | Detail view → *Backup Current Value* |
| Restore a single setting | Detail view → *Restore* |
| Back up all settings | Toolbar → *Backup All* |
| Restore all settings | Toolbar → *Restore All* |

**Backup All** exports every domain as a `.plist` file to:
```
~/Library/Application Support/defaultsManager/domain_backup/
```

**Restore All** re-imports all exported plists via `defaults import`.

### Editing the settings database

Click **Edit Parameters JSON** in the toolbar to reveal `macos-defaults.json` in Finder. The file is a JSON array of objects:

```json
{
  "domain": "com.apple.dock",
  "key": "autohide",
  "value": "false",
  "type": "bool",
  "category": "Dock",
  "description": "Automatically hide and show the Dock.",
  "all_values": ["false", "true"],
  "sources": ["https://macos-defaults.com/dock/autohide.html"],
  "settings_url": "x-apple.systempreferences:com.apple.preference.dock",
  "restart_action": "Dock"
}
```

| Field | Required | Description |
|---|---|---|
| `domain` | ✅ | Preference domain (e.g. `com.apple.dock`, `NSGlobalDomain`) |
| `key` | ✅ | Defaults key name |
| `value` | ✅ | Documented default value |
| `type` | ✅ | `bool`, `integer`, `float`, `string`, `array`, `dict`, `data` |
| `category` | ✅ | Sidebar category name |
| `description` | | Human-readable description |
| `all_values` | | Array of allowed values — rendered as radio buttons |
| `sources` | | Array of reference URLs |
| `settings_url` | | `x-apple.systempreferences:` deep link |
| `restart_action` | | `Dock`, `Finder`, `SystemUIServer`, `logout`, or `none` |

When the app updates, new entries are merged in automatically. Your existing entries and edits are never overwritten.

---

## Architecture

```
defaultsManager/
├── Models.swift                # DefaultEntry, DefaultValueType, BackupEntry
├── DefaultsStore.swift         # Loads & merges JSON; exposes entries & categories
├── BackupManager.swift         # Per-entry and full-domain backup/restore
├── ApplyManager.swift          # Wraps `defaults read/write` CLI
├── RestartActionResolver.swift # Maps entries → restart actions; performs kill(pid, SIGTERM)
├── SettingsURLResolver.swift   # Maps domains → System Settings deep links
├── ContentView.swift           # Root NavigationSplitView + toolbar + progress modal
├── DomainListView.swift        # Left column — category list with icons
├── KeyListView.swift           # Middle column — searchable entry list
└── DetailView.swift            # Right column — current value, editor, backup, restart banner
```

### Settings database

`macos-defaults.json` is bundled with the app and copied to Application Support on first launch. Sources:

| Source | Description | Entries |
|---|---|---|
| [macos-defaults.com](https://macos-defaults.com) | Community-maintained, well-documented defaults reference | 36 |
| [mathiasbynens/dotfiles](https://github.com/mathiasbynens/dotfiles/blob/main/.macos) | The canonical macOS dotfiles reference, widely used in the community | — |
| [FrancesCoronel/dotfiles](https://github.com/FrancesCoronel/dotfiles/blob/master/init/.osx) | Community dotfiles with additional macOS tweaks | — |
| [jessfraz/dotfiles](https://github.com/jessfraz/dotfiles/blob/master/bin/macos-defaults) | Developer-focused macOS defaults collection | — |
| [SixArm/macos-defaults](https://github.com/SixArm/macos-defaults/blob/main/macos-defaults) | Curated macOS defaults reference list | — |
| [ChristopherA/macOS defaults gist](https://gist.github.com/ChristopherA/98628f8cd00c94f11ee6035d53b0d3c6) | Annotated gist of macOS preference keys | — |

among many other sources ...
---

## Contributing

Pull requests are welcome. To add or correct entries in the settings database, edit `defaultsManager/macos-defaults.json` and open a PR.

Please verify any new `defaults` key against actual macOS behavior before submitting.

---

## License

MIT — see [LICENSE](LICENSE) for details.
