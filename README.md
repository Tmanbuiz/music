# TmanVibez for iPhone

TmanVibez is a local-first SwiftUI iPhone app starter for managing an offline audio and video library.

## Included

- Import individual media files from the iOS Files picker
- Choose a music folder and copy its supported audio tracks into the app library
- Re-select the folder later to add new tracks and refresh changed tracks
- Search the whole library for missing synced or plain lyrics
- Cache selected lyrics with the local track for offline viewing
- Play imported and downloaded media from the app
- Download a direct HTTPS audio/video file when its source permits downloads

## iPhone access and format limits

iOS does not allow apps to silently scan all device storage. The user must select a folder in Files or import files explicitly. A folder sync copies accessible audio files into TmanVibez; the user can choose the folder again later to scan for changes.

The first version targets common formats supported by Apple's media frameworks: MP3, M4A/AAC, WAV, AIFF, CAF, FLAC, MP4, MOV, and M4V. No single player can play literally every codec. Broader formats such as OGG/Opus/APE need an additional decoder framework and license review.

## Direct download limits

Downloads are limited to direct HTTPS links that return a supported single media file. The app does not extract media from streaming pages, bypass DRM, defeat paywalls, or download protected streams. Use only files you own or are authorized to save. Apple Music and Spotify subscription downloads stay in their respective apps.

## Lyrics

Bulk lyric lookup uses LRCLIB's public search API. Requests are sent one at a time with a short pause. Track title and artist are sent to find matches; selected lyrics are stored in TmanVibez's local library. Availability and matching accuracy vary. Lyrics are cached in the app library rather than written into the original audio files.

## Open and run

1. Open TmanVibez.xcodeproj in Xcode on a Mac.
2. Select the TmanVibez target and choose your Apple development team under Signing & Capabilities.
3. Change the bundle identifier if needed.
4. Run on an iPhone running iOS 17 or later.

This workspace contains source only. It does not include an iOS build environment, signed IPA, or TestFlight upload.

## Build and sideload with Codemagic

The repository includes a `codemagic.yaml` workflow named `ios-adhoc`. It references an App Store Connect API key named `codemagic` in Codemagic. If your Codemagic account uses a different key name, change `integrations.app_store_connect` in the YAML to match it. Register the iPhone's device ID with Apple and use an Ad Hoc provisioning profile for `com.wiantribe.tmanvibez`. Then run the workflow; Codemagic will provide the signed `.ipa` as a build artifact.

Apple signing requires an Apple Developer Program membership. Keep the API key and its private file inside Codemagic; do not put them in this repository. The `.ipa` must be installed using a supported iOS distribution method; it cannot be installed by tapping it in Files.

## Name and domain check

An exact-name search for `TmanVibez` on October 30, 2026 found no matching app or domain. It did surface the similar artist name `Tml Vibez`, so check for potential brand confusion before public release. RDAP checks that day reported `tmanvibez.com` and `tmanvibez.ca` as likely available. This is not trademark clearance or a reservation; confirm at a registrar before buying.

## Version

1.0.1 (build 2)
