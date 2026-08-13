# MobiWordFinderAVP

A configurable visionOS WordFinder experiment rendered binocularly over passthrough with Compositor Services and Metal.

The current feature-branch implementation loads `Config/experiment.json`, generates a deterministic letter grid, and presents it as a head-locked binocular stimulus at the configured visual-field position and distance. The participant searches for the configured target word, looks at its middle letter, and pinches to select that letter box.

On visionOS 26, every Metal-drawn box is registered as a tracking area. visionOS supplies its privacy-preserving automatic gaze highlight and reports the selected box identifier after a pinch; the app does not receive raw gaze or passive fixation data.

Use **Start trial** in the launcher to open the mixed immersive space. The launcher stays open so you can stop the trial reliably; move it aside if it blocks the grid. Closing the launcher also dismisses the immersive space. As a final safety measure, the immersive trial stops automatically after 30 seconds.

## Run on Apple Vision Pro

1. Open `MobiWordFinderAVP.xcodeproj` in Xcode.
2. In **Signing & Capabilities**, select your Personal Team.
3. Pair the headset, enable Developer Mode, and select it as the run destination.
4. Build and run.
5. Verify that the letter grid appears binocularly and that looking at a box produces the system hover effect before a pinch selects it.

The app targets visionOS 2.0 or later for rendering; gaze highlighting and tracked box selection require visionOS 26 or later.
