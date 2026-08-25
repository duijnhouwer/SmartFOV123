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

The app opens directly into a binocular, head-locked compositor experience. Its protocol-selection card numbers valid user protocols first, then numbers invalid user protocol files in a separate list. Selecting a valid number runs that protocol; selecting an invalid number opens the existing configuration-error card with that file's validation failure. If no user protocol is valid, the managed `fallback_do_not_edit.json` is added as the fallback while all faulty user files remain listed. A valid fallback is the sole valid selection; an invalid fallback joins the faulty list, leaving no valid selection. The fallback is not shown when any user protocol is valid. Before trial 1, a visionOS glass card collects a participant number using the configured digit count and asks for spoken confirmation with yes or no. Saying no, or anything other than yes, returns to number entry. After confirmation, the card shows the protocol instructions and waits for “Begin.” Each trial first shows the target number above a grid of Xs. The protocol independently selects keyboard or speech entry for the target and crossing digits. A configured Space press or spoken “stop” records the find time before the crossing number is verified. Correct/wrong feedback and automatic advancement work with either input method. Fixed-trial tasks end after the scheduled trials; time-based tasks score as many completed targets as possible before their deadline. Pressing the Digital Crown backgrounds the windowless research app, which then deliberately terminates.

Spoken forms are configured once under `input.speech.aliases`. Add a lowercase, single-word alias there to handle a recurring transcription such as `dree` for `3`. Every digit from `0` through `9` must have at least one alias, and one alias cannot belong to multiple digits.

## Protocols folder

At launch, the app creates and scans `Documents/protocols` inside its app container. The visionOS Files app exposes this as **On My Apple Vision Pro → SmartFOV123 → protocols**. Only regular files whose extension is `.json` (case-insensitive) are considered; subdirectories and other file types are ignored. A protocol's displayed and recorded name is its filename without `.json`.

A leading underscore masks a protocol. For example, `_pilot.json` remains in the folder but is not loaded, validated, or shown in either the valid or faulty list. Masked files do not count as valid user protocols and therefore do not prevent the fallback from appearing. Remove the leading underscore to make the file active again.

The app manages `fallback_do_not_edit.json` specially:

- On every launch, the bundled fallback replaces the copy in `Documents/protocols`. Any direct edits to that managed file are therefore lost.
- If at least one visible user protocol is valid, the fallback is omitted from the selector entirely.
- If no visible user protocol is valid, the fallback is added to the catalog. Faulty user protocols remain listed as faulty.
- If the fallback is valid, it becomes the only valid selection in that situation. If the fallback is also invalid or corrupted, it joins the faulty list instead.

Use the fallback as a protocol template by making a copy and renaming the copy before editing it. Choose a descriptive filename that is not `fallback_do_not_edit.json` and does not begin with `_`; for example, copy it to `contrast_pilot.json`. The renamed copy is a user protocol and will not be overwritten by the app.

Visible valid user protocols are sorted alphabetically and numbered first. Visible invalid user protocols follow in a separately labelled faulty list, continuing the numbering. Selecting a valid number starts that protocol; selecting a faulty number opens its preflight error so the file can be corrected.

## App configuration

`Documents/config.json` sits beside the `protocols` folder and stores app-session settings that cannot vary by protocol or trial. In the visionOS Files app it appears at **On My Apple Vision Pro → SmartFOV123 → config.json**.

The file has this complete format:

```json
{
  "app_settings": {
    "foveated_rendering": true
  }
}
```

`app_settings.foveated_rendering` is a required Boolean. When `true`, the app requests compositor foveation if the device supports it; when `false`, it requests a non-foveated compositor layout. The setting is loaded before protocol selection because compositor layout is fixed for the app session. After changing it, quit and relaunch SmartFOV123.

If `Documents/config.json` is missing, the app installs the bundled default with foveated rendering enabled. Unlike `fallback_do_not_edit.json`, an existing `config.json` is not overwritten, so edits persist across launches and app builds. Malformed JSON, missing keys, unknown keys, or a non-Boolean value produce a configuration error at launch. `foveated_rendering` is not a protocol parameter; placing it in a protocol file rejects that protocol as containing an unknown key.

## Multi-trial configuration

