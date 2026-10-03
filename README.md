# Helio for Mac

A native SwiftUI app for viewing Amazfit Helio Strap data from your Zepp account. Requires macOS 14 or later and Xcode 16 or later to build. No Python service, web dashboard, or third-party backend.

This is an independent, experimental app. Zepp does not publish a supported consumer Helio cloud API. The requests and field mappings come from community reverse engineering, not an official SDK. **The app builds and its offline tests pass, but live access has not been verified with your account.**

## Run

```sh
./scripts/run.sh
```

This builds, locally signs, and opens `.build/Helio.app`. Try **Explore sample data** before connecting; it shows two weeks of synthetic data. Sample data is clearly labeled and never saved as your real dataset.

To build an optimized local app:

```sh
./scripts/build-app.sh release
open .build/Helio.app
```

You can copy that app to `/Applications`. The build targets your current Mac's architecture. It is ad-hoc signed for local development, not notarized for distribution.

### Xcode

Install [XcodeGen](https://github.com/yonaskolb/XcodeGen), then:

```sh
xcodegen generate
open Helio.xcodeproj
```

Select the Helio scheme and My Mac, then Run. `project.yml` is the project definition. The generated project is ignored.

## Connect your account

1. Sync the Helio Strap in the Zepp app on your iPhone. This Mac app reads the cloud, not the strap directly.
2. Click **Connect Zepp account**, select your account's region, and approve Keychain storage and the local cache.
3. Click **Sign in to Zepp**. Helio opens the [official Zepp sign-in page](https://user.huami.com/privacy/index.html?platform_app=com.huami.watch.hmwatchmanager#/login) in a private web window inside the app. Use the same sign-in method and account as on your iPhone. Do not select Clear data, Delete account, or Revoke authorization.
4. After signing in, Helio collects the `apptoken` and `userid` cookies automatically and starts downloading. The private web session is cleared when sign-in completes or is cancelled. Credentials are saved in Keychain only after a successful cloud fetch.

If your sign-in provider blocks embedded web windows, cancel and expand **Enter cookies manually**. Open Zepp in Chrome, sign in, then open View → Developer → Developer Tools. Under Application → Cookies → `https://user.huami.com`, copy `userid` and `apptoken` into Helio and click **Connect & download**. Helio cannot read cookies from Chrome or Safari.

A token is a secret with account access. Never paste it into chat, a GitHub issue, email, or a screenshot. Your password goes to Zepp's website. Helio's native code does not read or store it.

Account region is set when the account is created. It is not necessarily your current location. The app never retries another region automatically. If Zepp rejects a session, check the region and sign in again. There is no verified token-refresh flow.

Use the toolbar to download the last 7, 14, or 30 days. Downloads are manual and replace the previous cached range; this version is not a full-history archive or live monitor. If an endpoint reaches its result limit, the app warns that records may be missing.

## What you can see

| Data | Current display |
| --- | --- |
| Today | Steps, sleep score, resting heart rate, and stress at a glance; the day's heart rate with sleep and workouts shaded; last night's stages; steps by hour; workouts; training load; trends across the downloaded range |
| Heart rate | Minute-by-minute chart with hover, resting/average/lowest/highest, the device's peak reading, time in zones for the whole day, heart rate while asleep, daily range and resting trends |
| Sleep | Score, time asleep, in-bed window, wake-ups, efficiency, a hoverable stage timeline, sleeping heart rate, stage breakdown, nightly history |
| Stress | 5-minute readings colored by level, average/low/high, time at each level, daily averages |
| Activity | Steps against your goal, distance, calories, active time, steps per hour (decoded from the per-minute record), detected walks and runs, daily steps |
| Workouts | History plus a detail view: duration, distance, pace, cadence, stride, calories, average/max heart rate, heart rate over your zones, time in zones, training effect, exercise load, perceived effort, and strength sets |
| Training load | 7-day load against Zepp's optimal range |
| Unknown fields | Raw endpoint responses and decoded daily summaries in Raw data; JSON export |

Not every endpoint returns data for every account. Missing measurements say "Not available", not zero. Heart-rate charts preserve minute indexes and do not join lines across missing samples. Sleep duration excludes awake stages; the start/end window is shown separately because it can include awake time. Cloud sleep records can be assigned to the date you fell asleep, so inspect the previous date when looking for last night's sleep.

Band charts are filtered to the selected device. Stress, workout, and training endpoints are account-level and may include your other Zepp devices. Sleep stages are placed using the record's reported start time; in real Helio records a night is filed under the morning it ended. Workout field meanings (sport type, zone limits, training effect scale) were checked against a real Helio record but are not documented by Zepp.

**HRV, BioCharge/readiness, SpO₂, and respiratory rate do not have verified endpoint mappings in this version.** Stress is not shown as HRV. The app does not invent recovery scores. This is not medical software.

## Privacy

- Health-data requests use HTTPS and only the selected first-party Zepp regional host. Redirects are refused so the session token cannot be forwarded to another host. The sign-in web window also permits HTTPS redirects to identity providers.
- The sign-in window uses a separate, nonpersistent WebKit data store. Only a complete, valid `apptoken` and `userid` pair belonging to the official sign-in page is accepted. Browser cookies and website data are cleared on completion or cancellation.
- Health-data downloads use an ephemeral URLSession without persistent cookies, URL cache, or credential storage. The token is sent as an `apptoken` header, never in a URL.
- Session credentials are stored in macOS Keychain after a successful cloud fetch. HTTP error messages omit response bodies. Known credential fields and literal token values are redacted from stored endpoint responses.
- The local health-data cache is `~/Library/Application Support/Helio/snapshot.json`. Its directory has mode `700` and the file has mode `600`. The file is excluded from normal backup, but is **not separately encrypted**. Use FileVault to protect your disk.
- Disconnect & delete local data removes the Keychain entry and the cache. It cannot remove files you exported yourself or data held by Zepp.
- JSON exports contain health data and account/device identifiers. Treat them as private. There is no telemetry.

The development app is not sandboxed. App Store distribution would need a separate signing, sandboxing, and privacy review.

## Verify

```sh
swift test
swift build -Xswiftc -warnings-as-errors
```

The tests use a mocked URLProtocol and private WebKit cookie stores with synthetic cookies, not a live account. Sign-in tests cover cookie domains, paths, expiration, conflicting values, automatic collection, isolated sessions, and cancellation. Cloud tests cover response decoding, timestamps, missing data, duplicate records, malformed payloads, request construction, authentication failures, partial endpoint failure, result limits, cancellation, token redaction, and redirect refusal.

See [docs/data-access.md](docs/data-access.md) for the research and source links. The next useful step is checking a real account's endpoint responses locally, then mapping the remaining fields and investigating a supported ongoing-sync route.
