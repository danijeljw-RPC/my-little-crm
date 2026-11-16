# Browser demo

A disposable, fully working copy of My Little CRM that runs in the browser
(#30). It is the real app (the same screens, services and SQLite schema),
compiled to WebAssembly and started in **demo mode**.

## What demo mode does

Demo mode is a compile-time flag:

```sh
flutter build web --release --wasm --dart-define=DEMO_MODE=true
```

Every web build is a demo, with or without the flag (`isDemoMode` in
`lib/demo/demo_mode.dart`): the browser has no persistent storage for a real
ledger. On native platforms the flag gives the same demo for screenshots and
sales calls.

In demo mode the app:

- opens `AppDatabase.inMemory()` and **never** the real `crm.sqlite` file, so
  real user data cannot be read or changed;
- seeds it with fictional sample parties, interactions, reference numbers,
  commitments and follow-ups (`lib/demo/demo_data.dart`). Dates are relative to
  today, so there are always overdue, due-today, upcoming and completed
  follow-ups;
- shows a permanent banner: *Demo Mode: This is a temporary demonstration of
  My Little CRM. Any changes you make will be discarded when you refresh or
  close this page.*

Everything else works as normal: create, edit, move, merge and delete records,
search, follow-ups, and the responsive layouts. Changes last while you move
between screens and are gone after a refresh, or after closing and reopening
the tab.

## How the browser database works

`lib/data/local/app_database.dart` holds all the SQL. Opening a database is
chosen by conditional import:

| File | Used on | Opens |
| --- | --- | --- |
| `database_opener_io.dart` | Android, iOS, macOS, Windows, Linux | the `crm.sqlite` file (native sqflite or FFI), or `:memory:` |
| `database_opener_web.dart` | Web | `:memory:` only |

On the web, SQLite runs as WebAssembly (`web/sqlite3.wasm`) through
`sqflite_common_ffi_web` with `inMemory: true` and `noWebWorker: true`:

- nothing goes to IndexedDB, OPFS, localStorage or sessionStorage;
- no shared worker, so another open tab can't keep the data alive across a
  refresh, and two tabs never share a demo.

There is no backend, API, account or sign-in.

## Native-only features in the browser

| Feature | In the browser |
| --- | --- |
| Export everything (JSON) / PDF report / party PDF | Downloads the file through the browser. The PDF is laid out on the page's thread, since browsers have no Dart isolates. |
| Import an export | Works, but only into an empty ledger, as on native. Delete the sample parties first. |
| Persistent storage | None, by design. |

## Build and run locally

`web/sqlite3.wasm` is not committed. It is fetched at the version pinned by
`pubspec.lock`:

```sh
scripts/web-demo.sh            # setup + release Wasm build + serve on :8080
scripts/web-demo.sh 9000       # same, on another port
scripts/web-demo.sh build      # build only (output in build/web)
scripts/web-demo.sh serve      # serve an existing build
```

For development with hot reload, `scripts/run.sh chrome` (or
`.\scripts\run.ps1 chrome`) fetches the Wasm binary if needed, then runs the
demo in a debug build.

## Continuous integration

The `Flutter validation / Web demo (Wasm)` job builds the release Wasm demo
on every pull request. It checks the static site, then uploads it as the
`web-demo` artifact: a ready-to-host folder. The job uses no secrets, and
`DEMO_MODE` is the only `--dart-define`. Deployment is not automated.

## Hosting requirements

The output in `build/web` is a static site. Any static host works if it
sends:

- `Content-Type: application/wasm` for `*.wasm`.
- `Cross-Origin-Opener-Policy: same-origin` and
  `Cross-Origin-Embedder-Policy: require-corp` on every response. These make
  the page cross-origin isolated, so Flutter can use its faster multi-threaded
  Wasm renderer. Without them the app still runs, single-threaded.
- HTTPS (any public host), which WebAssembly and service workers expect.

`web/_headers` sets these for Cloudflare Pages and Netlify, and Flutter copies
it into the build. Browsers without WebAssembly GC (older Safari and Firefox)
load the JavaScript build that is shipped alongside it automatically.
