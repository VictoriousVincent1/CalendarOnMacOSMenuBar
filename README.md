# MenuCal

A lightweight macOS menu bar app that shows your **next event** right in the menu bar, and opens a panel with a **month calendar**, the **day's events** and your **reminders**.

It reads from the same calendars and reminders as Apple's Calendar and Reminders apps, so it works with **iCloud, Google, Exchange/Outlook, and any other account** you've added to your Mac.

```
📅 3:00 PM Team Standup
```

## Features

- **Next event in the menu bar**: `3:00 PM Team Standup`, `Tomorrow 9:00 AM Dentist`, `Wed 10:30 AM 1:1`
  - or as a countdown: `in 25m Team Standup`, `in 2h 15m Dentist`, `Now · 1:1`
  - optionally switches from the meeting you're in to the next one a set time before it starts (e.g. 30 minutes)
- **Month calendar** with dots on days that have events; click a day to see its events
- **Events** with calendar colors, times and locations
- **Reminders**: overdue ones in red; click the circle to complete, or type to add a new one due today
- **Choose calendars**: show or hide whole accounts (e.g. Google) or individual calendars and reminder lists
- Updates live when anything changes in Calendar or Reminders
- Launch at login, no Dock icon, native SwiftUI, around 1 MB

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon or Intel Mac

## Install

### Option 1: Download the app

**[⬇ Download MenuCal.dmg](https://github.com/VictoriousVincent1/CalendarOnMacOSMenuBar/releases/latest/download/MenuCal.dmg)** (latest version)

1. Open **MenuCal.dmg** and drag **MenuCal** onto the **Applications** folder.
2. Open MenuCal from Applications (or Spotlight). Look for the 📅 in your menu bar.
3. If macOS says it **can't verify the developer**, click **Done**, then go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. You only need to do this once. Or run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/MenuCal.app
   ```
4. Click **Allow** when asked for access to Calendars and Reminders.

### Option 2: Build from source

You need Apple's Swift compiler, which comes with **Xcode** or the free **Command Line Tools**:

```bash
xcode-select --install
```

Then:

```bash
git clone https://github.com/VictoriousVincent1/CalendarOnMacOSMenuBar.git
cd CalendarOnMacOSMenuBar
./build.sh --install
open /Applications/MenuCal.app
```

| Command | What it does |
|---|---|
| `./build.sh` | Builds `build/MenuCal.app` |
| `./build.sh --install` | Builds and copies it to `/Applications` |
| `./build.sh --zip` | Builds and creates `build/MenuCal.zip` for sharing |

**Or with Xcode:** open `MenuCal.xcodeproj`, pick your team under *Signing & Capabilities*, and press ⌘R. (Without Xcode, `build.sh` builds the app without its icon.)

## Usage

- **Click the menu bar item** to open the panel.
- **‹ Today ›** move between months; click any day to see its events.
- **Reminders:** click ○ to complete; type in *New reminder for today* and press Return to add one.
- **Filter icon** (bottom right) or **⚙︎ → Choose Calendars…** picks which accounts and calendars to show.
- **⚙︎ menu:** toggle *Show next event in menu bar* (off shows the date), choose *Menu Bar Shows* start time or time until, *Switch to Next Event* (when the current event ends, or 5–60 minutes before the next), *Launch at login*, open Calendar/Reminders, or quit.

### Adding Google Calendar (or Outlook, etc.)

MenuCal uses the accounts macOS already knows about. To add Google:

1. Open **System Settings → Internet Accounts** (or use the link in MenuCal's calendar picker).
2. Add your **Google** account and turn on **Calendars**.
3. It appears in MenuCal within a few seconds. Use **Choose Calendars…** to show or hide it.

> Google **Tasks** are not synced to macOS Reminders by Google, so they won't appear here.

## Troubleshooting

**No events or reminders appear.** Check **System Settings → Privacy & Security → Calendars** and **→ Reminders**, and make sure MenuCal is set to *Full Access*.

**I clicked "Don't Allow" by mistake.** Enable it in the settings above, or reset the prompt and relaunch:
```bash
tccutil reset Calendar com.vincentwu.MenuCal
tccutil reset Reminders com.vincentwu.MenuCal
```

**Permission prompts come back after rebuilding.** Locally built apps are ad-hoc signed, so macOS may treat each rebuild as a new app. Just allow access again.

**New Google events take a few minutes to appear.** macOS syncs Google on a timer. Open the **Calendar** app → **Settings → Accounts** → your Google account → set **Refresh Calendars** to **Every 1 minute**. MenuCal also asks accounts to sync when you open the panel, click refresh, and every 2 minutes.

**Launch at login doesn't stick.** Make sure the app lives in `/Applications` (use `./build.sh --install`).

## Uninstall

Quit MenuCal from the ⚙︎ menu, then delete `/Applications/MenuCal.app`.

## Project structure

```
MenuCal/
├── Sources/
│   ├── MenuCalApp.swift        # App entry point + menu bar item
│   ├── CalendarModel.swift     # EventKit access, loading, calendar selection
│   └── ContentView.swift       # Panel UI: month grid, events, reminders, picker
├── Resources/
│   ├── Assets.xcassets         # App icon
│   └── PrivacyInfo.xcprivacy   # Privacy manifest: no tracking, no data collected
├── MenuCal.xcodeproj           # Xcode project (App Store builds)
├── MenuCal.entitlements        # App Sandbox: calendar/reminders access only
├── Info.plist                  # Bundle config, privacy strings, no Dock icon
├── build.sh                    # Builds, installs or zips the app without Xcode
├── release.sh                  # Signed + notarized MenuCal.dmg for GitHub Releases
└── RELEASING.md                # How to publish to the Mac App Store
```

## Privacy

MenuCal runs entirely on your Mac. It reads your calendars and reminders through Apple's EventKit and never sends data anywhere. It runs in Apple's App Sandbox with only calendar and reminders access, so macOS itself blocks network and file access.

## License

[MIT](LICENSE)
