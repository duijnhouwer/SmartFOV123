# MobiWordFinderAVP — Roadmap

## Purpose

Develop a reproducible visionOS platform for presenting independently controlled stimuli to the left and right eyes. The immediate prototype validates per-eye rendering; the eventual application will support configurable stimuli, controlled surroundings, experimental timing, and participant workflows.

## Current verified behavior

Verified on a physical Apple Vision Pro:

- The app opens a mixed immersive space without trapping the participant.
- The launcher can start and stop the test.
- The immersive test stops automatically after 30 seconds as a safety measure.
- Compositor Services presents independently controlled imagery to both eyes.
- The left eye receives a red patch and the right eye receives a green patch.
- The patches can be independently enabled and disabled on a repeating schedule.
- Both patches are projections of one shared binocular target.
- The shared target is head-locked, straight ahead, and currently hardcoded at a vergence distance of 1.5 metres.
- The physical-device renderer supplies predicted device anchors and follows the required Metal residency and frame-submission lifecycle.

The present implementation is a diagnostic prototype, not yet an experimental or clinical instrument.

## Working decisions

### Stimulus geometry

- Left/right describes the receiving eye, not a spatial offset.
- Both eyes target the same perceived point in the visual field.
- The initial target remains hardcoded at the centre of the visual field and 1.5 metres away.
- Position and vergence distance will become configurable later.

### Visual surround

- Do not depend on the participant's selected visionOS system Environment.
- The final app should own the visual surround so sessions remain consistent across rooms and participants.
- Keep passthrough available as an explicit test condition.
- Treat the surround as part of the experimental stimulus and version it accordingly.

### Authorization and safety

- Never leave a participant without an obvious way to exit an immersive test.
- Preserve an automatic timeout during development.
- Surface renderer and tracking failures in the launcher instead of crashing or presenting an empty immersive scene.

### Configuration and provenance

- Keep the initial experiment definition in one bundled `experiment.json` file.
- Bundle referenced panoramas and synthetic-environment assets in the Xcode project.
- Rebuilding and reinstalling the development app is an acceptable way to deploy configuration and asset changes.
- Treat `experiment.json` as the authoritative description of stimulus geometry, environment, and trials.
- Save the exact experiment configuration and Git commit identifier with every result set.
- Do not rely on the current repository state alone to reconstruct a completed session.

## Phase 1 — Stabilize the rendering diagnostic

- [x] Configure a valid app bundle and device signing workflow.
- [x] Run on the visionOS simulator.
- [x] Run on a physical Apple Vision Pro.
- [x] Implement hardware Metal residency and frame synchronization.
- [x] Start ARKit world tracking before presenting compositor drawables.
- [x] Project a single binocular target through each calibrated eye view.
- [x] Verify monocular red and green presentation on hardware.
- [x] Verify fusion at a shared position 1.5 metres straight ahead.
- [ ] Confirm and document which calibrated view corresponds to the anatomical left and right eye.
- [ ] Add an unmistakable eye-identification mode with labels or distinct temporal signatures.
- [ ] Measure actual stimulus timing and dropped frames on hardware.
- [ ] Record renderer, visionOS, device, and app-version diagnostics in the launcher.
- [ ] Decide whether the 30-second development timeout remains configurable or is replaced by a session controller.

### Phase 1 acceptance criteria

- The test starts and stops repeatedly without relaunching or force-quitting the app.
- No Compositor Services client errors appear during a normal session.
- Each eye reliably receives the intended color and visibility sequence.
- Both monocular images fuse at the intended visual-field location and vergence distance.
- Frame timing remains stable for the required duration.

## Phase 2 — Configurable stimuli

