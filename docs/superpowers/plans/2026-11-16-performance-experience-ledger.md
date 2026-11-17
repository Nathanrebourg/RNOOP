# Execution ledger

- Isolated copy created from the previously delivered 12.6.0 sources; original source directory and archive left intact.
- Baseline iPhone build passed with the same standalone-phone variant used by previous deliveries; the default Watch dependency requires an unavailable SDK.
- Dated context: eight focused native checks pass, covering canonical date parsing, DST, cutoff windows, identity, missing values and consent envelopes.
- Initial scoped coach tests failed on the missing nonpersistent/context APIs, then passed after implementation.
- Reviewer: native_experience_review inspected an immutable snapshot against the delivered baseline. All five reported issues were addressed in one correction pass.
- Snapshot regressions reproduced six assertions across three tests (health aliases/requested series, raw diagnostic count and exact stress-only day) before correction.
- Consent-history regression first failed on the missing wire-policy helper; contextual consent-off requests now exclude history and the dropped-message summarizer.
- Focused native suite: 38 tests pass, including prior coach prompt/sleep/URL tests.
- Broad Python suite: 410 tests, six failures, one error, six skips; the seven failure/error identities exactly match the prior delivery's baseline.
- Source comment hygiene: passes, no new detached comments.
- iOS simulator compilation passes. Visual inspection led to removing the duplicate system tab bar, compacting the header, translating new labels and adding an explicit configuration-sheet close button.
- Selected implementation boundaries: this is an iPhone presentation change; shared analytics/BLE/schema and Android behavior are unchanged. Contextual history is session-only, preserving the existing general saved transcript. Current-day auxiliary coach signals are excluded from historical screen requests to avoid mixing dates.
- Final builds after the close-button adjustment: iOS simulator and unsigned iPhone Release pass; macOS focused native tests pass (38/38).
- Simulator acceptance: historical-day values, recovery details, 7/28-day trends, date/metric-preserving coach, provider setup dismissal, Activities sensor asset, empty activity state and the existing workout picker were inspected. No workout was started. Captures use synthetic demonstration data.
- Delivery: 12.7.0 (445), standalone-phone unsigned IPA, complete source archive and binary-capable patch against the immutable 12.6.0 source ZIP. Packaging verification checks source bytes, patch replay, bundle versions, arm64 executable and ZIP integrity; see the accompanying report.
- Physical iPhone/WHOOP use and live provider replies remain untested. Existing workout selection strings still include English; the new performance presentation is translated into French.
