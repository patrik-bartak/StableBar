# Contributing

## Setup

Requires macOS 14+ and Xcode's Swift 6 toolchain. Optional workspace widgets require AeroSpace 0.21+ or yabai on your login shell's `PATH`.

Quit the running app before rebuilding its bundle.

```sh
./scripts/build.sh
open dist/StableBar.app
```

Local app builds show **Development** in **Settings → General → Updates**, with the source revision and a `-dirty` suffix when the checkout has changes. A local rebuild of beta source is still a development build; install the beta DMG for its published version and build number.

A development build registers the same `stablebar://` link scheme as the installed app, so macOS may open a source's join link or a package link in either one.

For development checks:

```sh
swift build
swift test
```

Node.js is needed only for the local release tooling and commit message check. `npm ci` installs them, and `npx commitlint --from origin/main` checks your commits before you push.

[t3.json](t3.json) defines project scripts: it builds each new worktree in the background and adds **Test** and **Build app**. Coding agents read [AGENTS.md](AGENTS.md); `CLAUDE.md` points Claude Code to it.

### Build an installer

Install [create-dmg](https://github.com/create-dmg/create-dmg) once with `brew install create-dmg`, then run:

```sh
./scripts/package.sh
```

This creates `dist/StableBar.dmg` with a custom background and the app beside an Applications shortcut. It builds in a temporary directory, leaving a running `dist/StableBar.app` untouched. The app and installer target the build Mac's processor family.

Local builds are ad-hoc signed. For public distribution without an unidentified-developer warning, use a Developer ID Application certificate and a saved `notarytool` keychain profile:

```sh
SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE='stablebar-notary' ./scripts/package.sh
```

The script signs with the hardened runtime, submits the DMG to Apple, then staples and validates its notarization ticket. See [Apple's notarization guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) for certificate and keychain-profile setup. A local DMG is suitable for development; building it alone does not make it a notarized release.

## Architecture

- [Configuration.swift](Sources/StableBar/Configuration.swift): config, widget definitions and style inheritance.
- [StyleResolution.swift](Sources/StableBar/StyleResolution.swift): style layers and states resolved in one place for bar widgets, workspace cells, layout blocks and the bar, and the rules that set data states.
- [WidgetLabel.swift](Sources/StableBar/WidgetLabel.swift): what each widget type shows and the default layout it draws.
- [BarStore.swift](Sources/StableBar/BarStore.swift): live reload, shared provider lifetimes, visibility, sleep and each widget's resolved style.
- [ConfigurationLoader.swift](Sources/StableBar/ConfigurationLoader.swift): includes, profiles, tokens and provenance.
- [ConfigurationEdits.swift](Sources/StableBar/ConfigurationEdits.swift): file-preserving edits shared by CLI and editor.
- [RuntimeControl.swift](Sources/StableBar/RuntimeControl.swift): local request/reply control endpoint.
- [ConfigurationEditor.swift](Sources/StableBar/ConfigurationEditor.swift): preview, undo/redo and validated persistence.
- [NativeMetrics.swift](Sources/StableBar/NativeMetrics.swift): CPU, memory, network and calendar readings.
- [AudioMonitor.swift](Sources/StableBar/AudioMonitor.swift): output-device readings and CoreAudio change listeners.
- [PowerMonitor.swift](Sources/StableBar/PowerMonitor.swift): battery readings and power-change notifications.
- [WidgetPackage.swift](Sources/StableBar/WidgetPackage.swift): package inspection, installation, store downloads and version selection.
- [Workspaces.swift](Sources/StableBar/Workspaces.swift): AeroSpace subscriptions, yabai refreshes and workspace actions.
- [Yabai.swift](Sources/StableBar/Yabai.swift): yabai snapshots mapped to workspaces and screen numbers.
- [ScriptWidget.swift](Sources/StableBar/ScriptWidget.swift): the runner that applies a data source's output, with diagnostics, retries and suspension.
- [DataSource.swift](Sources/StableBar/DataSource.swift): the data source protocol, and the command, stream, polling and push sources.
- [DataSourceRegistry.swift](Sources/StableBar/DataSourceRegistry.swift): each data source type, the settings it reads, how it runs and the access it needs.
- [BuiltInEvents.swift](Sources/StableBar/BuiltInEvents.swift): the events StableBar sends itself and what `INFO` holds.
- [BarView.swift](Sources/StableBar/BarView.swift): native rendering and selection animation.
- [LayoutConfiguration.swift](Sources/StableBar/LayoutConfiguration.swift): groups, priority overflow and notch-aware placement.
- [PopupConfiguration.swift](Sources/StableBar/PopupConfiguration.swift): popup layout blocks.
- [PopupView.swift](Sources/StableBar/PopupView.swift): shared popup rendering and script bindings.
- [WidgetPopup.swift](Sources/StableBar/WidgetPopup.swift): anchored panel, dismissal and screen placement.
- [StableBarApp.swift](Sources/StableBar/StableBarApp.swift): non-activating panels and application lifecycle.

There is no web view, custom drawing loop or private window-server API. Styling and data updates are separate from window placement. Performance and long-term stability still need measurement with your actual widgets and displays.

## How we work

1. **Start from an issue** for every `fix`, `feat` or `perf` change, using the issue forms, and link it from the pull request. The [triage skill](#agent-skills) checks whether a report is already tracked, fixed or supported. Other changes, such as CI, tests or docs, can go straight to a pull request.
2. **Branch from `main` and open a pull request.** Nobody pushes to `main` directly. Fill in the template: the problem, the changes, how you tested them and how to merge. Upload screenshots of visible changes to the pull request instead of committing them.
3. **Keep one problem per pull request.** Unrelated fixes and cleanups get their own.
4. **Wait for CI.** The `Test` job must pass before merging ([Commits and releases](#commits-and-releases) describes the checks).
5. **Merge** with a merge commit, a rebase merge or a squash merge. Use a Conventional Commit title when squashing.

Reviews are requested automatically from the people listed in [CODEOWNERS](.github/CODEOWNERS), but they are not required. Ask for one when a change is risky or outside your usual area.

## Commits and releases

This fork runs only the **Test** CI job on pull requests, pushes to `main` and manual requests through **Actions → CI → Run workflow**. It checks shell script syntax, compiles the Swift package with its tests and runs the full test suite on macOS. Swift build products are cached between runs. A newer run on the same ref cancels the older run.

CI does not create downloadable builds or installers, render documentation images, publish beta or stable releases, deploy the website, or update the upstream Homebrew tap. The local build, packaging and release scripts remain available; see [Build an installer](#build-an-installer) for manual packaging.

Use [Conventional Commits](https://www.conventionalcommits.org) for commit messages and pull request titles. You can run commitlint locally; CI does not check commit messages or titles.

## Docs images

`scripts/render-docs-images.sh` draws the images in `docs/images` from the app's own bar, popup and Settings views, with sample data and a fixed time, and writes them as WebP. It needs `cwebp`: `brew install webp`. Run the script manually when documentation images need updating; this fork does not render or commit them through CI. To show something new, add a scene to [DocsImages.swift](Sources/StableBar/DocsImages.swift).

## Agent skills

Skills for coding agents live in [.agents/skills](.agents/skills), one folder per skill with a `SKILL.md`. Codex reads that directory, and `.claude/skills` links to it for Claude Code. Invoke a skill by name (`/triage` in Claude Code, `$triage` in Codex) or describe the task and let the agent choose it.

| Skill | Use |
| --- | --- |
| [triage](.agents/skills/triage/SKILL.md) | Checks a bug report or feature request against issues, pull requests, `main` and releases, and drafts a GitHub issue when nothing covers it. It posts only what you asked it to file or approved. |

To add a skill, create `.agents/skills/<name>/SKILL.md` with `name` and `description` front matter.

## Security

Report vulnerabilities privately, as described in [SECURITY.md](.github/SECURITY.md).
