# Exercise GPS evidence and retrospective walking estimate — v1

Apple screen under Local improvements, opt-in, local and read-only. No fitness-age, Effort or VO2max
score is changed. Kotlin numerical twins have headless tests; Android UI/build parity is not claimed.
The screen reviews at most 30 stored GPS sessions from the preceding year. One historical HR owner
must be explicitly attested for each session; active strap selection alone is not historical proof.

## Generic running or walking sessions

Haversine route distance uses R=6371000 m. Elapsed speed includes stops. HR is time weighted with
no extrapolation over gaps beyond 10 seconds. Metres/beat = elapsed speed × 60 / mean HR.
These are unadjusted descriptive measurements, not oxygen cost, VO2max or vVO2max. VO2max is oxygen
uptake; vVO2max is speed at that uptake. Terrain, wind, temperature, fatigue and sensor error matter.
No elevation is stored, so slope is always unknown. The generic result never contains VO2max.

Frozen engineering gates: running/walking; duration 600–21600 s; 2–100000 GPS points; valid finite
coordinates; original timestamps and horizontal accuracy <=20 m; GPS coverage >=90%; gaps <=15 s;
legs <=8 m/s; route >=1000 m; stop time (speed <0.5 m/s) <=10%; stored/route discrepancy
<=max(50 m,10%). HR has 2–100000 samples, one declared owner, 40–220 bpm, strict in-window
increasing timestamps, gaps <=10 s and at least 600 s/90% coverage. Any failed gate withholds paired
metres/beat. Legacy polylines can still show geometric distance, but timing and accuracy are never
invented. These cutoffs are conservative engineering choices, not clinically validated confidence.

## Optional already-completed Kline one-mile walk

Source: Kline et al., 1987, Estimation of VO2max from a one-mile track walk, gender, age, and body weight.
Primary abstract: https://pubmed.ncbi.nlm.nih.gov/3600239/ . The study involved 343 healthy adults
aged 30–69, with a separate cross-validation sample. The absolute-uptake equation is:

L/min = 6.9652 + 0.0091 × weight_lb − 0.0257 × age + 0.5955 × sex
        − 0.2240 × fastest_time_minutes − 0.0115 × fourth_quarter_HR.

Use kg / 0.45359237 for lb; convert L/min to mL/kg/min by ×1000/kg. Sex is the study coefficient
(0 female, 1 male), explicitly chosen, never inferred. The fourth-quarter HR is the final recorded
observation, not mean whole-session HR. Cross-validation SEE is 0.355 L/min; it is not an individual
confidence interval or proof of accuracy with a WHOOP bracelet.

Only a retrospective, independently measured flat mile walked throughout qualifies. The user must
confirm repeated fastest trials within 30 seconds and select the faster one. GPS alone cannot prove
this protocol. The UI does not ask anyone to perform an exercise test. Additional provisional gates:
age 30–69, weight 30–250 kg, duration 10–30 min, valid repeat duration, positive finite prediction,
all generic signal gates, GPS distance within 3% of 1609.344 m, and recorded HR within five seconds
of finishing. No HRmax extrapolation is used. An ordinary run never receives this estimate.

The Olher 2019 paper (https://pubmed.ncbi.nlm.nih.gov/30802508/) concerns vVO2max from a controlled
six-minute running test. Its available abstract is not enough to implement an unambiguous model for
generic GPS sessions. No inferred correction or additional running VO2max equation is included.

## Verification

Seven numerical Swift tests and an actual compiled 14-case Swift transcript are pinned in Kotlin
and reverse-pinned in Swift. Cases cover units, malformed GPS/HR, source mismatch, gaps, stops,
missing witnesses and protocol gates. App-hosted tests verify real route metadata conversion,
legacy witness absence and withholding Kline when final HR is missing. Passing implementation
checks does not validate the protocol scientifically or establish real-bracelet accuracy.
