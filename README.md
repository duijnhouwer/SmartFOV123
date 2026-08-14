# MobiWordFinderAVP

A configurable visionOS number-finding experiment rendered independently to either or both eyes over passthrough with Compositor Services and Metal.

The current implementation loads `Config/experiment.json`, generates a deterministic digit grid, and presents it as a head-locked stimulus at the configured visual-field position and distance. The participant searches for the configured three-digit target number and confirms its location by speaking the perpendicular three-digit sequence that crosses the target's middle digit.

For example, if the target is `536` and the grid contains:

```text
155
738
865
```

the target runs vertically through the middle column, so the participant says “seven, three, eight.” Target placement always leaves room for this three-cell crossing, which means target centers never occur on a grid edge. The generator accepts a grid only when both the target number and its perpendicular confirmation number occur exactly once across all horizontal and vertical three-digit sequences.

Use **Start trial** in the launcher to grant microphone and speech-recognition access and open the mixed immersive space. The app listens only while the trial is active, shows the latest transcript, accepts digit-by-digit or normal-number transcriptions, and plays the bundled correct/wrong cue. The launcher stays open so you can stop the trial reliably; move it aside if it blocks the grid. Closing the launcher also dismisses the immersive space. As a final safety measure, the immersive trial stops automatically after 30 seconds.

Spoken forms are configured under `speech.digitAliases` in `Config/experiment.json`. Add a lowercase, single-word alias there to handle a recurring transcription such as `dree` for `3`; aliases are loaded at launch, so changing the mapping does not require changing or recompiling Swift code. Every digit from `0` through `9` must be present, and one alias cannot belong to multiple digits.

## Run on Apple Vision Pro

1. Open `MobiWordFinderAVP.xcodeproj` in Xcode.
2. In **Signing & Capabilities**, select your Personal Team.
3. Pair the headset, enable Developer Mode, and select it as the run destination.
4. Build and run.
5. Verify that the digit grid appears, say the three crossing digits one at a time, and confirm that the app reports and plays the correct result.

The app targets visionOS 2.0 or later. Speech recognition uses Apple's Speech framework and prefers on-device recognition when the active recognizer supports it.

## Display compositing

`Config/experiment.json` selects one of two display models:

```json
"display": {
  "mode": "opticalSeeThroughSimulation",
  "peakOpacity": 0.35
}
```

- `videoPassthrough` gives every completed stimulus RGB value the same `peakOpacity`. Black remains visible and darkens passthrough. Use `peakOpacity: 1.0` for an opaque condition.
- `opticalSeeThroughSimulation` approximates an additive optical display. Opacity scales with the brightest RGB channel, so black is fully transparent and white receives `peakOpacity`.

The app first draws the complete FOV—background, grid, and digits—into one 8×8-supersampled texture. It then converts every finished pixel to the selected display model before Metal presents the texture.

`peakOpacity` must be between `0.0` and `1.0`. This alpha-compositing model is an experimental simulation on video-passthrough hardware; it does not reproduce a physical optical display's luminance or contrast automatically.
