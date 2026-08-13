# Headlocked Eye Test

A minimal visionOS hardware test for independent left- and right-eye rendering over passthrough.

The renderer projects one shared head-locked square 1.5 metres dead ahead into each eye's calibrated view. The square repeats this three-second cycle:

1. Left eye red and right eye green for one second.
2. Left eye red and right eye transparent for one second.
3. Left eye transparent and right eye green for one second.

Use **Start test** in the launcher to open the mixed immersive space. The launcher stays open so you can stop the test reliably; move it aside if it blocks the square. Closing the launcher also dismisses the immersive space. As a final safety measure, the immersive test stops automatically after 30 seconds.

## Run on Apple Vision Pro

1. Open `HeadlockedEyeTest.xcodeproj` in Xcode.
2. In **Signing & Capabilities**, select your Personal Team.
3. Pair the headset, enable Developer Mode, and select it as the run destination.
4. Build and run.
5. Close one eye at a time to verify the three phases and confirm that the transparent eye sees normal passthrough.

The app targets visionOS 2.0 or later and uses Compositor Services with a mixed immersive space.
