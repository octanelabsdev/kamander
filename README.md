# Kamander

> Kamal + Commander — a local command center for a Kamal-deployed app fleet.

Kamander is a **local-only** Rails app for operating the Kamal apps running on your
servers. Instead of `cd`-ing into each repo to run `kamal` by hand, you get one
dashboard: what's running where, how much it's eating, and buttons to restart, stop,
or start it.

It reads status fast over SSH (`docker ps`), and performs lifecycle actions through
each repo's own `bin/kamal` so kamal-proxy registration stays correct.

**There is no authentication, by design.** It binds to localhost, it's single-user, and
it can stop production apps. Don't expose it to a network.

---

## Running it

Build CSS once and start Puma:

```sh
bin/rails tailwindcss:build
bin/rails server              # then open http://localhost:3000
```

Solid Queue runs **inside Puma** (`config/puma.rb:42`), so there's no separate worker
process to remember — the 30-second fleet poll and the lifecycle job lanes come up with
the web process.

If you use corral (a private local process manager), `corral up kamander` does the same
and serves it at `https://kamander.test`.

### Not `bin/dev`

`Procfile.dev` exists because Rails generated it, but `bin/dev` is the wrong entry point
here: `tailwindcss:watch` exits immediately without a TTY and foreman takes Puma down
with it.

## Requirements

- Ruby 3.4.4 (see `.ruby-version`; managed with mise)
- SQLite 3
- `ssh` on your `PATH`, with `~/.ssh/config` and an agent already set up for the target
  servers — Kamander shells out to the system binary and inherits your existing config.
  It uses `BatchMode=yes`, so **any host that would prompt for a passphrase or password
  reads as unreachable.**
- Docker on the *servers*, not locally (except for whatever your own repos need).

Lifecycle verbs additionally need **the target repo's bundle installed locally**, because
they run that repo's `bin/kamal`, which loads its full bundle. If a repo's `Gemfile.lock`
is ahead of its installed gems, the operation fails with `Bundler::GemNotFound` — that's
the target repo's state, not a Kamander bug. Fix with `bundle install` in that repo.

## First run

```sh
bin/setup --skip-server
```

This installs gems, runs `db:prepare`, and clears logs/tmp. `db:prepare` creates **two**
SQLite databases: `storage/development.sqlite3` and `storage/development_queue.sqlite3`.
The queue lives on its own file on purpose — SQLite is a single-writer database and the
pollers will contend with the app otherwise.

Then, in the UI:

1. **Scan** (`/scan`) globs `<scan_root>/*/config/deploy.yml`, parses each config plus any
   `deploy.<destination>.yml` overlays, and lists what it found.
2. **Confirm** the apps you actually want on the dashboard. Everything else is hidden;
   nothing is managed until you say so.
3. The dashboard polls status every 30 seconds and pushes updates over Turbo Streams.

`scan_root` defaults to `~/Development` and the SSH user defaults to `deploy` — both are
editable at `/setting`.

## How it works

### Service layer

Everything under `app/services/kamander/kamal/` is UI-agnostic, so a CLI or menu-bar
front-end could reuse it later.

| Object | Job |
| --- | --- |
| `ConfigScanner` | Globs and parses `deploy.yml` + overlays. Never raises — unreadable repos come back with `error` set so one bad config can't kill a scan. |
| `ScanImporter` | Turns scan results into `ManagedApp` / `AppDestination` rows. |
| `StatusReader` | SSH + `docker ps`, batched per `(host, ssh_user)` pair so a host running six apps gets one connection. |
| `StatusWriter` | Persists reports to `DestinationStatus`. |
| `MetricsReader` | On-demand `docker stats` for one app's own containers. Point-in-time, never stored. |
| `Lifecycle` | Runs one `Operation` to completion, streaming output as it arrives. |
| `SshClient` | Shells to system `ssh` via Open3. 5s connect timeout, 10s command timeout, own process group so a hung connection can actually be killed. |
| `CommandRunner` | Streams a repo's `bin/kamal` line-by-line, in that repo's directory, under `Bundler.with_unbundled_env`. No timeout — kamal verbs are legitimately slow. |

`SshClient` and `CommandRunner` are injected everywhere, and the test suite substitutes
fakes (`test/support/`), so **tests never touch a real server**.

The `kamal` gem is deliberately never loaded in-process — repos pin different versions and
the top-level `::Kamal` constant clashes with this app's own `Kamander::Kamal`. Configs are
parsed directly (ERB in a clean binding → `YAML.safe_load(aliases: true)` → deep-merged
overlays); lifecycle shells out.

### Container matching

Containers are matched to destinations by **kamal's own Docker labels**
(`service` / `role` / `destination`), not by name prefix. Real fleets break prefix matching:
a destination overlay can override `service:`, and apps get deployed plain (no `-d`) even
when overlays exist, leaving an empty destination label. Name-prefix matching survives only
as a fallback for containers carrying no labels at all.

Containers that can't be attributed to any known destination are **surfaced, not dropped** —
they appear on every destination sharing that host, so "something's running here I don't
recognize" is visible rather than silent.

### Lifecycle verbs