Schema version 10 uses snake_case property names and enum values. The required root protocol fields are `schema_version`, `subject_number_digit_count`, `instructions`, `debriefing_title`, `debriefing`, `task_mode`, `sounds`, `input`, `master_condition_template`, and `conditions`. The protocol name comes from the JSON filename stem and is copied into every result file; `protocol_name` is not a valid JSON key. `master_condition_template` must define every stimulus parameter and `random_seed`; it is not scheduled and therefore cannot contain `scheduling` or `factors`. Each element of `conditions` implicitly inherits the master, must explicitly contain `scheduling`, and may override stimulus parameters directly or through factors.

`random_seed` accepts:

- `"shuffle"` for a fresh random seed per repetition.
- One unsigned integer, reused for every repetition.
- Inside a condition factor, an array of unsigned integers and/or `"shuffle"` values defining random-seed levels.

### Defining condition factors and scheduling

Most experiments should put their shared stimulus definition in `master_condition_template` and describe only differences in `conditions`. Every master-template parameter must represent exactly one value: factors and factor arrays are forbidden there, and `master_condition_template.random_seed` must be `"shuffle"` or one unsigned integer. Structural arrays that encode one value, such as an RGB triple, remain valid because the triple is one color rather than three alternatives. JSON arrays use square brackets (`[]`), not braces (`{}`).

Each source condition may contain a `factors` array. Every object in `factors` defines one independent experimental factor:

- Arrays within one factor expand in parallel as that factor's levels. Arrays must have the factor's maximum length or length 1; scalar values and one-element arrays broadcast across its levels.
- Separate factors form a Cartesian product.
- Factor properties are merged recursively, so one factor may set `fov.eye` while another sets other `fov` properties. Two factors may not set the same final property.
- Factor arrays must be inside `factors`; arrays directly in a condition are reserved for structural values such as RGB triples.

The required `scheduling` object is independent of the experimental factors. Its `repeats` and `block_nr` arrays expand together in parallel; scalars and one-element arrays broadcast. The scheduling entries are crossed with all combinations of factor levels.

For example, this single source condition defines 2 dimming levels, 3 eye levels, and 3 geometry levels:

```json
{
  "scheduling": {
    "repeats": 1,
    "block_nr": 1
  },
  "factors": [
    {
      "passthrough_dimming": [0.0, 0.85]
    },
    {
      "fov": {
        "eye": ["left", "right", "both"]
      }
    },
    {
      "fov": {
        "width_degrees": [14.14, 21.21, 14.14],
        "height_degrees": [14.14, 21.21, 14.14],
        "zoomed_width_degrees": ["disabled", "disabled", 21.21],
        "zoomed_height_degrees": ["disabled", "disabled", 21.21]
      }
    }
  ]
}
```

The factors produce `2 × 3 × 3 = 18` resolved conditions, all scheduled once in block 1. A `random_seed` factor may mix unsigned integers with `"shuffle"`; for example, placing `"random_seed": ["shuffle", 123, "shuffle"]` alongside the three eye levels gives the right-eye level fixed seed `123`.

`scheduling.repeats: 0` explicitly skips a schedule entry. Consequently, `repeats: [1, 2, 1]` with `block_nr: [1, 3, 5]` is equivalent to `repeats: [1, 0, 2, 0, 1]` with `block_nr: [1, 2, 3, 4, 5]`. Skipped entries do not by themselves satisfy the consecutive-block requirement; another source condition must instantiate trials in blocks 2 and 4. Across the complete protocol, instantiated block numbers must start at 1 and be consecutive without gaps.

An RGB triple such as `"rgb": [1, 0, 0]` remains one atomic color. Inside a factor, use a nested array such as `"rgb": [[1, 0, 0], [0, 1, 0]]` to define two color levels. Empty factors or expansion arrays, mismatched array lengths within one factor or within scheduling, overlapping factor properties, and factor arrays outside `factors` reject the protocol during preflight with a path explaining the problem.

### Complete protocol parameter reference

All numeric values must be JSON numbers of the indicated kind. A value described as finite rejects `NaN` and infinities. An RGB value is exactly three finite numbers in red-green-blue order, each from `0.0` through `1.0`, such as `[1, 0.5, 0]`. Angular sizes, margins, radii, gutters, and offsets use degrees of visual angle. Every stimulus parameter listed below must have one scalar value in `master_condition_template`; a condition may override it with another scalar, or a factor may supply an array of levels.

#### Root parameters

