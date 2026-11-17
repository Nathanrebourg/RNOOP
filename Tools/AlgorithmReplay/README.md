# NROOP local algorithm replay

Requires macOS 13+ and a Swift toolchain to build from source. The delivered standalone tools ZIP includes an Apple Silicon executable. Everything stays local. Replay performs actual Swift calculations; Python only converts backups and evaluates reports.

From the source root:

```sh
swift build --package-path Tools/AlgorithmReplay -c release
python3 Tools/nroop_lab.py example work/example-synthetic.json
swift run --package-path Tools/AlgorithmReplay AlgorithmReplay work/example-synthetic.json work/report.json
python3 Tools/nroop_lab.py evaluate work/report.json --output work/evaluation
```

Create `work/` first if needed. The example is synthetic and cannot establish real accuracy.

## From a backup

Export a checkpointed `.noopbak` using NROOP's existing backup flow. Keep the original. Inspect identifiers, then choose one raw WHOOP 5 owner and a completed local day:

```sh
python3 Tools/nroop_lab.py inspect backup.noopbak
python3 Tools/nroop_lab.py capture backup.noopbak work/day.json --owner RAW_OWNER --computed-id COMPUTED_NAMESPACE --day 2026-11-13 --offset 3600 --age 30 --case-id day-01
swift run --package-path Tools/AlgorithmReplay AlgorithmReplay work/day.json work/day-report.json
```

Replace owner, namespace, age and fixed offset with the actual values. `--computed-id` defaults to raw owner + `-noop`; legacy installations may use a shared namespace instead. Optional flags: `--manual-hrmax`, `--deep-window`, `--v1`. Current days are evaluated against a full 24-hour expected interval by the converter, so prefer completed days; the in-app experiment instead measures the elapsed day. Offset is explicit and fixed, not historical zone/DST inference.

Unsupported numeric or capped reads are rejected rather than silently repaired. A live SQLite file with a nonempty WAL must be exported/checkpointed first. ZIP conversion reads only the expected database entry, at most 2 GiB; settings and arbitrary paths are ignored. RR needs current WHOOP 5 labels 5/7; legacy/mixed-unit rows are withheld, never guessed.

## Independent references

Use a separate UTF-8 CSV:

```csv
caseID,metric,value,source,independent,split
```

Fill real measured/observed values only. Metrics: recovery (0–100), hrmax (bpm), sleep_need (hours). Sources: whoop, diary, measured. Set independent=true only when the reference did not come from the NROOP candidate/incumbent; set split=holdout for evaluation data not used to choose parameters. Training references and synthetic cases never contribute to validation. A diary's sleep duration is only a contextual comparator for sleep need, not a measurement of true physiological need.

```sh
python3 Tools/nroop_lab.py evaluate work/day-report.json --references references.csv --output work/evaluation
```

Open `evaluation.html` locally. Read matched counts, missing candidates, units and provenance before interpreting MAE/bias. No reference means descriptive results only, not zero error or validated accuracy.

## Recording schema

JSON schema 1 contains: origin (`synthetic`/`recorded`), caseID, owner, dayStart (Unix local midnight under offset), now (within that day), offset (seconds east of UTC), age (0 unknown), optional sex/manualHRmax/useV2/deepWindow, raw hr [{ts,bpm}], gravity [{ts,x,y,z}], rr [{ts,rrMs,srcChannel,ord?,seq?}], events [{ts,kind}], band [{ts,state}], history [{dayStart,source:"computed",hours?,hrv?,rhr?,resp?,naturalWake?,rested?,disrupted?}], and historyStreams [{owner,dayStart,hr,gravity}]. Empty arrays are explicit. Raw current streams may cover 30 hours before dayStart through now. Histories must be distinct, strictly prior and bounded. See `docs/NROOP_ALGORITHM_LAB.md` for formulas, quality gates, provenance and limitations.
