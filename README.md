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

## Your own catalog

`~/Library/Application Support/Cleaner/catalog.json` holds the edits that are
yours to make. It is written by the app and safe to edit by hand; a file that
cannot be parsed is reported in the window rather than ignored.

```json
{
  "disabled": ["agentVM", "logs"],
  "folders": [
    { "title": "My renders",
      "path": "~/Library/Caches/MyTool",
      "consequence": "Recomputed on the next render" }
  ]
}
```

`disabled` leaves built-in categories out, and a category that is out stops
widening what may be deleted as well as disappearing from the list. `folders`
adds directories of your own; the toolbar button adds one through a panel, and
a category's context menu removes it.

Every path is validated on **every** read, not only when it is added, because
the file can be edited by hand and a path that was a folder last week can be a
symlink into Documents today. A path is refused when it is outside your home
folder, is your home folder, touches the never-touch list, is not a folder, or
sits inside a built-in category's territory — the last because the same bytes
counted in two categories is a bug, not a feature.

The built-in categories are deliberately **not** in this file. Five of the
fourteen are computed rather than listed — a search for cache directories by
name, the rule that identifies abandoned applications, filters over a
directory listing — and moving them into data would mean inventing a small
language for describing what to delete. That is a poor thing to invent, and a
worse thing to expose to hand-editing.

## Safety model

The priority is keeping data, not cleaning thoroughly.

**The Trash only.** Removal goes through `FileManager.trashItem`, so Finder's
regular "Put Back" works. The app has no permanent deletion at all.

**An allow list, not a deny list.** `PathGuard` admits a path only if it is
absolute, not a symlink, free of `..`, strictly inside an allowed root and not
equal to the root itself. The allowed roots are exactly the category roots, so
only their contents can go.

**Direct children only.** `PathGuard` admits a path exactly one component
below an allowed root, never deeper. Everything the scanner offers is a direct
child by construction, so nothing legitimate is lost — and without this, one
broad root such as `Application Support`, which the leftovers category needs,
would quietly stand in for most of the Library.

**A never-touch list on top of the allow list,** compared in both directions:
you can neither delete something forbidden nor delete a directory that has
something forbidden inside it. `Xcode/` cannot go because `Archives` lives
there. On the list: `Documents`, `Desktop`, `Downloads`, iCloud Drive, Photos,
Mail, Messages, Keychains, `~/.ssh`, device backups, `Xcode/Archives`,
`Xcode/UserData`, `~/.Trash`, and `~/Projects` — source code is never junk.

Comparison is by path component rather than by string: a string prefix would
read `CachesOther` as part of `Caches`.

**Leftovers are judged by identifier, never by name.** Only directories macOS
names after a bundle identifier are ever considered — `Containers`,
`Group Containers`, `HTTPStorages`, `Saved Application State` and the
identifier-shaped folders in `Application Support`. A folder called `Notion`
is never judged, because there is nothing to check it against, and guessing
from an application's name is how a cleaner deletes the data of software you
still use.

Matching runs both ways against every installed bundle identifier plus
LaunchServices: a group container named `dev.warp` belongs to an application
that answers to `dev.warp.Warp-Stable`, and an extension named
`notion.id.NotionSafariExtension` belongs to `notion.id`. Checking one way
called both of them abandoned while their application sat in the Dock —
measured, then fixed. On top of that a finding must have sat untouched for
180 days: below that the list filled with live command line tools and helpers
that simply have no application bundle for the system to find.

If the system cannot even resolve Finder, every other answer is worthless
too, so the lookup claims everything and reports nothing. Naming a whole
application directory widens what `PathGuard` permits, so `Remover` re-runs
the rule against the state of the disk at the moment of removal, not the
state at scan time.

This one is about tidiness rather than space: on the machine it was written
on it finds about 32 MB across a hundred directories, most of them empty
shells. It is listed last for that reason.

**Found by name, not by a list of applications.** Chromium and Electron give
their caches the same handful of directory names, so the catalog searches
`Application Support` for those names four levels down instead of naming
applications one by one. On the machine this was written on that reaches 147
directories holding 5.2 GB across Notion, Figma, Postman, TradingView and
others — including applications installed after this was written. A match ends
the descent, because Chromium nests a `Code Cache` inside `Cache` and counting
both would count the same files twice. A test asserts no root is claimed by
two categories, which is the same double-counting bug seen from the other end.

**A scan can be stopped.** Measuring `DerivedData` walks a lot of files, so
progress is reported per category and `allocatedSize` checks for cancellation
as it walks — a scan the user is still waiting on is not a cancelled one.
Stopping keeps whatever the previous scan found rather than emptying the
window, and stopping the very first scan lands on a state that says so
instead of a spinner that never resolves.

**Biggest first.** Categories are ordered by size rather than by catalog
order: the reason to open this app is at the top of the list. Marks survive a
rescan, so refreshing the numbers does not undo what was ticked.

**Found, next to what the disk has.** The footer names free and total space,
and the purgeable figure when there is over a gigabyte of it — that gap is
what explains a Mac reporting little free room and then finding some.

**Holds, not silent skips.** A finding stays visible but cannot be selected
when removing it now would be a bad idea, and the row says which of the two
reasons applies. `AppAttribution` reads the owning application out of the path
itself — `Library/Containers/com.apple.Safari/…` names its owner, whereas
`DerivedData/…` names nobody and is never attributed by guesswork — and holds
it while that application runs. The second reason is cost: where a fresh
timestamp means a large download was just paid for, the finding waits
(`minimumIdleDays`). Cache categories carry no age rule on purpose, measured
rather than assumed: a cache directory's timestamp moves whenever anything
inside it is touched, so a blanket rule held back every finding and turned
those categories off.

**The Trash is not freed space.** Moving 20 GB there frees nothing until the
Trash is emptied, so the report says exactly that and shows what the Trash
holds. The app never empties it — that would be the one irreversible act this
design exists to avoid. `~/.Trash` is on the never-touch list as well.

**An unreadable folder is not an empty one.** Without Full Disk Access macOS
hides directories, and a scan that counted them as empty would report a tidy
Mac nobody looked at. `CategoryScan.unreadableRoots` keeps them apart and the
window says the totals are a floor.

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
| Caches inside application data | `Cache`, `Code Cache`, `GPUCache` and kin found by name under `Application Support` | Rebuilt; settings and documents stay |
| Caches of sandboxed applications | `Containers/*/Data/Library/Caches` | Rebuilt on next launch |
| Downloaded models and runtimes | `~/.cache/huggingface`, `codex-runtimes`, `uv` | Downloaded again on demand |
| Application logs | `~/Library/Logs` | Only useful while diagnosing |
| Left behind by removed applications | Identifier-named folders no installed application answers to, untouched 180 days | Settings of software you removed |
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
