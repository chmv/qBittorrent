# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

qBittorrent is a BitTorrent client in C++20 / Qt 6 built on libtorrent-rasterbar. A single CMake build produces the desktop app (`qbittorrent`) or the headless daemon (`qbittorrent-nox`), both optionally embedding a WebUI (HTTP server + REST API). Minimum versions: Qt 6.6.0, libtorrent 1.2.19 / 2.0.10, Boost 1.76, OpenSSL 3.0.2, CMake 3.16. Python >= 3.13 is an optional runtime-only dependency used by the search engine.

## Build & Test Commands

```sh
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DTESTING=ON   # configure
cmake --build build                                                      # build
cmake --build build --target check          # build + run all tests (wraps ctest --output-on-failure)
ctest --test-dir build/test -R testpath     # run one test executable by name
build/test/testpath testConstructors        # run one test function (QtTest CLI)
```

- `enable_testing()` lives in `test/CMakeLists.txt`, not the root, so tests register under `build/test/` — `ctest --test-dir build` finds nothing; use `--test-dir build/test` (the `check` target already runs ctest from there).

- Feature options (root `CMakeLists.txt`): `GUI` (ON), `WEBUI` (ON), `TESTING` (**OFF** — tests don't exist without `-DTESTING=ON`), `STACKTRACE` (ON), `MSVC_RUNTIME_DYNAMIC` (ON, MSVC only).
- `-DGUI=OFF` produces `qbittorrent-nox`. GUI vs headless is a **compile-time** decision (`DISABLE_GUI` / `DISABLE_WEBUI` defines throughout the code); there is no runtime switch.
- Upstream commits no CMake presets or dependency manifest; this fork does (`vcpkg.json`, Windows build presets and scripts). CI builds with warnings-as-errors (`-Werror` / MSVC `/WX`) and `-DQT_FORCE_ASSERTS` — a warning that builds clean locally will fail CI.
- **Windows/MSVC** (verified with VS 2022+/2026 + Qt via [`aqt`](https://github.com/miurahr/aqtinstall)): configure with a vcpkg toolchain and point CMake at Qt, e.g. `-DCMAKE_TOOLCHAIN_FILE=<vcpkg>/scripts/buildsystems/vcpkg.cmake -DVCPKG_TARGET_TRIPLET=x64-windows-static-md -DCMAKE_PREFIX_PATH=<qt>/msvc2022_64`. The `x64-windows-static-md` triplet (static libs + dynamic CRT) is what `MSVC_RUNTIME_DYNAMIC=ON` expects; a plain `x64-windows-static` (`/MT`) triplet causes `RuntimeLibrary` mismatch link errors.
- vcpkg **manifest mode** (`vcpkg.json`): `libtorrent`, `openssl`, `zlib` are not sufficient — qBittorrent `#include`s Boost directly, so the manifest must also list `boost-circular-buffer`, `boost-multi-index`, and `boost-stacktrace` (the last only needed while `STACKTRACE=ON`). libtorrent pulls in boost-asio/-system/etc. but none of these.
- Qt from `aqt`/the official installer is **dynamically linked**: put `<qt>/msvc2022_64/bin` on `PATH` before running the app *or the tests*, otherwise the executables exit immediately with `0xc0000135` (STATUS_DLL_NOT_FOUND). The vcpkg deps use the static triplet, so Qt is the only runtime-DLL dependency.
- Tests are QtTest, cover `base/` utilities only, and live flat in `test/` as `test<area>.cpp` (a QObject with `private slots` test cases + `QTEST_APPLESS_MAIN` + `#include "test<area>.moc"`). A new test file must be added to the `testFiles` list in `test/CMakeLists.txt`.

### WebUI frontend (run in `src/webui/www/`)

```sh
npm install
npm run lint      # eslint + stylelint + html-validate
npm run format    # js-beautify for JS/HTML; prettier for CSS only
npm test          # vitest
```

### Python

- Search engine (`src/searchengine/nova3/` — the only Python lint config in the repo): `uv sync`, then `uv run just check` (mypy + pyright, both strict), `uv run just lint`, `uv run just format`.
- Other repo scripts are checked in CI with pyflakes, bandit, pycodestyle (`--max-line-length=1000`), isort (see `.github/workflows/ci_python.yaml`).

### File health

`pre-commit run --all-files` (CI runs the same config via prek) — editorconfig-checker, codespell, typos, end-of-file fixer, JSON/YAML validation, plus repo-specific checks (grid item order in `.ui` files, `<translation>` tags in `.ts` files).

## Architecture

### Layering (static libs, each in its own `src/` subdir)

| Target | Dir | Role |
|---|---|---|
| `qbt_base` | `src/base/` | All domain logic: libtorrent session, settings, RSS, search, HTTP server, networking, utils. Depends on nothing above it. |
| `qbt_gui` | `src/gui/` | Qt Widgets desktop UI. Links only `qbt_base`. |
| `qbt_webui` | `src/webui/` | REST API + WebUI serving. Links only `qbt_base`. |
| `qbt_app` | `src/app/` | Composition root: `main.cpp`, `Application`, singleton wiring. |

`gui` and `webui` are siblings that never link each other — shared logic belongs in `base`. Includes are rooted at `src/` (`#include "base/bittorrent/session.h"`). Both UIs observe the core via Qt signals from `Session` (`torrentAdded`, `torrentsUpdated`, ...).

### Core patterns

- **Singletons**: services follow `initInstance()` / `freeInstance()` / `instance()` (e.g. `SettingsStorage`, `Preferences`, `Logger`, `BitTorrent::Session`, `Net::DownloadManager`, `SearchPluginManager`). `Application` creates them in a fixed order; several (`RSS::Session`, `AddTorrentManager`, `TorrentFilesWatcher`, `MainWindow`/`WebUI`) are created **only after the async `Session::restored` signal** — don't assume they exist during early startup.
- **Interface/impl split**: `BitTorrent::Session` and `BitTorrent::Torrent` are abstract; concrete `SessionImpl`/`TorrentImpl` are internal. Consume the interfaces (`Session::instance()`).
- **Settings stack**: `SettingsStorage` (thread-safe key→QVariant store with debounced save) → wrapped by `SettingValue<T>`/`CachedSettingValue<T>` (typed access to one key) → `Preferences` (typed getters/setters, emits `changed()`).
- **App access without the concrete type**: non-singleton components (`WebApplication`, `APIController`s, `AddTorrentManager`) derive from `ApplicationComponent<T>` and receive an `IApplication *` (`base/interfaces/iapplication.h`).

### WebUI / WebAPI

- HTTP transport lives in `base/http/`; `WebApplication` (`src/webui/webapplication.{h,cpp}`) does routing, sessions, auth, CSRF/host-header protection.
- Endpoints are `/api/v2/<scope>/<action>`, dispatched **by reflection**: a `void <action>Action()` private slot on the `APIController` subclass for that scope (`src/webui/api/`). Read params via `params()`/`requireParams()`, report errors by throwing `APIError`.
- Adding/changing an endpoint: (1) add the `...Action()` slot; (2) if it mutates state, add it to the POST-only `m_allowedMethod` table in `webapplication.h`; (3) **bump `API_VERSION`** in `webapplication.h`; (4) **add an entry to `WebAPI_Changelog.md`** — steps 3–4 are commonly forgotten, and they apply to upstream contributions only: fork-local API changes are documented in `WebAPI_Changelog.fork.md` instead (see "Fork workflow").
- Frontend (`src/webui/www/`): plain JS, **no build/bundle step**. `public/` = pre-login pages, `private/` = authenticated app. Files are **compiled into the binary via `webui.qrc`** — edits require a rebuild, and new files must be added to `webui.qrc`. For live iteration enable the "alternative WebUI" preference (`Preferences/WebUI/AlternativeUIEnabled` + `RootFolder` pointing to a dir that itself contains `public/` and `private/`). Legacy MooTools is still shipped but new code must be vanilla JS. UI strings use `QBT_TR(...)QBT_TR[CONTEXT=...]` markers translated at serve time; sync WebUI `.ts` files with `src/webui/www/tstool.py`.

### Search engine

Python "nova3" scripts (`src/searchengine/nova3/`) are embedded via `searchengine.qrc` and copied into the user profile at runtime; searches spawn an external Python interpreter (>= 3.13, enforced in `src/base/utils/foreignapps.h` — the `requires-python = ">=3.9"` in nova3's pyproject.toml is not the real floor). Search plugins (`engines/*.py`) are not part of this repo. Per `src/searchengine/README.md`, this subsystem is under review — only major-bug fixes are accepted.

### Generated files

- `src/base/version.h` is generated at configure time and git-ignored — edit `src/base/version.h.in`.
- GUI `.ui` files compile to `ui_*.h` in the build dir; MOC runs automatically.
- Translations: `.ts` → `.qm` at build time. Refresh English sources with the `qbt_update_translations` target (lupdate); **never hand-edit non-English `.ts`** — they come from Transifex. (`src/lang/TRANSLATION_INSTRUCTIONS` is stale; ignore its file references.)
- Man pages: `doc/*/qbittorrent{,-nox}.1.md` are the sources; regenerate the `.1` roff with pandoc and commit **both** (CI diffs them).

## Code Style (enforced on review; full rules in CODING_GUIDELINES.md)

- Allman braces (opening brace on its own line) for everything including `if`/loops; single-statement bodies may omit braces. 4-space indent, UTF-8, LF line endings.
- camelCase names; types/namespaces start uppercase; private members prefixed `m_`.
- Constructor init lists vertical, `:` and `,` leading each line; brace initialization with a space before the brace and none inside: `Class obj {expr};`.
- Include order: module header, C++ std, system, Boost, libtorrent, Qt, then qBittorrent headers (starting with `base/`); alphabetical within each group. `#pragma once`, never include guards.
- `auto` only where strictly necessary or clearly more readable; prefer pre-increment; no method definitions in header files.
- `uncrustify.cfg` (repo root) can format C++; `.clang-tidy` and `.editorconfig` also apply.

### Project idioms

- String literals: `u"..."_s` (`Qt::Literals::StringLiterals`, pulled in by `base/global.h`); `QString` for all text.
- Filesystem paths use the `Path` class (`base/path.h`) and `Utils::Fs`, never raw `QString`; forward-declare via `pathfwd.h`.
- Fallible operations return `nonstd::expected<T, QString>` (`base/3rdparty/expected.hpp`).
- Logging via `LogMsg(...)` (`base/logger.h`); the error severity is `Log::CRITICAL` (libtorrent `#define`s `ERROR`).
- `Utils::*` are namespaces of free functions (`Utils::String`, `Utils::Misc`, `Utils::Net`, ...).

## Commits & PRs

- Subject: imperative mood, capitalized, <= 50 chars, no trailing period; area prefixes are customary (`WebUI:`, `GHA CI:`). Body wrapped at 72 chars explains what/why; reference issues with `Closes #NNNN.`.
- Resolve conflicts by rebasing onto the target branch, not merging.

## Fork workflow

This working copy is the `chmv` fork: `origin` = `chmv/qBittorrent`, `upstream` = official `qbittorrent/qBittorrent`. `master` mirrors upstream's master (refreshed via GitHub "Sync fork", then `git fetch origin`). `chmv-master` is the working branch: a short patch stack riding on `origin/master`, one commit per topic.

- **Sync is always a rebase** onto `origin/master`, never a merge — `git log origin/master..chmv-master` must stay exactly the fork delta. Push after rebase: `git push --force-with-lease origin chmv-master`.
- **Git split** (exception to the global "no git commands" rule): Claude runs sync operations — fetch, rebase, conflicts, branch bookkeeping — everything except `push`, which stays with the user, as do commits of new work.
- **Patch hygiene**: follow-up work is committed on top as usual and folded into its topic commit at the next sync.
- **Fork patches never touch upstream's `WebAPI_Changelog.md` or `API_VERSION`** — claiming upstream's future numbers would mislead version-gated clients. Fork API changes go to `WebAPI_Changelog.fork.md` (own `fork-N` numbering); the server keeps reporting upstream's API version.
- `git rerere` is enabled — a rebase conflict resolved once replays automatically on later syncs.
