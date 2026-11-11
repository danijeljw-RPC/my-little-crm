# My Little CRM — product and technical design

## Intent

My Little CRM is a fast, personal record of communications with companies,
service providers, and individuals. It lets a person document an interaction
in under a minute, attach it to a continuing history, track promises and
follow-ups, and find the record again in seconds. It is deliberately not a
sales pipeline, team CRM, or enterprise customer-management system.

The application is private by default. It should remain useful offline, avoid
requiring personal details, and leave backups under the user's control.

## Goals

- Support Windows, macOS, Linux, Android, and iOS from a single codebase.
- Keep a chronological, searchable history per company, provider, or person.
- Record date/time, communication method, party, contact, note, reference
  number, agreement/promise, and follow-up.
- Make follow-ups visible in the app, available as local notifications, and
  optionally exportable to the device calendar.
- Persist the primary data locally in SQLite and work without a connection.
- Let the user explicitly back up and restore an encrypted database file using
  the operating system's file picker and its configured providers (iCloud Drive,
  Google Drive, OneDrive, removable storage, and similar).
- Provide an app-entry PIN plus device biometric/secure-auth alternative without
  requiring an email address, phone number, or hosted account.
- Allow a forgotten PIN to be reset locally through a static WASM recovery site;
  the recovery service must not receive, store, or expose CRM data or recovery
  credentials.

## Non-goals for the first release

- Sales, leads, pipelines, teams, shared records, or organisation accounts.
- Managed multi-device sync, hosted user databases, or any account held by us.
- User-configured PostgreSQL, Supabase, or other bring-your-own cloud database.
- Direct integration with mail, SMS, or live-chat providers.
- Full document/attachment management; links or small references may follow
  once the core data model is proven.

## Product model

### Records

`Party` represents a company, service provider, or individual. A party owns a
time-ordered list of `Interaction` records. Each interaction contains:

- event timestamp (defaulted automatically, editable), method, and optional
  contact name;
- free-text discussion summary;
- one or more reference/case/account numbers;
- an optional structured commitment and follow-up due date;
- a completion state and audit timestamps.

Search indexes party name, contact name, reference numbers, and interaction
text. The initial experience centres on a fast “new interaction” sheet, a party
timeline, global search, and a due/upcoming follow-up list.

### Follow-ups

A due follow-up is part of the interaction record, never merely a notification.
The app can schedule a local notification. At save time, the user may also add
a device-calendar event with a configurable alert and a discreet title to avoid
exposing sensitive details on a locked device. Completing a CRM follow-up does
not silently delete the calendar event; the app offers the user the choice.

## Platform and technical approach

### Client

Build a single **Flutter** application for Windows, macOS, Linux, Android, and
iOS. Flutter is the selected technical direction because it permits one UI and
domain codebase while supporting native SQLite, secure storage, biometric
authentication, local notifications, calendar access, file pickers, and QR
scanning across the requested platforms.

The application uses a layered design:

1. Presentation: responsive Flutter screens for phone, tablet, and desktop.
2. Domain: parties, interactions, follow-ups, search, backup, and recovery
   policy with no platform-specific dependencies.
3. Local data: SQLite database, migrations, full-text search, and encrypted
   backup export/import.
4. Platform adapters: secure storage, biometrics, notifications, calendar,
   file picker/share sheet, camera/QR scanner, and desktop clipboard.

The first release has no product backend or API. This deliberately avoids a
managed identity system, hosted copies of records, and infrastructure coupling.

### Data protection and app entry

The PIN is an app-entry lock, not the sole encryption key for the user's
database. The app supports a numeric PIN and the operating system's local
secure-auth mechanism where available: Face ID/Touch ID on Apple devices,
Android biometric prompt, Windows Hello, and comparable desktop facilities.

Local data and backups must use platform-backed key material and modern
authenticated encryption. The exact cryptographic library and key-management
mechanism remain an implementation decision subject to platform review. The
critical product behaviour is that a forgotten PIN may be reset without making
the data visible in a browser or requiring us to hold an account.

### Backup and restore

Backup is an explicit, versioned, encrypted snapshot—not synchronization. The
user selects an output location through the native file picker; the operating
system decides whether that is iCloud Drive, Google Drive, another configured
provider, or local/removable storage. Restore requires the user to select a
backup and confirm replacement/merge policy. The first release should use
replace-with-confirmation and create a safety copy before replacement; merging
independent SQLite histories is deferred.

Users should be guided to verify a backup after creation and retain the recovery
kit separately from the backup file.

## Offline recovery design

### Setup

During first-run setup the app creates locally:

- a non-secret App ID, used only to bind recovery material to an installation or
  restored data set;
- a high-entropy recovery kit, displayed once and explicitly saved by the user;
- a recovery signing key pair derived from that secret.

Only the recovery public key is retained in local application/backup metadata.
The recovery kit itself is never transmitted to us or retained by the app after
setup. Losing every copy of it means the user cannot reset the app-entry lock;
this is intentional and must be communicated clearly.

### Reset

The recovery website is a static WASM application. It has no user accounts,
database, API, analytics, reset queue, device registry, or access to CRM data.
It derives the recovery signing capability in-browser from the recovery kit and
creates a signed PIN-reset token bound to the App ID.

The site presents that token as a QR code for mobile scanning and as text for
desktop copy/paste. The installed app verifies the token using the locally held
public key, then permits the user to set a new PIN. It must not unlock or send
the CRM database to the browser. The final protocol needs cryptographic review
before implementation, including token replay and binding rules.

Recovery after reinstallation requires restoring a user-controlled backup first,
then using the recovery token if the app-entry PIN is forgotten. There is no
download-from-us path.

## Future stages

### Stage 2: attachments and backup usability

Add attachment references/import, backup verification, backup retention prompts,
and a more polished restore/safety-copy experience after the core interaction
workflow has been validated.

### Stage 3: bring-your-own cloud

Offer an optional self-hosted or user-configured synchronization adapter for
PostgreSQL/Supabase or another user-owned backend. It must remain opt-in and
separate from the local-first product. It should use narrowly scoped credentials
and a tested sync protocol rather than allowing an unreviewed client to expose
a privileged database password. This stage requires an explicit API contract,
security model, conflict resolution strategy, and integration tests before any
implementation.

## Key risks and decisions

- A PIN lock is not a substitute for strong device security or sound encryption;
  the product should say so plainly.
- Backup and restore can cause data loss if mistaken for sync. The UI must state
  that restore replaces local data and show a safety-copy option.
- Platform calendar access and notification permission are optional, granted only
  when the user chooses those features.
- A static WASM recovery page reduces collection of personal data, but it does
  not eliminate the need for careful supply-chain, CSP, offline-cache, and
  cryptographic review.
- A lost recovery kit has no recovery path by design. Setup must ensure the user
  acknowledges and saves it.

## Proposed release sequence

1. Core local application: parties, interactions, search, follow-ups, desktop
   and mobile responsive UI.
2. App-entry PIN/biometrics, local notifications, optional calendar export.
3. Encrypted backup/restore and recovery-kit flow, including the static WASM
   token generator.
4. Platform acceptance testing on all five targets and privacy/security review.
5. Separate discovery and design for user-owned cloud sync.

## Approval required

No product code should be scaffolded or implemented until this design is
approved. The main unresolved implementation-level decision is the audited
cryptographic protocol for recovery tokens; the stated privacy and behavioural
constraints are fixed inputs for that review.
