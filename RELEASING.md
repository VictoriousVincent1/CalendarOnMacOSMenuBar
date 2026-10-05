# Releasing MenuCal

## Before every release

1. Bump the version in Xcode: select the **MenuCal** target → **General** → *Version* (e.g. `1.1`) and *Build* (must go up every upload: `2`, `3`, …).
2. Run it once (⌘R) and check the menu bar, calendar, reminders and calendar picker.
3. Commit and push.

## Mac App Store

### One-time setup

1. **Create the app record.** In [App Store Connect](https://appstoreconnect.apple.com) → **Apps** → **+** → **New App**:
   - Platform: **macOS**
   - Name: **MenuCal** (if taken, try e.g. *MenuCal – Calendar & Reminders*)
   - Bundle ID: **com.vincentwu.MenuCal**. If it isn't listed yet, run a build in Xcode first, or register it under *Certificates, Identifiers & Profiles → Identifiers*.
   - SKU: anything unique, e.g. `menucal`
2. **App Privacy** → *Get Started* → **Data Not Collected**.
3. **Privacy Policy URL:** link to the README's Privacy section, e.g. `https://github.com/VictoriousVincent1/CalendarOnMacOSMenuBar#privacy`.
4. **Category:** Productivity.

### Upload a build

1. In Xcode, set the run destination to **Any Mac**.
2. **Product → Archive.** The Organizer opens when it's done.
3. **Distribute App → App Store Connect → Distribute.** Xcode creates the distribution certificate and profile automatically.
4. Wait for the "ready" email (typically 10–30 minutes), then choose the build on the version page in App Store Connect.

### Store listing

- **Screenshots:** at least one at 1280×800, 1440×900, 2560×1600 or 2880×1800. Open the panel and capture with ⌘⇧4, then Space, then click the menu bar panel, or take a full-screen shot and crop to size.
- **Description, keywords, support URL** (the GitHub repo works).
- **App Review notes.** Reviewers often miss menu bar apps, so spell it out:
  > MenuCal is a menu bar app with no Dock icon or window. After launch, click the calendar icon in the top-right menu bar. It asks for Calendar and Reminders access to show events and reminders. No account or login is needed.

Then **Add for Review → Submit**. Review usually takes 1–3 days.

## Direct download (outside the App Store)

To share a zip without the "unverified developer" warning:

1. **Product → Archive**
2. **Distribute App → Direct Distribution → Distribute.** Xcode signs it with your Developer ID and sends it to Apple for notarization.
3. When it finishes, **Export** the app, zip it (`ditto -c -k --keepParent MenuCal.app MenuCal.zip`) and attach it to a GitHub Release.

`./build.sh --zip` still works for quick tests, but its zip is unsigned, so users must click *Open Anyway*.
