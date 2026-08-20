# ChatGPT project context

This directory is a local mirror of the ChatGPT project “SmartFOV123”.

- Treat every file under `sources/` as read-only reference material.
- Do not edit, rename, move, or delete synced project files.
- These files may be replaced the next time a task is created from this ChatGPT project.


## Project instructions

### Conservative visionOS verification

- For visionOS work, conserve Codex usage by avoiding Xcode builds, simulator
  runs, and automated test suites unless explicitly requested.
- Perform lightweight source and diff checks, then leave functional validation
  to the user on Apple Vision Pro.
- If compilation is especially important, explain why and ask before running it.

### Reverting experiments

- When rolling back an unsuccessful experiment, first consider restoring the
  affected files from the known-good Git commit instead of manually reversing
  each edit.
- Before restoring from Git, verify that the target diff contains only the
  experiment being discarded. Preserve any overlapping or unrelated user
  changes; use a manual rollback when a whole-file restore would remove them.

### Completion chime

- At the beginning of every new user prompt, immediately stop any completion
  chime that is running and cancel any completion chime that is waiting to
  start. Any new task, question, acknowledgement, or other prompt triggers this
  cleanup automatically.
- After completing a user prompt that took more than 12 seconds to work on,
  wait until one minute after the response has been sent, then start a repeating
  macOS system chime that sounds once every five seconds. If another prompt
  arrives during that one-minute delay, cancel the pending chime so it never
  starts.
- Keep the chime running only until the next user prompt arrives, then stop it
  immediately before handling that prompt. An explicit “stop the chime” also
  stops it immediately. A standalone “OK” stops it immediately without a
  response.
