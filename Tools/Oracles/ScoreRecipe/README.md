# Score recipe oracle

`Fixtures.swift` and `main.swift` form a standalone Swift executable linked against the package's
compiled objects. Its literal output is independently pinned in `ScoreRecipeTests.swift` and
`ScoreRecipeTest.kt`; the Kotlin fixture generator produces the same transcript, including exact
Double bits and payload fingerprints. Cases cover final daily Rest, current-inclusive Recovery
baseline snapshots (including an omitted stale driver's retained state), both Effort methods and
sex coefficients, mixed cadence/gaps, physiological windows, UTF-8 source and context.

Build the analytics package first, then run:

```sh
python3 Tools/Oracles/ScoreRecipe/verify.py --build-dir /path/to/scratch/arm64-apple-macosx/debug
```

The verifier compiles and runs the Swift executable, checks both independently stored literals,
and prints the transcript. Kotlin unit tests compare their independently computed transcript to
the Swift literal and verify decoding/replay. No sensor, database or network is needed at runtime.
