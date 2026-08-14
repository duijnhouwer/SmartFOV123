# MobiWordFinderAVP

A configurable visionOS number-finding experiment rendered independently to either or both eyes over passthrough with Compositor Services and Metal.

The app loads the complete multi-trial plan from `Config/experiment.json` before the experiment starts. Conditions support recursive inheritance, repetitions, fixed or shuffled seeds, and ordered blocks whose trials are randomized internally. Each repetition expands into a uniquely named condition, and the first three-digit number drawn from its seeded random-number generator becomes the target. The participant confirms the target's location by speaking the perpendicular three-digit sequence that crosses its middle digit.

For example, if the target is `536` and the grid contains:

```text
155
738
865
```

the target runs vertically through the middle column, so the participant says “seven, three, eight.” Target placement always leaves room for this three-cell crossing, which means target centers never occur on a grid edge. The generator accepts a grid only when both the target number and its perpendicular confirmation number occur exactly once across all horizontal and vertical three-digit sequences.

Use **Start trial** in the launcher to grant microphone and speech-recognition access and open the mixed immersive space. The app listens only while the trial is active, shows the latest transcript, accepts digit-by-digit or normal-number transcriptions, and plays the bundled correct/wrong cue. A correct response closes the current immersive trial and advances to the next scheduled trial. The launcher stays open so you can stop a trial reliably; move it aside if it blocks the grid. Trials have no automatic time limit.

Spoken forms are configured under `speech.aliases` in the main condition. Add a lowercase, single-word alias there to handle a recurring transcription such as `dree` for `3`. Every digit from `0` through `9` must resolve to at least one alias, and one alias cannot belong to multiple digits.

## Multi-trial configuration

The first condition must be `main`, inherit `null`, set `blockNr` and `randomSeed` to `null`, set `repeats` to `0`, and define every parameter. Named templates can inherit from it and override individual nested values. A concrete definition uses `__condition_nr__`; every repetition expands to a unique immutable identity such as `condition1`, even when seeds or all resolved parameters are identical.

`randomSeed` accepts:

- `"shuffle"` for a fresh random seed per repetition.
- One unsigned integer, reused for every repetition.
- An unsigned-integer array whose length must equal `repeats`.

Every instantiated condition requires `blockNr >= 1`. Used block numbers must begin at 1 and be consecutive without gaps. Blocks run in ascending order, and their trials are randomized within each block. Initial trial names (`trial1`, `trial2`, …) are assigned after scheduling and remain separate from condition identities so a future retry can create a new trial for an existing condition.

The entire configuration and schedule are preflighted at app launch. Validation rejects malformed or unknown keys, incomplete main parameters, invalid or circular inheritance, illegal reserved names, duplicate expanded names, invalid repeats or seed arrays, nonconsecutive blocks, and invalid geometry, colors, or speech aliases. If preflight fails, **Start trial** remains disabled and the launcher reports the configuration error.

Grid generation happens when each trial is about to run. The target is drawn first from that trial's seeded random-number generator. Candidate grids are then generated until both the target and its perpendicular response occur exactly once across all horizontal and vertical three-digit sequences. A rejected candidate advances the same deterministic random-number stream; it does not invalidate or abort the experiment.

## Run on Apple Vision Pro

1. Open `MobiWordFinderAVP.xcodeproj` in Xcode.
2. In **Signing & Capabilities**, select your Personal Team.
3. Pair the headset, enable Developer Mode, and select it as the run destination.
4. Build and run.
5. Verify that the digit grid appears, say the three crossing digits one at a time, and confirm that the app reports and plays the correct result.

The app targets visionOS 2.0 or later. Speech recognition uses Apple's Speech framework and prefers on-device recognition when the active recognizer supports it.

## Display compositing

Each resolved condition selects one of two display models in its `fov` section:

```json
"fov": {
  "mode": "opticalSeeThroughSimulation",
  "peakOpacity": 0.35
}
```

- `videoPassthrough` gives every completed stimulus RGB value the same `peakOpacity`. Black remains visible and darkens passthrough. Use `peakOpacity: 1.0` for an opaque condition.
- `opticalSeeThroughSimulation` approximates an additive optical display. Opacity scales with the brightest RGB channel, so black is fully transparent and white receives `peakOpacity`.

The app first draws the complete FOV—background, grid, and digits—into one 8×8-supersampled texture. It then converts every finished pixel to the selected display model before Metal presents the texture.

`peakOpacity` must be between `0.0` and `1.0`. This alpha-compositing model is an experimental simulation on video-passthrough hardware; it does not reproduce a physical optical display's luminance or contrast automatically.
