# Amazfit Helio Strap data access

## Recommendation

Use Zepp's first-party cloud endpoints as the first-release path, but treat them as an undocumented integration rather than a supported API. The unofficial `zepp-export` project reports that it works with the Helio Strap and documents concrete requests and response encodings. Its own docs say the API was reverse-engineered from Zepp app traffic. Zepp publishes no consumer account API contract, OAuth flow, stability promise, or Mac SDK that matches this use case.

Do not collect a Zepp password in native app controls. The community flow uses an `apptoken` cookie from the user's session at `user.huami.com`. No documented OAuth handoff was found that lets a native Mac app obtain that cookie after opening an external browser. Helio instead loads the official sign-in page in a nonpersistent WKWebView and observes its cookie store. It accepts only a complete, valid `apptoken` and `userid` pair applicable to that page, without reading password fields or injecting JavaScript. This is still an unofficial integration, not a supported OAuth flow, and some identity providers may block embedded browsers. Manual cookie entry remains a fallback. Keep the session in macOS Keychain after a successful cloud fetch, send the token only to the selected regional Zepp host, redact it from logs, and prompt for sign-in after authorization failures. Never send credentials or tokens to this project or another third party.

Start with daily heart rate, sleep, steps, stress, and training-load records from the endpoints below. Do not promise direct HRV, BioCharge, or a general readiness score from this API. Confirm each mapping against the user's own account and firmware before presenting it as supported.

## What is documented and what is not

