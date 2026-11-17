# Experimental hierarchical sleep model

The research-only `hierarchical-v1` candidate is declared before benchmarking. It does not replace
`SleepStagerV2` or feed any app recovery, sleep need or stored stage.

The first pass marginalizes the three V2 sleep emissions with log-sum-exp, then decodes wake/sleep.
Wake persistence is 0.90. Sleep-to-wake is the shipped transition weighted by shipped sleep priors:
`(0.15*0.007 + 0.22*0.015 + 0.50*0.03) / 0.87`. Remaining mass stays in sleep.
The second pass decodes deep/REM/light only inside continuous sleep runs, using the shipped sleep
transition rows renormalized after removing wake. The shipped onset REM penalty is retained.
Every absent 30-second sensor epoch is `unknown`, and model state resets at every such gap.
An epoch with at least one heart-rate sample in 1...300 bpm or finite nonzero gravity vector has observed input;
this minimal support check is not a validated quality or accuracy claim.

Evaluation will use the 47 already examined BIDSleep 1.0.1 first nights (30 previously labelled
training, 17 previously labelled holdout). This is a retrospective benchmark, not a fresh independent
holdout. There is one declared candidate and no parameter selection on these results. Apple Watch
signals, provided sleep windows and expert-reviewed Dreem 2 labels do not validate WHOOP 5.0 staging.
Report coverage and accuracy counting abstentions as incorrect alongside conditional metrics; missing
predictions must never silently turn into wake or improve an apparent denominator.


## Retrospective result, 15 November 2026

One candidate was run without adjusting any parameter after seeing these results. The 47 first nights
contain 41,734 reference-labelled 30-second epochs. The native executable's immutable SHA-256 is
`6fd6447e518539832c15528b21a07f4b35b87ea9718cd635bc033ba73100ad45`.

| Previously used cohort | People | Shipped accuracy | Candidate accuracy | Shipped person macro F1 | Candidate person macro F1 |
|---|---:|---:|---:|---:|---:|
| Training | 30 | 53.285% | 51.417% | 0.475981 | 0.462282 |
| Holdout (already examined) | 17 | 60.073% | 59.029% | 0.538645 | 0.525898 |
| All | 47 | 55.700% | 54.126% | 0.498647 | 0.485292 |

Accuracy above uses every known reference epoch; unknown candidate predictions count as errors.
The candidate abstains on 1,032/41,734 reference epochs (2.473%). Mean participant wake F1 is
0.385700 shipped versus 0.348580 candidate. This is not solely an abstention penalty: on the exact
same observed candidate support, training macro F1 is 0.475055 shipped versus 0.468052 candidate;
the previously examined holdout is 0.543686 versus 0.530237.

**The candidate is not promoted.** It remains an explicit research option; app scores and stages are
unchanged. A two-step architecture alone does not establish a better classifier. Reusing these results
to choose a new model would require development-data labelling and a fresh participant evaluation.
These numbers also do not validate session detection, raw WHOOP sensor decoding or RR-dependent terms.

Reproduce locally from the prepared attributed cases shipped with the research tools:

```sh
python3 Tools/nroop_hierarchical.py \
  --binary /path/to/sleeppsg \
  --training-manifest /path/to/manifests/training.json \
  --previous-holdout-manifest /path/to/manifests/holdout.json \
  --output /path/to/new-output-directory
```

The output directory must not already exist. Its `summary.json` includes input, manifest, report and
native binary hashes, all per-participant scores, unknown coverage and paired common-support summaries;
`summary.html` is a static reader. The case preparation and dataset licence/attribution remain those of
[BIDSleep 1.0.1](https://physionet.org/content/bidsleep-dataset/1.0.1/).

Verification: all 46 SleepPSG Swift tests passed, including the existing exact shipped-port equivalence
corpus and ten new hierarchy/report cases; ten Python summary/bounded-I/O tests passed. The actual native model ran
all 47 cases twice; report variant payloads were identical when the availability predicate was replaced
by the shared `SleepSignalCoverage` helper. The candidate is tool-only, with no Android/app formula or
persisted-data contract added.


## Native report scopes and bounded wrapper

For `hierarchical-v1`, `metricScope: conditional-on-nonunknown-predictions` explicitly scopes the
legacy-shaped top-level `epochs`, `confusion`, `accuracy`, `macroF1`, `kappa` and `perStage`. The separate
`fullReference` block reports a four-by-five confusion matrix (last prediction column `unknown`), every
known reference epoch, and stage precision/recall/F1 with abstentions counted as false negatives. The
full-reference stage supports include abstained epochs. Ordinary recipe report fields stay compatible.
A real two-epoch native fixture (light prediction, then unknown; both references light) has conditional
accuracy 1/F1macro .25, but full-reference accuracy .5/F1macro 1/6 and light support 2/recall .5.

The Python wrapper checks each manifest against 1 MiB, case against 64 MiB and native report against
16 MiB before parsing. It reads at most limit+1 bytes after the initial size check, so growth after stat
cannot bypass the cap. Only bounded subject/night/truth metadata is retained across cases, never the
sensor arrays; each manifest has at most 512 cases and a truth grid at most 2,880 epochs. The native
input hash must still match the validated case after the subprocess runs. This both bounds individual
reads and avoids retaining every night's sensor-object graph in memory.
