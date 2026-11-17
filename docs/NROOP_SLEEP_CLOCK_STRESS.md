# Sleep clock and nocturnal activation — frozen exploratory v1

Apple research screen, default off on each opening, available under Local improvements.
This is a read-only design hypothesis, not a validated sleep score or a WHOOP replica.
No IntelligenceEngine score, cache, profile, backup schema or BLE command changes here.
The Kotlin numerical twin is headless; no Android screen or full Android build is claimed.

## Candidate and missing data

Candidate = 100 × (0.40D + 0.25E + 0.20C + 0.15N).
D = min(1, known asleep seconds / 28800); E = known asleep seconds / bed interval.
The eight-hour reference and weights are provisional engineering choices, frozen for comparison.
N = 1 − logistic(zHR − zRMSSD), using prior same-channel nocturnal summaries.
It is a nocturnal cardiac calmness proxy, not mental stress. A value of 0.5 is neutral at the baseline.
No component substitutes for another. Any missing component withholds the total.
Full, known, non-overlapping stage coverage and an explicitly non-sparse stored night are required.
Unknown stages, holes, overlaps and sparse/unknown staging cannot become complete sleep evidence.

C uses the median circular distance of bedtime and wake time from prior nights, summing the
separate median bed/wake distances and scaling against 240 minutes. It requires three distinct prior
wake dates in the previous 28 days, ending before target bedtime. Identical duplicates collapse;
conflicting dates are excluded. There is no future or same-night baseline leakage.
Clock times use the current timezone's historical daylight-saving rules. Past travel zones are
unknown. Regularity does not establish sleep quality, adequacy or causal benefit.

## Source and raw signal gates

The Apple adapter reads attributable computed nights from the selected owner namespace and the
canonical NOOP cache. A matching sleep_performance input-source tag is mandatory. It shows the
longest attributable session per wake date (same-length conflicting sessions excluded). The picker
covers 30 local wake dates; a 60-day bounded history supplies earlier selected-night baselines.
Stored Rest is shown only with matching provenance. At most the target plus seven previous nights
have their raw signals loaded, separately and sequentially. Every query reads only the selected owner.
A before/after analysis fingerprint rejects detected local changes; it is not an atomic DB snapshot.
Generation, cancellation, refresh, selected source, local date and timezone guards invalidate results.

Activation requires confirmed WHOOP 5.0/MG provenance, one historical RR channel (5 or 7), and the
existing RRReplayIdentity normalization. Channel 6 live RR is not assumed equivalent. Conflicting
RR identities refuse the night. The same channel must supply at least three qualified previous nights.
Five-minute windows must be entirely asleep. Existing HRV cleaning and motion machinery are reused:
at least 80% HR/RR/motion coverage per window, clean RR rejection <=10%, bounded 15-second gaps,
and motion masking. At least 12 windows and 70% asleep coverage are required for a night summary.
HR 30–250 bpm, positive finite RMSSD, and finite usable gravity are checked. Reads cap at 60000 HR,
120000 RR and 60000 gravity records per night; reaching a sentinel cap withholds a partial result.
Baselines use minimum HR/RMSSD scales of 5 bpm/10 ms. All gates are provisional, not accuracy claims.
A labelled 'qualified' supplied summary is checked again against numeric/window/coverage bounds.
Awake stress is never substituted for sleeping physiology.

## Verification and limits

Swift tests cover chronology, midnight circularity, incomplete staging, provenance, raw replay,
coverage, channel ambiguity and invalid qualified summaries. Tools/Oracles/SleepClockStress contains
actual compiled Swift output for summary and raw-signal cases, pinned literally in Kotlin/JUnit and
reverse-pinned in Swift. App-hosted SQLite tests verify canonical cache ownership and read-only scores.
These establish deterministic implementation and refusal behavior, not physiological validity.
Real WHOOP recordings and independent sleep labels are still needed before considering score changes.