| Route | Evidence | What it gives this app |
| --- | --- | --- |
| Zepp cloud account endpoints | Community reverse engineering only. See [zepp-export API reference](https://github.com/EvanCooke/zepp-export/blob/main/docs/api-reference.md). | The most direct path to historical account data, but no compatibility guarantee. |
| Zepp account data export | [Zepp Privacy Protection Support](https://www.zepp.com/privacy-support) lists "Export data" and the in-app user-rights path. | A user-controlled fallback or backup. The page does not document the delivered file format, schema, or a live API, so do not assume an archive layout. |
| Apple Health | [Xiaomi's support article](https://www.mi.com/global/support/article/KA-12890/) documents Zepp Life syncing selected data to Apple Health. | It documents Zepp Life, not the current Zepp app/Helio Strap metric coverage or a Mac-readable account API. Do not make it the MVP dependency. |
| Zepp developer platform | [Zepp OS developer docs](https://docs.zepp.com/) cover apps for Zepp OS; [Zepp Open Platform](https://console.zepp.com/) advertises partner capabilities. | No public consumer cloud-read API or native macOS authorization path was found in these materials. Partner access may have separate terms and onboarding. |
| Direct Bluetooth | Official [Helio Strap support](https://support.amazfit.com/us/amazfit_helio_strap/docs/GyUIdtHLvoMqNUxOkuNcQB4hn4d) documents "Heart Rate Push" to third-party devices. | Real-time heart rate after the user enables the setting. It does not document historical sync, sleep, stress, HRV, or readiness over BLE. |

Zepp's official export instructions are in the app under **Profile → Settings → Exercising user rights**. Zepp Life uses **Profile → Settings → Account and Security**. Export is useful for a manual fallback, but its format must be inspected from an actual user export before implementing an importer.

## Reverse-engineered cloud requests

The following requests and shapes are documented by `zepp-export`; they are not Zepp-supported API specifications. Its README says the flow was confirmed with a Helio Strap. The repo's history is short (three commits shown, with no releases on the repository page), so use it as a reference, not a vetted dependency. Its API reference says the endpoints were mapped from Zepp app traffic and may vary by account region or app version.

### Authentication and host

The project documents using `https://user.huami.com/privacy/index.html` and reading the `apptoken` cookie in the browser's developer tools. The plain URL actually renders a Zepp Life privacy operations menu in a fresh session. We reproduced this in an ephemeral WKWebView. The direct route `https://user.huami.com/privacy/index.html?platform_app=com.huami.watch.hmwatchmanager#/login` renders the Zepp heading and a sign-in form with a password input. The current official JavaScript defines both this product selector and the `/login` route. No real-account login was performed in that check. Do not select destructive privacy operations to sign in.

The project says to supply the token as the `apptoken` request header, along with:

```http
appPlatform: web
appname: com.xiaomi.hm.health
```

The project reports that tokens expire after several weeks and documents no refresh endpoint. Treat that lifetime as an observation, not a guarantee. The account's numeric user ID is also required by some calls. The project says it can be found in the Zepp app or a response; verify the actual account response rather than guessing an ID or undocumented lookup route.

The current official privacy site's JavaScript at `https://user.huami.com/privacy/static/js/main.b5278b36.chunk.js` reads both `apptoken` and `userid` cookies. This identifies the cookies used for automatic collection and manual entry, but does not prove that every regional health endpoint accepts that session. The native cookie parser checks the official domain, applicable path, expiry, credential format, and conflicting duplicate values. It does not infer or probe the account region. The web data store is cleared after completion or cancellation, and no browser password is read by native code.

The repo lists these regional hosts. Do not guess a host or silently forward tokens across regions:

- US: `https://api-mifit-us2.zepp.com`
- Global: `https://api-mifit.huami.com`
- Europe: `https://api-mifit-de2.zepp.com`

### Daily heart rate, sleep, and steps

```http
GET /v1/data/band_data.json?query_type=detail&device_type=android_phone&userid={id}&from_date=YYYY-MM-DD&to_date=YYYY-MM-DD
```

The documented response has a top-level `code` and `data` array. Each daily record includes fields such as `date_time`, `summary`, `data_hr`, and `data`. `summary` is Base64-encoded JSON; the reference maps `summary.stp.ttl` to daily steps and `summary.slp` fields including `st`, `ed`, `dp`, `lt`, `rhr`, `ss`, and `stage`. Sleep timestamps `st`/`ed` are Unix seconds. Sleep-stage entries use minute-of-day `start`/`stop` offsets and mode values 4 light, 5 deep, 7 awake, and 8 REM.

`data_hr` is documented as Base64-encoded bytes with 1,440 minute slots per day. Values 1–253 are heart-rate readings; 0 and 254–255 mean no reading or sensor error. The separate `data` field is also Base64 binary, but the project says its format is not well understood. Do not decode it for product features without independent validation.

The project notes that sleep is assigned to the date it starts. To include a session crossing midnight, query the previous date too. Verify timezone and date boundaries with real account data.

### Stress

```http
GET /users/{id}/events?eventType=all_day_stress&from={unix_ms}&to={unix_ms}&limit=200
```

The documented response uses an `items` array. An item can contain `avgStress`, `minStress`, `maxStress`, zone proportions, and `data`. `data` is itself a JSON-encoded string containing readings shaped like `{"time": <unix milliseconds>, "value": <stress>}`. The reference describes samples at five-minute intervals. It says automatic stress monitoring must be enabled for readings to appear.

Stress is calculated from HRV according to the official Helio Strap manual, but stress scores are not HRV measurements. Do not relabel them as HRV or infer an HRV value from them.

### Training load and recovery-related values

```http
GET /v2/users/me/events?eventType=exertion&subType=algo_result&from={unix_ms}&to={unix_ms}&limit=200
```

The reverse-engineered reference documents `items[]` records with `timestamp` and a `value` object containing fields such as `atl`, `ctl`, `tsb`, `recoveryFactor`, `exerciseScore`, and `targetScore`. A separate documented query uses `eventType=phn&subType=daily_analysis` and maps `value.result.trimp`, `atl`, `ctl`, and `tsb`. These are training-load/recovery-related fields, not proof of the Helio app's daily readiness or BioCharge score. Validate availability and meaning with a real Helio account before displaying them.

## Helio metrics: device capability versus cloud coverage

The [official Helio Strap manual](https://support.amazfit.com/us/amazfit_helio_strap/docs/OSUldKzExovDlRxnMyCcH10dnL0) says the Zepp app can show continuous heart rate, resting heart rate, HRV, stress, sleep, and sleep stages. It says stress monitoring runs every five minutes when enabled. REM sleep requires auxiliary sleep monitoring. The manual also describes a morning Body Battery/Body Power score using sleep, HRV, resting heart rate, and recent activity. Zepp's [Helio Strap launch release](https://www.zepp.com/press-release/amazfit-introduces-balance-2-smartwatch-and-helio-strap-for-smarter-training-better-recovery-and-peak-performance) says BioCharge combines sleep, naps, exertion, and stress.

Those device and app features do not establish that every metric is available from cloud endpoints. In particular, `zepp-export` says it found no dedicated HRV endpoint and no BioCharge/readiness endpoint. It exposes stress as a proxy and training-load fields as separate data. The cloud coverage, endpoint stability, and date/history availability for those in-app scores remain unverified.

The manual's direct-Bluetooth feature is deliberately narrower: the user turns on **Zepp → Device → Helio Strap → Health Monitoring → Heart Rate Push**, then a compatible third-party device can receive live HR. There is no official public BLE protocol or SDK in the cited docs for reading stored daily data. A Mac BLE client should therefore be considered a separate experimental live-HR feature, not a substitute for account sync.

## Security and failure handling

- Never ask for or store the Zepp account password in native code. Password entry happens on the official website inside WebKit, not in a Helio form. The documented unofficial method uses a session cookie, not an app password grant.
- Do not claim that external browser sign-in authorizes the Mac app to read browser cookies. Helio observes only its own private WebKit cookie store after the user approves session storage. No supported OAuth redirect or token-exchange flow is documented. Only HTTPS web navigation is allowed, apart from blank popup pages; identity-provider popups share the same temporary store.
- Whether collected from WebKit or entered manually, keep the token in Keychain and call only the selected first-party Zepp regional host over HTTPS. Do not include it in logs, crash reports, analytics, URLs, or support requests.
- Handle 401/authorization errors by pausing sync and asking the user to reauthenticate. Do not retry with guessed headers or another region.
- Parse the observed JSON and Base64 formats defensively. Reject malformed records and preserve unknown fields where practical. The reverse-engineered project reports both Base64 JSON and binary payloads, plus JSON encoded inside a JSON string.
- Treat endpoint names, field meanings, sampling density, and retention as unversioned. There is no documented rate limit or availability commitment.

## Sources

- [Amazfit Helio Strap support manual](https://support.amazfit.com/us/amazfit_helio_strap/docs/OSUldKzExovDlRxnMyCcH10dnL0)
- [Official Helio Strap Heart Rate Push instructions](https://support.amazfit.com/us/amazfit_helio_strap/docs/GyUIdtHLvoMqNUxOkuNcQB4hn4d)
- [Zepp Privacy Protection Support](https://www.zepp.com/privacy-support)
- [Zepp OS developer documentation](https://docs.zepp.com/)
- [Zepp Open Platform](https://console.zepp.com/)
- [Official Zepp Life to Apple Health instructions](https://www.mi.com/global/support/article/KA-12890/)
- [Zepp Helio Strap press release](https://www.zepp.com/press-release/amazfit-introduces-balance-2-smartwatch-and-helio-strap-for-smarter-training-better-recovery-and-peak-performance)
- [zepp-export README and project claims](https://github.com/EvanCooke/zepp-export)
- [zepp-export API reference](https://github.com/EvanCooke/zepp-export/blob/main/docs/api-reference.md)
- [zepp-export reverse-engineering notes](https://github.com/EvanCooke/zepp-export/blob/main/docs/mapping-guide.md)
- [zepp-export commit history](https://github.com/EvanCooke/zepp-export/commits/main)
- [Related small fork](https://github.com/marekdolnicek/zepp-export)