| Parameter | Type and allowed values | Meaning |
| --- | --- | --- |
| `schema_version` | Integer; exactly `10` | Selects this protocol format. Other versions reject the protocol before further validation. |
| `subject_number_digit_count` | Integer from `1` through `12` | Required number of digits in the participant identifier. The result preserves leading zeroes. |
| `instructions` | Nonempty string with no leading or trailing whitespace | Text shown before the experiment. `<NUMBEROFTRIALS>` becomes the resolved trial count, `<GRIDSIZE>` becomes the resolved grid size or sizes, and `<TIMER_SECONDS>` becomes the timed-task duration or `unlimited`. |
| `debriefing_title` | Nonempty string with no leading or trailing whitespace | Heading displayed when the experiment finishes. |
| `debriefing` | Nonempty string with no leading or trailing whitespace | Final message. `<NUMBER_OF_TARGETS_FOUND>` becomes the final score. |
| `task_mode` | `"fixed_number_of_trials"` or `"loop_trials_<positive integer>_seconds"` | Runs the resolved schedule once, or repeatedly for the canonical positive integer duration. Example: `"loop_trials_300_seconds"`. |
| `sounds` | Object; required | Defines all six experiment-wide sound effects described below. |
| `input` | Object; required | Defines experiment-wide keyboard and speech controls. It cannot vary by condition. |
| `master_condition_template` | Object; required | Supplies one scalar value for every stimulus parameter. It may not contain `scheduling`, `factors`, or factor arrays. |
| `conditions` | Nonempty array of condition objects | Defines scheduling, scalar overrides, and experimental factors. |

The protocol filename must have a `.json` extension, must not begin with an underscore, and supplies the protocol name recorded in results. Unknown JSON keys at every documented level reject the protocol.

#### Sound parameters

Every sound object requires both child parameters: `sounds.<name>.file` is a nonempty bundled-audio filename with no surrounding whitespace, and `sounds.<name>.volume` is a finite number from `0.0` through `1.0`.

| Sound object | When it is used |
| --- | --- |
| `sounds.reveal` | Plays when the masked grid reveals its digits. |
| `sounds.stop_timer` | Plays when the stop command pauses the search timer. |
| `sounds.correct` | Plays after a correct crossing response. |
| `sounds.wrong` | Plays after an incorrect crossing response. |
| `sounds.timer` | Supplies the active search/countdown sound. |
| `sounds.final` | Plays when the experiment ends. |

#### Input parameters

| Parameter | Type and allowed values | Meaning |
| --- | --- | --- |
| `input.start_digits` | `"keyboard"` or `"speech"` | Input method for submitting the displayed target number and revealing the grid. |
| `input.stop_command` | `"keyboard_space"` or `"speech_stop"` | Method used to stop the timer after finding the target. |
| `input.cross_digits` | `"keyboard"` or `"speech"` | Input method for the perpendicular crossing response. |
| `input.speech.aliases` | Object with exactly the keys `"0"` through `"9"` | Each key maps to a nonempty array of spoken aliases for that digit. An alias is one letters-only word after trimming and lowercasing. Aliases must be unique within a digit and cannot belong to two digits. |
| `input.speech.max_interdigit_pause_seconds` | Finite number greater than `0` | Maximum accepted speech-segment pause between consecutive recognized digits in one three-digit response. |

The `speech` object and its complete aliases table are required even when all three input modes use the keyboard. If a condition requires keyboard input but no keyboard is connected, the participant may continue with the app's all-speech replacement; that replacement is recorded in the result file.

#### Condition structure and scheduling

| Parameter | Type and allowed values | Meaning |
| --- | --- | --- |
| `scheduling` | Object; required in every source condition | Contains only `repeats` and `block_nr`. It is forbidden in the master and in factors. |
| `scheduling.repeats` | Integer from `0` through `10000`, or a scheduling array of such integers | Number of trials made from each resolved condition. Zero skips that schedule entry. At least one entry in the complete protocol must produce a trial. |
| `scheduling.block_nr` | Integer at least `1`, or a scheduling array of such integers | Assigns trials to ordered blocks. Instantiated blocks across the complete protocol must begin at 1 and be consecutive without gaps. |
| `factors` | Optional nonempty array of factor objects | Each object is one independent factor. Its arrays define parallel levels; separate factor objects are crossed. |

Within `scheduling`, arrays must share the maximum scheduling length or have length 1; scalars and length-one arrays broadcast. The resolved experiment may contain at most 10,000 trials. Blocks run in ascending order and trials are randomized within each block.

Inside one factor, all non-structural arrays must share the factor's maximum length or have length 1. Scalars and length-one arrays broadcast. Different factors may modify different leaves of the same section—for example, `fov.eye` in one and `fov.width_degrees` in another—but two factors may not modify the same final parameter.

