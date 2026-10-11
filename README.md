# Salle 215

A native SwiftUI iOS app based on `concepts/salle215.html`, targeting **iOS 26.0 and later**. Connect to a Langfuse Cloud or self-hosted v4 project, or explore the bundled Support agent sample.

## Run

Open `Salle215.xcodeproj` in Xcode, select the **Salle215** scheme and an iOS 26+ simulator, and press **Run**. On first launch, choose **Connect to Langfuse** and enter your instance URL and project API keys, or choose **Explore a sample project** to open the sample directly.

The project was built with Xcode 27 and Swift 6. It uses Apple’s SwiftUI, Observation, and Charts frameworks and has no external package dependencies. Running on a physical device requires selecting your development team in Signing & Capabilities.

`project.yml` is the XcodeGen source. The generated Xcode project is included. Regenerate it after changing targets, build settings, or adding source files:

```sh
xcodegen generate
```

## Implemented

- **Overview:** time ranges, attention indicators, four vitals with sparklines, metric sheets with chart scrubbing and breakdowns, and navigation to filtered traces or the review queue. While scrubbing, the headline shows the selected value and its time, then returns to the period value on release.
- **Traces:** error filters and a slow filter for all traces lasting at least five seconds, including errors, cost sorting, trace input/output and errors, span timelines, generation details, related sessions and prompts, error copying, and native sharing. Overview actions return to the filtered list even when a trace was previously open.
- **Review:** source documents, Good and Needs work ratings, multiple feedback reasons, optional notes, skipping, undo, queue completion, and confirmed restart. Sample ratings persist locally; live ratings are stored in Langfuse. Feedback stays attached to the original answer across windows, and an existing rating cannot be overwritten by a stale submission.
- **Prompts:** production and staging versions, template messages, and sentence comparisons showing added, removed, and unchanged content.
- **Search:** trace IDs, sessions, users, trace names, input/output, and error titles; recent query shortcuts and empty results.
- **Presentation:** system tab bar and navigation, sheets, menus, confirmation dialogs, light/dark palettes, Dynamic Type, and an Salle 215 app icon, styled after the concept. Review controls stack vertically at accessibility text sizes. Each iPad window keeps its own tab, navigation, time range, filters, and search.

## Test

Press **Command-U** in Xcode, or run against the installed simulator:

```sh
xcodebuild test \
  -project Salle215.xcodeproj \
  -scheme Salle215 \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO
```

Verification on October 11, 2026: the full iPhone 17 Pro / iOS 26.5 suite passed 57 tests, including the read-only real-project smoke test. After renaming the project to Salle 215, the suite passed 56 tests with no failures; the opt-in real-project smoke test was skipped in that rerun. All 43 non-live model tests and the four live UI flows also passed on iPad Pro 11-inch (M5) / iPadOS 26.5. The four live UI flows passed again on iPhone 18 Pro / iOS 27.0 after the rename. Coverage includes model tests for decoding, trace reconstruction, cursor guards, rate limits, concurrent requests, prompt versions, and score submission/undo. Simulator UI coverage exercises all live tabs, loading/empty/rate-limit states, trace/session navigation, prompt comparisons, review undo, and server search on iPhone and iPad. A separate native-client smoke test exercises the real project with read-only requests.

UI tests use `--uitesting` for isolated in-memory state. Live fixtures require a DEBUG build and `SALLE215_LIVE_FIXTURE=data`, `empty`, `limit`, or `cached-limit`; these transports are excluded from Release. The cached-limit fixture completes the first report and rate limits its next refresh. Normal launches restore the saved connection. `--demo` opens the sample workspace.

The real smoke test is opt-in. With a local `.env` containing `LANGFUSE_BASE_URL` (or `LANGFUSE_HOST`), `LANGFUSE_PUBLIC_KEY`, and `LANGFUSE_SECRET_KEY`, pass its absolute path as `TEST_RUNNER_SALLE215_REAL_ENV` to `xcodebuild test`, or `SALLE215_REAL_ENV` through XcodeBuildMCP's `testRunnerEnv`. The test never posts or deletes scores. Score writes and undo are covered with simulated HTTP responses and simulator UI tests.

`scripts/check_live_backend.py` provides an additional read-only contract check through the Langfuse CLI. It reads `.env` locally without placing credentials in command arguments. Neither the script nor the native smoke test bundles keys into the application.

Screenshots captured from the running app and UI tests are saved in `docs/screenshots/`.

The October 11 UI implementation report is in [review/2026-10-11/index.html](review/2026-10-11/index.html), with fresh simulator captures and a comparison of the original screens, generated concepts, and implementation. It covers persistent project/environment context, concise trace errors, a shared-axis waterfall, labeled metric charts, neutral pinned review choices, expanded evidence, and actionable empty states. Failed Overview refreshes retain the previous completed report and its original timestamp.

After the UI implementation, 60 distinct tests passed on iPhone 17 Pro / iOS 26.5 across regression and capture runs; three opt-in live checks were skipped. The report contains 44 fresh simulator screenshots, including connected review/feedback and a rate-limited refresh with retained metrics. See [validation details](review/2026-10-11/implemented/validation.json).

## Source

The public marketing, support and privacy pages are maintained in `site/public/`. `site/wrangler.jsonc` deploys them to `salle.room215.me` as a Cloudflare Worker with static assets. The landing page is at `/`, support at `/support/` and the privacy policy at `/privacy/`.

