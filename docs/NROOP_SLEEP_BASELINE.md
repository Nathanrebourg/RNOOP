# NROOP personal overnight HR baseline experiment

This is a default-off, measurement-only comparison using the existing `SleepStager.adaptiveOvernightHRBaseline` and optional `sleepHRBaseline` detector input. It never supplies stored sleep sessions, nightly HRV/RHR, sleep debt, Rest, recovery, personal score baselines, Health writes, live state or a provided hypnogram. The earlier Effort and HRV experiments remain independent.

## Activation and scope

Activate Settings → Advanced → Test Centre → Sleep & Rest (or the master mode). On the next actual analysis pass with enough HR to process the newest local day, one `sleep baseline experimental=true` line is added to the Sleep channel. The inherited whole-pass unchanged-input gate still applies; synchronizing new data or explicitly forcing analysis starts a pass. There is no background job or network export added.

Only the newest day is compared, limiting the extra reads and detector work. For that day only, an active Sleep trace bypasses per-day reuse and does not write a DayScan cache entry. This means a newly enabled trace or changed older history cannot reuse an experiment built with different evidence. Historical days keep their existing cache path. The comparison line is not cached for replay; each qualifying pass recomputes it from local data. With the Sleep mode off, no history reads or candidate detections run and cache eligibility is unchanged.

## Historical reference

The experiment reads the same owner as the target day's streams. It selects fourteen fixed local **00:00–06:00 calendar windows**, all ending at or before the beginning of the entire target detector read window (currently 30 hours before the target day). Current-night samples and any other samples in the target read window are excluded from reference training.

These windows are a proxy for nocturnal HR, not independently identified sleep. Each read is half-open `[start, end)`, capped at 50,000 HR rows; a read at the cap is declined conservatively. Nonpositive BPM values are excluded. Identical same-second copies count once. If a timestamp has different positive BPM values, the entire timestamp is excluded. The median BPM is computed per occupied minute, then the median of those minute values describes the window: packet density cannot give one hour extra weight.

A window requires at least **180 occupied minutes**, with the earliest and latest occupied minutes at least **240 minutes apart**. Missing minutes are not filled. At least **three distinct qualified windows** are required. Only the fourteen selected end timestamps are admitted; conflicting duplicate observations are excluded. The reference is the existing helper's median of qualified window medians, retaining its **40 bpm floor**. Every qualified window has equal weight.

The selection, three-window minimum, coverage thresholds and fixed clock band are provisional engineering choices. HR availability is not proof of wear, skin contact, rest or sleep. No motion-based quality weighting or sleep label is inferred for historical windows. Overnight work, nocturnal exercise, travel or a shifted sleep schedule can contaminate the reference. A single captured UTC offset is used for all windows, matching the current detector; historical timezone/DST changes are not reconstructed. The comparison should not be promoted on these proxies alone.

## What is compared

The real detector runs twice over exactly the same current HR, R-R, respiration, gravity, off-wrist intervals, strap sleep-state samples, timezone offset and V1/V2 setting. The only differing input is the optional personal HR reference. The incumbent uses its existing day-median fallback; the candidate supplies the historical reference to the existing session HR-confirmation gate. Motion-corroborated widening and all other detector gates remain in force.

Both outputs are restricted to detector sessions ending on the target local day, sorted by start and end. `scope=detector` is intentional: outputs are **before** device-provided or HR-only fallback sessions, manual corrections, main-night selection and motion-aware post-detection wake refinement. They may differ from the final displayed daily night, especially if a nap also ends on this day. This is not a new sleep-stage classifier and not a claim of PSG or WHOOP equivalence.

## Report

- `status=compared`: both real detections ran. `nights` and `baselineBpm` describe the admitted historical reference.
- `status=insufficient-history`: fewer than three qualified distinct windows; both outputs are `nil`, never invented zero sleep.
- `status=no-motion`: enough history, but the current stream cannot run this motion-based comparison. The app's existing HR-only fallback is unchanged.
- `status=target-read-capped`: a current HR, R-R, gravity or respiration read reached its configured ceiling; no comparison is emitted as if complete.
- `status=cancelled` can appear when Swift history collection is cancelled. Android Room reads retain coroutine cancellation.
- `originalSessions` / `candidateSessions`: detector session counts. An actual empty result is zero.
- `originalInBedSec` / `candidateInBedSec`: sums of detected session spans, not necessarily the primary night's in-bed time.
- `originalAsleepSec` / `candidateAsleepSec`: sums of light/deep/REM stage seconds within those sessions. Sparse motion can yield a session with zero classified asleep seconds.
- `originalWindows` / `candidateWindows`: start:end epoch-second boundaries. `none` is a completed empty detection; `nil` means no comparison was available.

Evaluate several real WHOOP 5.0 nights, including variations in HR, restless nights, stable elevated HR and known wakeful time. Compare boundaries against a sleep diary and inspect history coverage. A shorter or longer candidate alone does not establish better detection.

## Verification

Swift tests cover historical bounds, minute weighting, duplicates/conflicts, missing data, minimum history, stale/future evidence, the existing floor, real detector changes, preserved low-HR/dense-motion nights, off-wrist exclusion, missing motion, capped reads and unchanged daily scoring after comparison. Kotlin exercises the real V1/V2 detectors and their production pure dependencies. Nine trace records are literal stdout of an executable linked to the compiled Swift analytics modules. The real Kotlin history wrapper is separately compiled/executed with only the repository replaced by a bounded-read test fixture. No scoring or detector substitute is used.

Builds of the shared iPhone and macOS app targets are required. A full Android app/Gradle/JaCoCo budget run still requires the Android SDK; targeted JVM compilation does not cover the whole Android application. Hardware installation and physiological validation require the user's iPhone and strap.
