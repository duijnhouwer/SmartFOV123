# SmartFOV123

A configurable visionOS number-finding experiment rendered independently to either or both eyes over passthrough with Compositor Services and Metal.

The app loads the complete multi-trial plan from `Config/protocol.json` before the experiment starts. A required `master_condition_template` defines the complete stimulus, and each numbered entry in `conditions` inherits it implicitly while overriding only its differences. Conditions specify repetitions and ordered blocks whose trials are randomized internally. The first three-digit number drawn from each trial's seeded random-number generator becomes the target. The participant confirms the target's location by speaking the perpendicular three-digit sequence that crosses its middle digit.

For example, if the target is `536` and the grid contains:

```text
155
738
865
```

the target runs vertically through the middle column, so the participant says “seven, three, eight.” Target placement always leaves room for this three-cell crossing, which means target centers never occur on a grid edge. The generator accepts a grid only when both the target number and its perpendicular confirmation number occur exactly once across all horizontal and vertical three-digit sequences.

The app opens directly into a binocular, head-locked compositor experience. Before trial 1, a visionOS glass card collects a participant number using the configured digit count and asks for spoken confirmation with yes or no. Saying no, or anything other than yes, returns to number entry. After confirmation, the card shows the protocol instructions and waits for “Begin.” Each trial first shows the target number above a grid of Xs. Reading the target aloud reveals the grid digits. The app accepts digit-by-digit or normal-number transcriptions for the perpendicular confirmation sequence and plays the bundled correct/wrong cue. Repeating the target while searching is silently ignored. A correct response advances automatically. Fixed-trial tasks end after the scheduled trials; time-based tasks score as many completed targets as possible before their deadline. Pressing the Digital Crown backgrounds the windowless research app, which then deliberately terminates.

Spoken forms are configured under `speech.aliases` in `master_condition_template`. Add a lowercase, single-word alias there to handle a recurring transcription such as `dree` for `3`. Every digit from `0` through `9` must resolve to at least one alias, and one alias cannot belong to multiple digits.

## Multi-trial configuration

Schema version 6 uses snake_case property names and enum values. The root protocol fields include a nonempty `protocol_name`, `subject_number_digit_count` from 1 through 12, nonempty `instructions`, `debriefing_title`, and `debriefing` text, and `task_mode`. Use `"fixed_number_of_trials"` for the original behavior or `"loop_trials_<seconds>_seconds"`—for example, `"loop_trials_300_seconds"`—to loop the specified schedule for a positive integer countdown. `foveated_rendering` defaults to `true` and is disabled only when explicitly set to `false`. The protocol name is copied into every result file; the other fields control participant-number collection and the participant cards. `<NUMBER_OF_TARGETS_FOUND>` in the debriefing is replaced with the final score. `master_condition_template` must define every stimulus parameter and `random_seed`; it is not scheduled and therefore cannot contain `repeats` or `block_nr`. Each element of `conditions` implicitly inherits the master, must explicitly define positive `repeats` and `block_nr`, and may override any nested parameter. `timer.bar` defines the countdown background and fill, including `back_corner_radius`. The stationary background is part of the trial texture, while the square-ended fill is resized by the renderer every frame in loop-trials mode. `timer.metronome` defines equal-length `start_seconds` and `beats_per_minute` arrays; each start time begins its corresponding tempo stage, and `final_gong` optionally plays `gong.caf` when the final-score prompt opens.

`random_seed` accepts:

- `"shuffle"` for a fresh random seed per repetition.
- One unsigned integer, reused for every repetition.
- An unsigned-integer array whose length must equal `repeats`.

Negative `timer.metronome.start_seconds` values disable their paired BPM stages; setting every start negative suppresses the metronome. `timer.metronome.volume` scales the peak-normalized tick and tock assets from silence (`0`) through full amplitude (`1`). `timer.final_gong` controls whether `gong.caf` plays when the final-score prompt opens.

`speech.reset_seconds` controls how long an incomplete one- or two-digit trial response may remain idle before its recognition pass is restarted and forgotten. It must be defined in `master_condition_template`.

Every instantiated condition requires `block_nr >= 1`. Used block numbers must begin at 1 and be consecutive without gaps. Blocks run in ascending order, and their trials are randomized within each block. Fixed-trial mode runs that schedule once. Loop-trials mode cycles the scheduled order until its deadline, reusing each trial's configured random seed on every pass. Use `"shuffle"` when you want each scheduled trial to receive a unique seed at experiment creation; use a fixed seed or a seed list when you intentionally want repeats. Trial names (`trial1`, `trial2`, …) remain unique when loop-trials mode revisits a source condition.

The entire configuration and schedule are preflighted at app launch. Validation rejects malformed or unknown keys, incomplete master parameters, missing scheduling fields, invalid repeats or seed arrays, nonconsecutive blocks, and invalid geometry, colors, or speech aliases. Both `tiles.number_horizontal` and `tiles.number_vertical` must be at least 4. If preflight fails, the participant card reports the configuration error.