- [ ] Add a bundled `experiment.json` resource to the Xcode project.
- [ ] Define a small, versioned JSON schema for the initial experiment format.
- [ ] Replace hardcoded stimulus parameters with a validated configuration model loaded from `experiment.json`.
- [ ] Display a human-readable configuration summary before starting a session.
- [ ] Reject invalid or unsupported configurations with actionable errors rather than silently substituting defaults.
- [ ] Decode and validate the complete experiment, including every trial, when the app launches; do not defer trial-specific decoding or validation until a session is underway.
- [ ] Prevent a session from starting unless all trials pass validation, so a configuration problem cannot terminate an experiment after valid trials have already been completed.
- [ ] Report all discoverable configuration problems together, with the JSON field path, supplied value, expected type or allowed values, and affected trial number where applicable.
- [ ] Show configuration errors in the launcher and mirror their full details to the Xcode console while keeping the app responsive.
- [ ] Configure horizontal and vertical position in visual-angle units.
- [ ] Configure vergence distance independently from visual-field position.
- [ ] Configure angular size rather than only physical size in metres.
- [ ] Configure shape, color, luminance, contrast, and opacity per eye.
- [ ] Support images, text, and WordFinder-specific content.
- [ ] Generate each WordFinder letter grid reproducibly from its configured random seed.
- [ ] Validate the completed grid horizontally and vertically to ensure the target word occurs only at its intentionally selected position and orientation; if an accidental occurrence exists, deterministically generate a new grid and check again.
- [ ] Add automated tests for accidental target-word detection, including overlapping occurrences and occurrences that share letters with the intended target.
- [ ] Configure independent onset, offset, duration, and repetition per eye.
- [ ] Add fixation marks and optional binocular alignment references.
- [ ] Add preview and configuration validation before entering immersion.
- [ ] Save and load named stimulus protocols.

### Initial `experiment.json` scope

- Stimulus width and height in degrees of visual angle.
- Horizontal and vertical position in degrees relative to straight ahead.
- Vergence distance in metres.
- Per-eye appearance and visibility.
- Environment type: passthrough, bundled panorama, stereoscopic panorama, or bundled synthetic scene.
- Bundled environment asset filename or scene identifier.
- Trial definitions, event timing, repetition, and ordering.
- A schema-version field so later app versions can migrate or reject old configurations explicitly.

### Open stimulus questions

- Which coordinate convention should the user interface expose: degrees, metres, or both?
- Should vergence distance be fixed per protocol or adjustable during a session?
- What color space and luminance calibration are required?
- How should optical inserts and participant calibration be recorded?
- What temporal precision and synchronization tolerance are scientifically acceptable?

## Phase 3 — Controlled visual environments

- [ ] Implement an app-owned world-locked surround behind the head-locked stimulus.
- [ ] Provide an explicit passthrough condition.
- [ ] Create a neutral controlled environment with documented visual properties.
- [ ] Evaluate monoscopic versus stereoscopic surrounds experimentally rather than assuming stereo is preferable.
- [ ] Support a versioned 360° panorama asset format if photographic environments are needed.
- [ ] Record the selected environment and asset version with every session.
- [ ] Validate head rotation, poles, horizon, seams, and stereo comfort on hardware.
- [ ] Establish asset licensing and redistribution requirements before adding third-party media.

### Environment candidates

1. Neutral synthetic surround
   - Low contrast and low spatial frequency.
   - Known scale, horizon, luminance, and depth cues.
   - Rendered in-house to avoid licensing and stitching uncertainty.

2. Monoscopic 360° panorama
   - Appropriate when the surround is intended to be visually distant.
   - Simpler and less prone to stereo stitching artifacts.

3. Stereoscopic 360° panorama
   - Use only when binocular depth in the environment is experimentally necessary.
   - Requires verified eye ordering, projection format, camera baseline, scale, stitching quality, comfort, and redistribution rights.

### Phase 3 acceptance criteria

- The selected surround is identical across testing locations and sessions.
- The surround remains world-locked during head motion.
- The stimulus remains head-locked and independently configurable.
- Switching between passthrough and controlled surroundings does not alter stimulus geometry or timing.
- The app records enough metadata to reproduce the environment exactly.

## Phase 4 — Experimental workflow

- [ ] Separate researcher controls from the participant display.
- [ ] Add participant identifiers that avoid unnecessary personal information.
- [ ] Add protocol selection, instructions, practice, test, pause, resume, and completion states.
- [ ] Prevent accidental configuration changes during an active trial.
- [ ] Add explicit emergency stop and session recovery behavior.
- [ ] Record stimulus events using a monotonic clock.
- [ ] Record participant responses and response latency.
- [ ] Write one uniquely named session directory per run in the app's Documents container.
- [ ] Save tabular trial results as `results.csv`.
- [ ] Copy the exact loaded `experiment.json` into the session directory.
- [ ] Save `metadata.json` with the Git commit, app version, build number, device model, visionOS version, UTC timestamps, environment identifier, and session status.
- [ ] Export structured session data with app, protocol, device, and environment versions.
- [ ] Define handling for interrupted, incomplete, or invalid trials.

