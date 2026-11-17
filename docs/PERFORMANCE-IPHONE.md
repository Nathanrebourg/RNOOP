# Dated iPhone performance experience

The iPhone shell presents Today, Health, Activities and More. It uses the existing Repository and scoring outputs. The three score rings open dedicated, date-anchored pages. The default liquid-today preference selects this experience; the classic Today option remains available. Advanced sleep, trends, journal, workout and health tools remain reachable. Android keeps its existing presentation; no analytics or stored schemas changed.

## Data and provenance

PerformanceContext validates canonical day keys and calendar windows. PerformanceSnapshot reads exact-day resolved values and preserves source metadata. Missing values are not carried into another selected date. Trends exclude future days and split at calendar gaps. Temperature history retains a single scale, using the existing absolute/deviation preference and source attribution. Raw oxygen channel diagnostics are excluded from the five vital-sign count. The daily stress proxy reuses StressModel; an exact stored stress point wins over a derived prior-day model.

## Coach

The contextual launcher reuses AICoachEngine and its configured provider, Keychain and consent gates. Each screen/day/metric/window has a separate in-memory conversation, with at most eight cached contexts. These engines neither restore nor write the existing persistent general transcript. Opening a screen or contextual sheet never sends a question. Configuration-only CoachView skips general history, automatic briefs, pending-prompt consumption and automatic model refresh; the general Coach entry and scheduled-notification route retain their prior behavior.

At explicit send time, the contextual engine re-reads data consent. With consent enabled, only a dated text summary is added, without current-day auxiliary signals. With consent disabled, only the new question and a redacted screen envelope are sent: cached history and the dropped-message summarizer are excluded. The user-entered question itself is sent as requested. No live provider call was made during this change's verification.

## Personal sensor visual

The iPhone asset NathanWhoopSensor is a background-extracted/retouched version of the product image Nathan supplied and explicitly requested in this personal build. It is an illustration of his model, not a Bluetooth connection indicator or a live sensor reading. No readings are drawn onto it as fixture values in the native app.

## Build

The regular project.yml keeps the upstream Watch targets. project-phone.yml is the same specification with the embedded NOOPWatch dependency removed, allowing a standalone iPhone build without the unavailable watchOS SDK. Regenerate it from project.yml after version/configuration changes, then run:

```sh
xcodegen generate --spec project-phone.yml
xcodebuild -project Strand.xcodeproj -scheme NOOPiOS -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

Signing/installation uses the existing personal sideload workflow. The resulting unsigned IPA must be signed by the user's installation tool. No App Store/TestFlight publication is involved.

## Validation

Focused native tests cover dated windows, strict dates, missing values, consent redaction, nonpersistent conversations, provider context boundaries, temperature and oxygen trends, and stored stress without a daily row. Existing coach prompt, sleep-context and URL/error tests also run. Simulator screenshots use only the repository's pre-existing DEBUG demo seeder on a dedicated simulator; they are not Nathan's measurements. No physical strap/iPhone validation or live AI-provider request is claimed.

Delivery version: 12.7.0 (445). Final unsigned iPhone Release and simulator builds passed. The macOS native selection executed 38 tests without failure. The general Python suite retains six failures and one error with the same seven identities as the previous delivery; it is not reported as fully passing. Some existing advanced/workout screens still use English.