Grid generation happens when each trial is about to run. The target is drawn first from that trial's seeded random-number generator. Candidate grids are then generated until both the target and its perpendicular response occur exactly once across all horizontal and vertical three-digit sequences. A rejected candidate advances the same deterministic random-number stream; it does not invalidate or abort the experiment.

## Run on Apple Vision Pro

1. Open `SmartFOV123.xcodeproj` in Xcode.
2. In **Signing & Capabilities**, select your Personal Team.
3. Pair the headset, enable Developer Mode, and select it as the run destination.
4. Build and run.
5. Verify that an X grid and unboxed target appear, read the target to reveal the digits, then say the three crossing digits and confirm that the next trial starts automatically.

The app targets visionOS 2.0 or later. Speech recognition uses Apple's Speech framework and prefers on-device recognition when the active recognizer supports it.

## Development result output

> **Testing status:** This result-file writing and Files/AirDrop transfer path has not yet been tested on Apple Vision Pro hardware.

The first completed trial in an app run creates a local-time-stamped file in the app's Documents container:

```text
Documents/Results/result_007_20260814_130156.json
```

The file is always valid JSON. Its `trials` array grows after each completed trial:

```json
{
  "experiment": {
    "application": "SmartFOV123",
    "protocol_name": "example",
    "subject_number": "007",
    "task_mode": "loop_trials_300_seconds",
    "start_date": "2026-08-14",
    "start_time": "13:01:56-04:00"
  },
  "trials": [
    {
      "name": "trial1",
      "definition": {
        "condition_nr": 3,
        "block_nr": 1,
        "random_seed": 123,
        "digits": { "...": "complete resolved digit parameters" },
        "annotation": { "...": "complete resolved annotation parameters" },
        "timer": {
          "bar": { "...": "complete resolved time-bar parameters" },
          "metronome": { "...": "complete resolved tempo progression" }
        },
        "tiles": { "...": "complete resolved tile parameters" },
        "surround": { "...": "complete resolved surround parameters" },
        "fov": { "...": "complete resolved FOV parameters" },
        "speech": { "...": "complete resolved speech parameters" }
      },
      "seeded_stimulus": {
        "target_number": 512,
        "target_orientation": "leftright",
        "response_number": 613,
        "grid": [[4, 5, 7, 9], [6, 4, 6, 8], [2, 5, 1, 2], [8, 0, 3, 4]]
      },
      "results": {
        "start_time_ms": 1204,
        "digit_reveal_ms": 4839,
        "target_found_ms": 12751,
        "speech": [{"utterance": "512", "ms": 4817}, {"utterance": "613", "ms": 12751}]
      }
    }
  ],
  "summary": {
    "score": 12,
    "duration_seconds": 300,
    "end_time_ms": 312751
  }
}
```

The `experiment` block records the application, configured protocol, confirmed participant number, and local experiment-start date and time in ISO 8601-compatible forms. Loop-trials files also record `task_mode`. The participant number is a string so leading zeroes are preserved. Each trial has its unique name and a complete `definition` containing the source condition's 1-based `condition_nr`, concrete block and actual random seed, and every resolved parameter section. `repeats` is omitted because it has no meaning in a completed-trial record. `seeded_stimulus` records the generated target, its `leftright` or `topdown` orientation, the expected response, and the displayed grid as rows of integer digits. `results` records monotonic integer milliseconds since app launch for the trial start, digit reveal, and correct response, plus every transcript that successfully parsed as three digits and its detection time. Speech aliases are replaced with their configured digits before storage, and an entirely numeric result is collapsed without spaces (`Free 56` becomes `356` when `free` maps to `3`). Words without a configured mapping remain visible in the stored utterance. At a loop-trials deadline, `summary` records the final score, configured duration, and end time, even when no target was completed. These timestamps intentionally provide practical event timing rather than millisecond measurement precision.

Scalar arrays, grid rows, and speech detections are formatted horizontally. No template resolution is needed to interpret the result. The app rewrites the document atomically, and a trial advances only after the updated JSON is written successfully.

The app exposes its Documents directory to the visionOS Files app. To transfer a result manually, open **Files → On My Apple Vision Pro → SmartFOV123 → Results**, pinch and hold the file, choose **Share**, and AirDrop it to the Mac. Keep result files before deleting or reinstalling the development app because doing so can remove its app container.

## Display compositing

Each resolved condition selects one of two display models in its `fov` section:

```json
"fov": {
  "mode": "optical_see_through_simulation",
  "peak_opacity": 0.35
}
```

- `video_passthrough` gives every completed stimulus RGB value the same `peak_opacity`. Black remains visible and darkens passthrough. Use `peak_opacity: 1.0` for an opaque condition.
- `optical_see_through_simulation` approximates an additive optical display. Opacity scales with the brightest RGB channel, so black is fully transparent and white receives `peak_opacity`.

The app draws the complete stimulus—surround, tile grid, and digits—directly into one sRGB texture. It then converts every finished pixel to the selected display model before Metal presents the texture.

`peak_opacity` must be between `0.0` and `1.0`. This alpha-compositing model is an experimental simulation on video-passthrough hardware; it does not reproduce a physical optical display's luminance or contrast automatically.
