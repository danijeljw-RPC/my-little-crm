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
scripts/web-demo.sh package    # build + zip for uploading: see Publish below
```

For development with hot reload, `scripts/run.sh chrome` (or
`.\scripts\run.ps1 chrome`) fetches the Wasm binary if needed, then runs the
demo in a debug build.

## Publish

The demo is a static site: a folder of files with no server code, database or
secrets. Build it once, upload the files, and add the headers listed in
step 3.

### 1. Get the files

**Build locally** (needs Flutter and the repo):

```sh
scripts/web-demo.sh package
# ✓ dist/mylittlecrm-demo-1.1.2.zip (17M), 52 files
```

The version in the name comes from `pubspec.yaml`. The same files are also
in `build/web/`.

If the demo will live in a sub-folder (`https://example.com/demo/`) rather
than at the root of a (sub)domain, pass the folder. It must start and end
with `/`:

```sh
scripts/web-demo.sh package --base-href /demo/
```

**Or download the CI build:** every pull request's `Flutter validation` run
has a `web-demo` artifact (Actions → the run → Artifacts) with the same files,
built for the site root. Artifacts are kept for 14 days.

### 2. Upload

Upload the **contents** of the zip (not the zip itself, and not an enclosing
folder) to the web root, e.g. `public_html/` or `/var/www/mylittlecrm-demo/`.
`index.html` must sit directly in the web root, or in your sub-folder if you
used `--base-href`.

Two of the files start with a dot or underscore, and some upload tools hide
or skip them. Make sure they arrive:

| File | Used by |
| --- | --- |
| `.htaccess` | Apache / cPanel / most shared hosting: sets everything in step 3 |
| `_headers` | Cloudflare Pages / Netlify: sets everything in step 3 |

Both are harmless on other servers, and the configs below stop them from
being downloaded.

From a terminal, for example:

```sh
unzip dist/mylittlecrm-demo-1.1.2.zip -d mylittlecrm-demo
rsync -av --delete mylittlecrm-demo/ user@server:/var/www/mylittlecrm-demo/
```

With `--delete`, files from an older upload are removed. With SFTP or FTP,
replace every file. Old leftover files are harmless.

### 3. Server headers

The site needs these on every response:

| Header | Value | Why |
| --- | --- | --- |
| `Content-Type` for `*.wasm` | `application/wasm` | Browsers refuse to stream-compile Wasm otherwise |
| `Content-Type` for `*.mjs`, `*.js` | `text/javascript` | Module scripts need a JavaScript type |
| `Cross-Origin-Opener-Policy` | `same-origin` | With COEP: cross-origin isolation, so Flutter can use its faster multi-threaded renderer |
| `Cross-Origin-Embedder-Policy` | `require-corp` | As above |
| `Cache-Control` on `index.html`, `flutter_bootstrap.js`, `flutter_service_worker.js`, `version.json` | `no-cache` | A new upload shows up straight away |

The app still runs without COOP/COEP, using the slower single-threaded
renderer. Serve it over HTTPS, since browsers restrict some APIs on plain
HTTP. Gzip or Brotli for `.wasm` and `.js` more than halves the download:
`main.dart.wasm` goes from 3.3 MB to 1.2 MB.

**Apache, cPanel, most shared hosting:** nothing to do. The uploaded
`.htaccess` sets all of it. It needs `AllowOverride All`, or at least
`FileInfo Indexes AuthConfig`, which shared hosts allow. It uses
`mod_headers`, `mod_mime` and `mod_deflate` when they are present.

**Cloudflare Pages, Netlify:** nothing to do. The uploaded `_headers` file
sets all of it.

**nginx:** add to the site's `server { }` block:

```nginx
root /var/www/mylittlecrm-demo;
index index.html;

types {
  application/wasm wasm;
  text/javascript js mjs;
  application/json json;
  text/html html;
  image/png png;
  font/otf otf;
  font/ttf ttf;
}

add_header Cross-Origin-Opener-Policy "same-origin" always;
add_header Cross-Origin-Embedder-Policy "require-corp" always;
add_header X-Content-Type-Options "nosniff" always;
add_header Referrer-Policy "no-referrer" always;

gzip on;
gzip_types application/wasm text/javascript application/json;

# Entry files are always revalidated. `expires` is used, not add_header,
# because an add_header inside a location drops the headers above.
location ~ ^/(index\.html|flutter_bootstrap\.js|flutter_service_worker\.js|version\.json)?$ {
  expires -1;
}
location ~ /(_headers|\.htaccess)$ {
  return 404;
}
```

For a sub-folder, use `location /demo/ { … }` with `alias` instead of
`root`, and prefix the two regex locations with `/demo`.

**Caddy:**

```caddy
mylittlecrm-demo.example.com {
  root * /var/www/mylittlecrm-demo
  file_server
  encode gzip
  header {
    Cross-Origin-Opener-Policy same-origin
    Cross-Origin-Embedder-Policy require-corp
    X-Content-Type-Options nosniff
    Referrer-Policy no-referrer
  }
  @entry path / /index.html /flutter_bootstrap.js /flutter_service_worker.js /version.json
  header @entry Cache-Control no-cache
  @config path /_headers /.htaccess
  respond @config 404
}
```

Caddy already knows the `.wasm` and `.mjs` types and gets HTTPS certificates
automatically.

**IIS:** add `.wasm` as `application/wasm` and `.mjs` as `text/javascript`
under MIME Types. Then add the COOP and COEP headers under HTTP Response
Headers.

**Object storage + CDN (S3, Azure Blob, GCS):** upload with the right
`Content-Type` per file. Most upload tools guess from the extension; check
that `.wasm` is `application/wasm`. Add COOP/COEP with the CDN's response
headers policy, e.g. a CloudFront response headers policy.

### 4. Check it

Open the site in a private window and check that:

- the purple **Demo Mode** banner and the sample interactions appear;
- in DevTools → Console, `crossOriginIsolated` is `true`. If it is `false`,
  the COOP/COEP headers are missing; the demo still works, just slower;
- in DevTools → Network, `main.dart.wasm` and `sqlite3.wasm` load with type
  `application/wasm`;
- adding an interaction and refreshing brings back the original sample
  data.

From a terminal:

```sh
curl -sI https://mylittlecrm-demo.example.com/main.dart.wasm | grep -iE 'content-type|cross-origin'
# content-type: application/wasm
# cross-origin-opener-policy: same-origin
# cross-origin-embedder-policy: require-corp
```

**Blank page or "Failed to load"?** The usual causes:
- `.wasm` is served as `application/octet-stream` (fix the type);
- the files sit one folder too deep (`index.html` must be in the web root);
- a sub-folder build is missing `--base-href`.

Safari and older browsers without WebAssembly GC load `main.dart.js`
instead. That fallback is automatic.

### Updating

Build again and upload again, replacing the files. Visitors get the new
version on their next load, because the entry files are never cached. Each
visit starts from the sample data anyway, so there is nothing to migrate.

## Continuous integration

The `Flutter validation / Web demo (Wasm)` job builds the release Wasm demo
on every pull request. It checks the static site (required files, both
hosting configs, no stray files), then uploads it as the `web-demo`
artifact. The job uses no secrets, and `DEMO_MODE` is the only
`--dart-define`. Deployment is not automated: publish with the steps above.