### Proposed session output

```text
session-20260813T132500Z-P017/
├── results.csv
├── experiment.json
└── metadata.json
```

Use a unique UTC timestamp and a non-identifying participant code in the directory name. Never overwrite an existing session. Record both requested event timing and measured presentation timing where available.

### Development result transfer

- [ ] Add a Mac shell script that finds the connected Apple Vision Pro and pulls session directories with `xcrun devicectl`.
- [ ] Read from the app's private `Documents` directory using the `appDataContainer` domain and the app bundle identifier.
- [ ] Pull every unarchived session rather than depending on one fixed result filename.
- [ ] Refuse to overwrite an existing local result directory.
- [ ] Verify transfer completion before reporting success.
- [ ] Keep device-side results unless the user explicitly requests deletion or archival.
- [ ] Document that results should be pulled before deleting or reinstalling the development app because its private container may be removed.
- [ ] Add a visionOS Files/share-sheet export as a backup when command-line transfer is unavailable.
- [ ] Consider a Mac companion app only after the shell-script workflow becomes limiting.

Conceptual development command:

```sh
xcrun devicectl device copy from \
  --device "<connected Vision Pro>" \
  --domain-type appDataContainer \
  --domain-identifier "<app bundle identifier>" \
  --source "Documents/<session directory>" \
  --destination "<Mac results directory>"
```

Scripts should consume `devicectl`'s JSON output rather than parsing its human-readable terminal output.

## Phase 5 — Calibration and validation

- [ ] Define participant-specific binocular alignment calibration.
- [ ] Validate angular position and angular size against an external measurement method.
- [ ] Validate vergence disparity at each supported target distance.
- [ ] Validate color, luminance, contrast, and transparency on the physical display.
- [ ] Validate onset timing, duration, interocular synchronization, and frame drops.
- [ ] Test with supported optical inserts and relevant vision settings.
- [ ] Document environmental requirements such as headset fit, room lighting, and session duration.
- [ ] Establish repeatability and reproducibility tests before using the app for research conclusions.

## Phase 6 — Productization

- [ ] Replace the diagnostic launcher with the final application structure and naming.
- [ ] Add accessibility and localization where they do not compromise the experimental protocol.
- [ ] Add automated tests for configuration, schedules, state transitions, and data export.
- [ ] Add continuous integration builds for simulator and physical-device SDK targets.
- [ ] Define privacy, consent, data retention, and security requirements.
- [ ] Review whether intended claims trigger research ethics, institutional, clinical, or regulatory requirements.
- [ ] Prepare distribution, provisioning, and device-management workflows.

## Technical debt and project hygiene

- [ ] Review and either commit or remove the Xcode-generated shared scheme.
- [ ] Add source-level documentation for coordinate spaces and compositor lifecycle requirements.
- [ ] Replace remaining hardcoded diagnostic values with named constants before adding settings.
- [ ] Add structured logging with rate limiting for renderer failures.
- [ ] Add a small hardware test checklist to the repository.
- [ ] Embed the Git commit identifier during the Xcode build without requiring runtime access to Git.
- [ ] Mark builds produced from a dirty working tree so exported provenance is not misleading.
- [ ] Add JSON schema and example configuration validation to automated tests.
- [ ] Keep verified milestones in Git with informative commits and tags.

## Near-term priorities

1. Confirm anatomical eye assignment beyond subjective color observation.
2. Make repeated start/stop operation boringly reliable.
3. Measure timing on hardware.
4. Define the first bundled `experiment.json` schema.
5. Define session output and implement `results.csv`, saved configuration, and provenance metadata.
6. Prototype a neutral app-owned surround before selecting photographic assets.

## Non-goals for the current prototype

- Clinical diagnosis or treatment.
- Claims of calibrated luminance, color, geometry, or timing without measurement.
- Depending on undocumented visionOS system Environment behavior.
- Downloading arbitrary third-party panoramas at runtime.
- Building a full experimental user interface before the rendering and timing foundation is validated.