#### Condition-wide parameters

| Parameter | Type and allowed values | Meaning |
| --- | --- | --- |
| `random_seed` | `"shuffle"` or an unsigned 64-bit integer | Controls seeded target and grid generation. `"shuffle"` gives every presentation a fresh seed, including loop-mode revisits; a fixed integer is reused. Inside a factor, an array may mix both forms as factor levels. |
| `passthrough_dimming` | Finite number from `0.0` through `1.0` | Dims passthrough during trials. `0` preserves passthrough and `1` applies maximum dimming/black. Dimming is off outside trials. |

#### `digits` parameters

| Parameter | Type and allowed values | Meaning |
| --- | --- | --- |
| `digits.height_degrees` | Finite number greater than `0` | Visual height of grid digits and the displayed target digits. It also participates in target-heading clearance validation. |
| `digits.font_name` | Nonempty installed font name | Font used for the target and grid digits. The font must exist on the device during protocol preflight. |
| `digits.rgb` | RGB | Normal target and grid-digit color. Correct/wrong highlighting changes tile backgrounds, not this digit color. |
| `digits.random_method` | `"flat_distribution"` | Grid filler-digit generation method. This is currently the only accepted method. |
| `digits.highlight_correct_rgb` | RGB or `"disabled"` | Tile-background color used for a correct response. `"disabled"` omits correct highlighting while retaining the sound. |
| `digits.highlight_wrong_rgb` | RGB or `"disabled"` | Tile-background color used for an incorrect response. `"disabled"` omits wrong highlighting while retaining the sound. |
| `digits.post_stop_visibility_seconds` | Finite number at least `0` | Time the revealed grid remains visible after the stop command before returning to the masking character. |
| `digits.masking_character` | Exactly one non-newline character | Character displayed in every tile while digits are masked. |

#### `annotation` parameters

| Parameter | Type and allowed values | Meaning |
| --- | --- | --- |
| `annotation.height_degrees` | Finite number greater than `0` | Visual height of annotation text above the grid. It participates in heading-clearance validation. |
| `annotation.font_name` | Nonempty installed font name | Font used for annotation text; it must exist on the device during preflight. |
| `annotation.font_rgb` | RGB | Annotation text color. |

#### `timer_bar` parameters

| Parameter | Type and allowed values | Meaning |
| --- | --- | --- |
| `timer_bar.fill_rgb` | RGB | Color of the shrinking active timer fill. |
| `timer_bar.height_degrees` | Finite number greater than `0` | Height of the active timer fill. |
| `timer_bar.corner_radius_degrees` | Finite number at least `0`; at most half `height_degrees` | Corner radius of the full timer fill. Its moving right edge becomes straight as the fill is cropped. |
| `timer_bar.back_rgb` | RGB | Color of the stationary timer background. |
| `timer_bar.back_height_degrees` | Finite number greater than `0` | Height of the timer background; it must fit in the available space below the centered grid. |
| `timer_bar.back_corner_radius_degrees` | Finite number at least `0`; at most half `back_height_degrees` | Corner radius of the stationary timer background. |

#### `tiles` parameters

| Parameter | Type and allowed values | Meaning |
| --- | --- | --- |
| `tiles.width_degrees` | Finite number greater than `0` | Width of each tile. |
| `tiles.height_degrees` | Finite number greater than `0` | Height of each tile. |
| `tiles.gutter_degrees` | Finite number at least `0`; less than both tile dimensions | Gap between neighboring tiles. |
| `tiles.corner_radius_degrees` | Finite number at least `0`; diameter strictly less than both tile dimensions | Tile-corner radius. |
| `tiles.fill_rgb` | RGB | Normal tile-background color. |
| `tiles.gutter_rgb` | RGB | Color rendered between tiles. |
| `tiles.number_horizontal` | Integer from `4` through `254` | Number of tile columns. |
| `tiles.number_vertical` | Integer from `4` through `254` | Number of tile rows. |

#### `surround` parameters

| Parameter | Type and allowed values | Meaning |
| --- | --- | --- |
| `surround.fill_rgb` | RGB | Background color filling the FOV outside the inner grid area. |
| `surround.inner_margin_rgb` | RGB | Color of the margin surrounding the tile grid. |
| `surround.inner_margin_degrees` | Finite number at least `0` | Margin added on every side of the tile grid. |
| `surround.inner_corner_radius_degrees` | Finite number at least `0` | Inner-grid surround radius; its diameter may not exceed the smaller computed grid dimension. |
| `surround.outer_corner_radius_degrees` | Finite number at least `0` | Outer-FOV radius; its diameter may not exceed the smaller FOV dimension. |

