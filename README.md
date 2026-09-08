# Cleaner

[Українською](README.uk.md)

A native macOS app for clearing out developer junk. A list of categories,
checkboxes, one button. Nothing is erased for good — only the Trash.

The interface ships in English and Ukrainian and follows the system language.

## Liability

**This program deletes files. Keeping them safe is your responsibility.**

The author is not liable for lost data, broken builds, ruined projects or any
other damage caused by using this program, whether direct or indirect. That is
the MIT licence talking, not a figure of speech: the software is provided
"as is", without warranty of any kind.

Run it only if you understand what it removes. Before your first clean-up, look
through the list and read what each category costs — that is exactly what those
captions in the interface are for. The Simulators tab deletes permanently,
bypassing the Trash: a mistake there cannot be undone.

The precautions inside — a path allow list, a never-touch list, revalidation
before removal, the Trash instead of erasure — reduce the risk but do not
remove it. A backup remains your job: make sure Time Machine or another backup
actually works before you start clearing disk space.

## Building

```bash
./make.sh test    # run the tests
./make.sh build   # build the app
./make.sh run     # build and launch
./make.sh loc     # check the string catalogs against the code
```

The icon is produced by a script: `swift tools/make-icon.swift` redraws every
PNG under `Cleaner/Resources/Assets.xcassets`. You edit code, not a picture.

`make.sh` always runs `tuist generate` first. That is not superstition: Tuist
freezes the file list at generation time, so without this step a new `.swift`
silently stays out of the build — and the tests then "pass" simply by not
existing.

## Layout

```
CleanerKit/       logic: PathGuard, Catalog, DiskScanner, Remover, simulators
CleanerKitTests/
Cleaner/          the SwiftUI app and its resources
tools/            icon generator, localization check
legacy/           the predecessor — the maccleaner.sh shell utility
```

`CleanerKit` does not import SwiftUI, and the app does not touch the file
system directly. The logic is verified by tests without opening a window.

## Localization

Two languages: English (the source language) and Ukrainian. Strings live in
string catalogs — `Cleaner/Resources/Localizable.xcstrings` for the interface
and `CleanerKit/Resources/Localizable.xcstrings` for the category names and
error texts the framework owns.

Counted nouns are separate strings with exactly one numeric argument
(`%lld items`, `%lld days`, `%lld devices`), because Ukrainian needs
one/few/many forms and a plural rule can only key off a single number.

`./make.sh loc` compares both catalogs against the keys the compiler actually
emits. This matters more than it sounds: Swift builds keys from interpolation,
so `Text("Selected \(a) · \(b)")` becomes `Selected %@ · %@`, not
`Selected %1$@ · %2$@`. A hand-written entry that guesses wrong never matches
and fails quietly — the app simply shows English.

## Menu bar

The app also lives in the menu bar. The panel there shows what has piled up per
category, lets you tick the categories you want gone, and removes them after a
confirmation shown in the panel itself.

That confirmation is deliberate. Sending you to the main window to confirm would
defeat the point of cleaning from the menu bar; skipping it would break the rule
the rest of the app is built on. So the panel asks, in place.

**Run in the background only** drops the Dock icon and keeps the app in the menu
bar. `WindowGroup` opens a window at launch whatever the preferences say, so in
background mode `AppDelegate` closes that launch window and switches the
activation policy before it can settle in — otherwise "menu bar only" would
still start with a window on screen.

Closing the window never quits the app: the menu bar item stays, and quitting is
an explicit choice in the panel.

## Safety model

The priority is keeping data, not cleaning thoroughly.

**The Trash only.** Removal goes through `FileManager.trashItem`, so Finder's
regular "Put Back" works. The app has no permanent deletion at all.

**An allow list, not a deny list.** `PathGuard` admits a path only if it is
absolute, not a symlink, free of `..`, strictly inside an allowed root and not
equal to the root itself. The allowed roots are exactly the category roots, so
only their contents can go.

**A never-touch list on top of the allow list,** compared in both directions:
you can neither delete something forbidden nor delete a directory that has
something forbidden inside it. `Xcode/` cannot go because `Archives` lives
there. On the list: `Documents`, `Desktop`, `Downloads`, iCloud Drive, Photos,
Mail, Messages, Keychains, `~/.ssh`, device backups, `Xcode/Archives`,
`Xcode/UserData`, and `~/Projects` — source code is never junk.

Comparison is by path component rather than by string: a string prefix would
read `CachesOther` as part of `Caches`.

**Revalidation before removal.** `Remover` does not trust the scan and puts
every path through `PathGuard` again immediately before moving it: minutes pass
between the scan and the button press.

**Nothing is selected by default.** A failure on one path does not stop the
rest — the report is assembled per item.

## Files

The Files tab is reversible cleaning: everything goes to the Trash.

A category expands into the individual findings: name, size, modification date.
You can mark anything — a single file, a group, or the whole category. The
category checkbox shows a partial state when only some of it is selected, and
clicking it completes the rest.

Categories with several roots show groups first: in "Package manager caches"
the name `content-v2` says nothing on its own, but under the heading
`.npm/_cacache` it does.

| Category | What it is | Consequence |
|---|---|---|
| Xcode DerivedData | Indexes and intermediate builds | The next build is slower |
| Device symbols | `iOS/watchOS/tvOS DeviceSupport` | Re-downloaded when a device connects |
| Package manager caches | npm, Yarn, pnpm, pip, CocoaPods, Gradle | The next install is slower |
| XcodeBuildMCP test products and logs | Finished test runs under `workspaces/*` | Build state is left in place |
| SwiftPM and documentation cache | `org.swift.swiftpm`, `DocumentationCache` | Re-downloaded |
| Application caches | Xcode, JetBrains, VS Code, Chrome, Homebrew, playwright and others | Apps rebuild their cache |
| Simulator builds made by Claude | `Application Support/Claude/simulator-builds` | Recreated on the next build |
| Claude sandbox virtual machine | `Application Support/Claude/vm_bundles` | Several GB downloaded again |
| Desktop app caches | Claude and VS Code caches, cached `.vsix` installers | Rebuilt; installed extensions stay |
| Downloaded models and runtimes | `~/.cache/huggingface`, `codex-runtimes`, `uv` | Downloaded again on demand |
| Application logs | `~/Library/Logs` | Only useful while diagnosing |
| Downloaded updates | `*.ShipIt` directories in `~/Library/Caches` | Downloaded again if needed |

The `*.ShipIt` list is derived from what the directory actually contains rather
than fixed as a constant: everyone has a different set of apps.

## Simulators

The Simulators tab is separate **because removal here is irreversible**. A
simulator directory is tied to the CoreSimulator database, so it cannot be
moved to the Trash without leaving that database out of sync. `simctl` does the
deleting, and it bypasses the Trash.

Hence the different rules in this section:

- **Select unused** marks what is demonstrably dead: devices whose runtime is
  not installed, and runtimes no device uses.
- A running simulator cannot be deleted — shut it down first.
- A runtime marked `Deletable: NO` is protected by the system.
- Confirmation requires ticking "I understand this does not go to the Trash"
  separately; an ordinary click is not enough.

Parsing of `simctl` output is verified against recorded fixtures, including
names with parentheses such as `iPad Pro 13-inch (M5)`: splitting on
parentheses would read `M5` as the UDID.

## Sandbox

App Sandbox is off deliberately: inside it `~/Library/Developer` is unreachable
unless the user picks every folder by hand. This is a local tool, not something
for the App Store.

## Licence

MIT — see [LICENSE](LICENSE).