| Verb | What actually runs | Why |
| --- | --- | --- |
| **Restart** | `ssh <host> docker restart <containers>` | Fast, same version, proxy route untouched, no local-repo dependency. |
| **Reboot** | `bin/kamal app boot --version <pinned>` | Version-pinned rolling replace, re-registers with the proxy. |
| **Start** | `bin/kamal app boot --version <pinned>` | Boots the last-deployed version. |
| **Stop** | `bin/kamal app stop` | Proper proxy deregistration. Causes downtime. |

The pinned version is read from the **running (or last exited) container's image tag** — never
from local HEAD. If no version is known, the operation is blocked with an explanation rather
than booting something arbitrary.

`Restart` groups containers by host and issues one `docker restart` per host.

### Data model

- **`ManagedApp`** — one repo. `discovered` → `managed` / `hidden`. Status rolls up across
  destinations by worst-severity (`unknown` < `running` < `partial` < `down` < `unreachable`).
- **`AppDestination`** — one `deploy*.yml`. `name` is `nil` for the base config. A base-only
  destination counts as `production?`, as does anything matching `/prod/i`.
- **`DestinationStatus`** — last observed state per destination, `unknown|running|partial|down|unreachable`,
  stale after 90 seconds. Broadcasts to the dashboard card and the app's stats page on write.
- **`Operation`** — one lifecycle action. `queued|running|succeeded|failed`, with streamed
  `output`. A partial unique index (`status IN (0, 1)`) enforces **one active operation per
  destination** at the database level.
- **`Setting`** — singleton row: `scan_root`, `default_ssh_user`.

### Background jobs

Two Solid Queue lanes (`config/queue.yml`), not one pool:

- **`default`** (3 threads) — `StatusPollJob`, the 30-second fleet poll, `limits_concurrency to: 1`.
- **`lifecycle`** (2 threads) — `LifecycleJob`. A `kamal boot` streaming for minutes must never
  starve the fleet poll of a thread.

`LifecycleJob` has **no `retry_on`**: re-running a lifecycle verb without knowing what state it
left the destination in is dangerous. A failed command is already a normal `failed` Operation;
an actual exception means `Lifecycle` itself broke. `discard_on` marks the operation failed so a
crashed job can't leave the destination lock stuck.

## Safety model

- Only non-destructive kamal verbs. **No** `deploy`, `rollback`, `remove`, or accessory destroy.
- Lifecycle buttons don't render at all until status is known — an `unknown` or `unreachable`
  destination shows "Refresh status first" instead. You can't act on a fleet you can't see.
- Verbs are offered by state: a `down` destination offers only **Start**; otherwise
  **Restart / Reboot / Stop**.
- Stopping a **production** destination requires typing the app's name exactly; the modal names
  the destination and its hosts. Every other stop, and any verb on a production destination, gets
  a standard confirm naming the same.
- One active operation per destination, enforced by a partial unique index — not just a UI guard.
  A second request while one is running is rejected, not queued.

## Tests

```sh
bin/rails test          # models, controllers, jobs, services, helpers, views
bin/rails test:system   # operator journeys, run separately
bin/ci                  # setup, rubocop, bundler-audit, importmap audit, brakeman, tests, seeds
```

Minitest + fixtures. Last run of `bin/rails test`: **155 runs, 511 assertions, 0 failures,
0 errors, 0 skips.** Note that `bin/ci` has the system-test step commented out — run
`bin/rails test:system` yourself before shipping anything operator-facing.

Two testing constraints worth knowing before you write a system test here:

- Anything asserting a Turbo broadcast needs `use_transactional_tests = false`. `after_commit`
  never fires for new records inside the test transaction.
- Proving a *live* Turbo patch (as opposed to a redirect repaint) takes two Capybara sessions:
  a watcher that never navigates, plus the actor.

## Troubleshooting

**Dashboard shows `unreachable`.** Kamander uses `BatchMode=yes`, so anything needing an
interactive prompt fails. Verify by hand: `ssh -o BatchMode=yes deploy@<host> docker ps`.

**An operation fails with `Bundler::GemNotFound`.** The target repo's bundle isn't installed
locally. `bundle install` in that repo. It reproduces in a plain shell — not a Kamander bug.

**Operation console appears stuck on "queued".** Fast operations (a `docker restart` takes 1–2s)
can finish before the page's Turbo Stream subscription connects, so every broadcast fires
pre-subscribe. The console self-heals by polling while the operation is non-terminal and stops
once a terminal state renders. If it genuinely hangs, reload — state is read from the database.

**`/cable` returns 404 under curl.** Expected. ActionCable rejects any handshake without a valid
`Origin` header; browsers always send one. Not a proxy problem.

## Layout

```
app/services/kamander/kamal/   scanning, status, metrics, lifecycle, ssh/command seams
app/models/                    ManagedApp, AppDestination, DestinationStatus, Operation, Setting
app/jobs/                      StatusPollJob (default lane), LifecycleJob (lifecycle lane)
app/javascript/controllers/    confirm_stop, op_refresher
test/support/                  FakeSshClient, FakeCommandRunner
```