#### `fov` parameters

| Parameter | Type and allowed values | Meaning |
| --- | --- | --- |
| `fov.eye` | `"left"`, `"right"`, or `"both"` | Eye or eyes receiving the stimulus. |
| `fov.mode` | `"video_passthrough"` or `"optical_see_through_simulation"` | Selects the display-compositing model described below. |
| `fov.peak_opacity` | Finite number from `0.0` through `1.0` | Maximum stimulus opacity used by the selected compositing model. |
| `fov.width_degrees` | Finite number greater than `0` and less than `180` | Base FOV width before optional zoom scaling. |
| `fov.height_degrees` | Finite number greater than `0` and less than `180` | Base FOV height before optional zoom scaling. It must leave sufficient space above and below the centered tile grid. |
| `fov.zoomed_width_degrees` | `"disabled"` or a finite nonzero number with magnitude less than `180` | Final angular width. A negative value mirrors the texture horizontally. `"disabled"` tracks the resolved base width for a scale factor of one. |
| `fov.zoomed_height_degrees` | `"disabled"` or a finite nonzero number with magnitude less than `180` | Final angular height. A negative value mirrors the texture vertically. `"disabled"` tracks the resolved base height for a scale factor of one. |
| `fov.horizontal_offset_degrees` | Any finite number | Horizontal stimulus-center offset. It does not participate in zoom-scale calculation. |
| `fov.vertical_offset_degrees` | Any finite number | Vertical stimulus-center offset. It does not participate in zoom-scale calculation. |
| `fov.distance_meters` | Finite number greater than `0` | Virtual presentation distance in meters. |

#### Combined geometry requirements

The resolved grid dimensions are:

```text
grid width  = tile width  × columns + gutter × (columns - 1) + 2 × inner margin
grid height = tile height × rows    + gutter × (rows - 1)    + 2 × inner margin
```

The grid width and height must fit inside `fov.width_degrees` and `fov.height_degrees`. Because the grid is centered, the free space above it must be at least `1.5 × max(digits.height_degrees, annotation.height_degrees)`, and the free space below it must fit `timer_bar.back_height_degrees`. The surround and corner-radius limits listed above are checked after resolving every factor combination, so one invalid level rejects the complete protocol.

The required root `input` section independently configures `start_digits`, `stop_command`, and `cross_digits`. The digit fields accept only `keyboard` or `speech`; `stop_command` accepts only `keyboard_space` or `speech_stop`. Keyboard digit input is intentionally invisible: digits append to a three-character buffer, Delete/Backspace removes its last digit, and Enter submits only when exactly three digits are buffered. Auto-repeat key-down callbacks are ignored until the physical key is released, so holding a key produces one input and one log event. Space or the standalone spoken word “stop” records `stop_signal_start_ms` and pauses the countdown. `digits.masking_character` supplies the single character used while the grid is hidden. After either stop command, the grid returns to that mask after `digits.post_stop_visibility_seconds`, measured from the instant the global countdown is paused. The first crossing code submitted afterward is final: it records `answer_correct` from `cross_digits`, plays the matching feedback sound, and advances without a retry. Feedback colors apply to the five solution tile backgrounds while their digits retain the normal font and RGB. Both `digits.highlight_correct_rgb` and `digits.highlight_wrong_rgb` accept either an RGB array or `"disabled"`; disabling either one omits that answer highlight and its texture. When all three trial inputs use the keyboard, speech recognition is stopped for the trial phases.

The experiment-wide `sounds` section configures `reveal`, `stop_timer`, `correct`, `wrong`, `timer`, and `final`, each with a bundled filename and volume from `0` through `1`. The reveal sound plays when the masked grid changes from the configured masking character to digits. The timer sound and bar run only during active search time and pause between trials; `stop_timer` plays when the configured stop command pauses them.

`input.speech.max_interdigit_pause_seconds` is the longest permitted pause between spoken digits in a three-digit trial response. The app measures each gap from the previous digit's recognized speech-segment end to the next digit's segment start, not from speech-recognition callback timing. A later digit starts a new attempt. Speech settings are root-level and cannot vary by condition.

