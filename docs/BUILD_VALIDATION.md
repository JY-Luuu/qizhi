# Qizhi 0.1.0 validation

Initial local validation: 2026-10-17, Apple Silicon (`arm64`), macOS.

## Passed

- Optimized release compilation of the app and core checker.
- Core checker: 22 passed, 0 failed.
- Native Messaging host: 5 passed, including real subprocess framing, inbox delivery and rejection of the upstream extension origin.
- Personal identity checker: Swift, Chrome public key / extension ID, JavaScript, Python host, bundle and storage identifiers agree.
- JavaScript syntax: popup and background scripts.
- Eight app checks: adaptive card layout, resume targets, idea capture, image routing, image editing, saved thumbnails, external drop and desktop drop routing.
- Chinese light and English dark sample screenshots, rendered from isolated synthetic data and visually inspected. No personal content is used in the documentation images.
- Release ZIP extraction to a temporary directory, followed by `codesign --verify --deep --strict`, plist validation and native ICNS decoding.

The local ARM64 ZIP is approximately 4.4 MB; the app's regular files total approximately 8.9 MB, before user captures and previews. Build caches are separate and are not distributed.

## Environment limits and manual checks

The local execution environment has no usable Metal rendering device. Interactive 3D Done Spike rendering and pointer interactions therefore remain a manual check on a normal macOS desktop. The original SceneKit implementation is retained, with the receipt wordmark changed to QIZHI.

DMG creation did not complete in the restricted local execution environment. The macOS GitHub Actions workflow also builds the DMG; its current result is available in the repository's Actions tab. The local ZIP is independently built and verified.

Real Screen Recording permission prompts, Chrome host installation, opening real Chrome / Obsidian documents, global shortcut behavior and real notifications remain manual integration checks. These actions were not triggered against the user's applications or data during fixture generation.

The app uses an ad hoc local signature and has not been Apple notarized.