- `Salle215App.swift`: onboarding, tab structure, and project menu.
- `Models.swift`: shared connection state, per-window state, observation-backed trace loading, filtering/search, and sample review persistence.
- `LangfuseClient.swift`: Observations API v2 transport, response decoding, trace reconstruction, and Keychain credential storage.
- `ConnectionViews.swift`: connection form, live tabs, loading/error states, and trace hydration.
- `BackendMetrics.swift`, `LiveOverviewView.swift`: aggregate queries, caching, charts, and breakdowns.
- `BackendResources.swift`, `LiveResourceViews.swift`: prompts, scores, reviews, session fetches, and server search.
- `Theme.swift`: adaptive colors and shared screen/row components.
- `OverviewView.swift`, `TraceViews.swift`, `ReviewView.swift`, `PromptViews.swift`: native screens.
- `Resources/SampleData.json`: the concept’s sample dataset.
- `Resources/PrivacyInfo.xcprivacy`: the app’s privacy manifest, declaring its local `UserDefaults` use.
- `Salle215Tests/` and `Salle215UITests/`: model and simulator flow tests.

## Live connection

Connect one project using its instance URL, public key, secret key, and optional environment. Keys are stored in Keychain with `WhenUnlockedThisDeviceOnly` accessibility; they are never stored in `UserDefaults` or bundled into the app. Reopening restores the connection and fetches fresh data. Disconnect removes the saved keys and clears live caches. The project menu supports changing environment and refreshing traces; disconnect to connect another project.

All five tabs have real backend data:

- **Overview:** `GET /api/public/v2/metrics` supplies all-step error rate and recorded cost, logical-root P95 latency, and separate numeric/Boolean score averages. Hour, day, and week ranges use minute, hour, and day buckets respectively. Each report makes four queries; breakdowns load when opened. Headline P95 comes from a whole-period query, with milliseconds converted to seconds. Missing data remains unavailable rather than becoming a fabricated zero. Loading, empty, partial-failure and rate-limit states are visible.
- **Traces:** `GET /api/public/v2/observations` returns 200 steps per page over a stable seven-day window. Rows are deduplicated by step ID within each trace and grouped by `traceId`. Logical `isRootObservation` takes precedence over physical parentage; missing parents and cycles do not become fabricated roots. Opening a trace fetches its remaining pages and I/O. Local trace filters explicitly apply to loaded traces. Sessions fetch their own observation pages within the same window.
- **Search:** indexed server-side observation filters support trace ID, session, user, name, I/O, and status text. Searches preserve time bounds and environment and support loading additional pages. Results group by trace ID; opening a result fetches complete trace details within the window.
- **Prompts:** `GET /api/public/v2/prompts` paginates metadata; `GET /api/public/v2/prompts/{name}` lazily retrieves the requested version or label. Folder names are URL-encoded, text/chat prompts are supported, and production/latest comparisons preserve repeated chat roles and large prompt content.
- **Review:** `GET /api/public/v3/scores` reads typed scores and comments. Good/Needs work creates a trace-level BOOLEAN score named `salle215-review-thumbs` via the supported write route `POST /api/public/scores`, including reasons and an optional comment. Writes use a stable ID across retries and appear as saved only after acknowledgement. Undo deletes only a score created by the current connection, using `DELETE /api/public/scores/{id}`. Existing reviews are protected from stale overwrite. The review queue covers loaded traces and can load more.

Successful Overview reports are cached for ten minutes across windows, manual refresh and failed retries are spaced by at least one minute, and concurrent requests are shared. A 429 response respects `Retry-After` across the relevant API bucket. Reports reaching the configured 1,000-row metrics limit are rejected with guidance to shorten the range, rather than displaying truncated aggregates. Cursor repetition and excessive automatic pagination are also guarded. These controls reduce requests but do not bypass account-specific quotas.

Requests use an ephemeral URLSession, HTTPS-only hosts, and reject redirects to keep credentials on the configured instance. v2 I/O raw strings are decoded as JSON strings or chat arrays where possible; arbitrary JSON remains readable text. Authentication, access, rate-limit, HTTP and decoding failures are surfaced. Traces crossing the window boundary may have older steps outside it.

Sample mode remains available for exploration and stores its reviews locally. Its illustrative metrics stay separate from live data. Live score POST/DELETE tests use mocks; actual account validation is read-only.

Langfuse Cloud sunsets legacy reads on **November 16, 2026**. References: [Public API and response contracts](https://langfuse.com/docs/api-and-data-platform/features/public-api), [migration guide](https://langfuse.com/faq/all/deprecated-api-migration). The app uses no legacy trace, session, observation, metric or score read endpoints.

## TestFlight

The application and test bundles are `room215.salle215`, `room215.salle215.tests`, and `room215.salle215.uitests`. The project, scheme, and Swift module are `Salle215`; the display name is **Salle 215**. Signing uses team `73MJ5ES2M3`.

Version **1.0 (1)** was archived in Xcode and uploaded successfully on October 11, 2026 using **TestFlight Internal Only**. The [App Store Connect record](https://appstoreconnect.apple.com/apps/6821614941/distribution/info) is named Salle 215 and uses `room215.salle215`. Its original SKU is immutable and is internal to App Store Connect.

Apple completed processing and the build shows **Testing**, assigned to **Internal Testers** with one invitation. The group has the account holder as its sole tester, with automatic build distribution enabled. [Open TestFlight builds](https://appstoreconnect.apple.com/teams/656f4abd-6e7d-4cb6-b371-1785f855dce4/apps/6821614941/testflight/ios). The release package includes the privacy manifest, excludes `.env` and DEBUG fixture transports, and declares no non-exempt encryption. Enter the Langfuse project keys on the device after installing; developer credentials are not shipped in TestFlight builds.