Every condition requires `scheduling.repeats >= 0` and `scheduling.block_nr >= 1`. After zero-repeat entries are skipped, instantiated blocks must start at 1 and be consecutive without gaps. Blocks run in ascending order, and their trials are randomized within each block. Fixed-trial mode runs that schedule once. Loop-trials mode cycles the scheduled order until its deadline. A trial configured with `"shuffle"` receives a fresh random seed every time it is presented, including when loop-trials mode revisits it; fixed seeds are reused on subsequent passes. Trial names (`trial1`, `trial2`, …) remain unique when loop-trials mode revisits a source condition.

The entire configuration and schedule are preflighted at app launch. Validation rejects malformed or unknown keys, incomplete master parameters, missing scheduling fields, empty or mismatched factor arrays, invalid repeats or seed values, unavailable digit or annotation fonts, and invalid geometry, colors, or speech aliases. Both `tiles.number_horizontal` and `tiles.number_vertical` must be at least 4. If preflight fails, the participant card reports the configuration error.

Grid generation happens when each trial is about to run. The target is drawn first from that trial's seeded random-number generator. Candidate grids are then generated until both the target and its perpendicular response occur exactly once across all horizontal and vertical three-digit sequences. A rejected candidate advances the same deterministic random-number stream; it does not invalidate or abort the experiment.

## Run on Apple Vision Pro

1. Open `SmartFOV123.xcodeproj` in Xcode.
2. In **Signing & Capabilities**, select your Personal Team.
3. Pair the headset, enable Developer Mode, and select it as the run destination.
4. Build and run.
5. Verify the target-entry, stop-command, and crossing-entry methods selected by the protocol, and confirm that a correct crossing number advances automatically.

The app targets visionOS 26.0 or later. Speech recognition uses Apple's Speech framework and prefers on-device recognition when the active recognizer supports it.

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
    "input": {
      "start_digits": "speech",
      "stop_command": "speech_stop",
      "cross_digits": "speech",
      "speech": { "aliases": { "...": "all digits 0 through 9" }, "max_interdigit_pause_seconds": 1.0 }
    },
    "forced_voice_input": true,
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
        "countdown": {
          "bar": { "...": "complete resolved countdown-bar parameters" },
          "stopwatch_volume": 0.25,
          "final_gong_volume": 0.5
        },
        "tiles": { "...": "complete resolved tile parameters" },
        "surround": { "...": "complete resolved surround parameters" },
        "fov": { "...": "complete resolved FOV parameters" },
      },
      "seeded_stimulus": {
        "target_number": 512,
        "target_orientation": "leftright",
        "response_number": 613,
        "grid": [[4, 5, 7, 9], [6, 4, 6, 8], [2, 5, 1, 2], [8, 0, 3, 4]]
      },
      "results": {
        "absolute_trial_start_ms": 1204,
        "digit_reveal_ms": 3635,
        "timer_start_ms": 3635,
        "stop_signal_start_ms": 11547,
        "timer_stop_ms": 11799,
        "answer_correct": true,
        "speech": [
          {"stop": {"recognized_ms": 11798}},
          {"613": {"recognized_ms": 12401}}
        ],
        "keyboard": [
          {"1": {"start_ms": 3613}},
          {"enter": {"start_ms": 3686}}
        ]
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

The `experiment` block records the application, configured protocol, confirmed participant number, and local experiment-start date and time in ISO 8601-compatible forms. Loop-trials files also record `task_mode`; all files record the resolved root `input` configuration. If a selected protocol requires a keyboard but none is connected, the participant can speak “Continue with voice”; the app replaces the complete input configuration with its all-speech equivalent before trials begin and records `forced_voice_input: true` (otherwise `false`). The participant number is a string so leading zeroes are preserved. Each trial has its unique name and a complete `definition` containing the source condition's 1-based `condition_nr`, concrete block and actual random seed, and every resolved parameter section. `seeded_stimulus` records the generated target, expected response, and grid. `results.absolute_trial_start_ms` records the monotonic milliseconds since app launch when the prepared masked-grid texture is activated for that trial, before trial input begins. Every other time in that trial's `results` block is measured in milliseconds relative to that trial start, so events occur at zero or later. `timer_start_ms` records entry into the timed search phase, while `timer_stop_ms` records when the app pauses the timer. For speech stops, the difference between `stop_signal_start_ms` and `timer_stop_ms` includes speech recognition and command-processing latency. Each recognized utterance is stored as one speech event whose `recognized_ms` is the time its transcription callback reached the app; digit aliases are normalized, so a spoken three-digit response is stored as a value such as `613`. Apple Speech cannot log audio it never recognizes. Session-summary timing remains session-level.

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
