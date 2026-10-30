# TmanVibez for iPhone

TmanVibez is a local-first SwiftUI iPhone app starter for managing an offline audio and video library.

## Included

- Import individual media files from the iOS Files picker
- Choose a music folder and copy its supported audio tracks into the app library
- Re-select the folder later to add new tracks and refresh changed tracks
- Search the whole library for missing synced or plain lyrics
- Cache selected lyrics with the local track for offline viewing
- Play imported and downloaded media with shuffle, repeat one/all, next/previous track, audio-only queues, background audio, and lock-screen controls
- Download a direct HTTPS audio/video file when its source permits downloads

## iPhone access and format limits

iOS does not allow apps to silently scan all device storage. The user must select a folder in Files or import files explicitly. A folder sync copies accessible audio files into TmanVibez; the user can choose the folder again later to scan for changes.

The first version targets common formats supported by Apple's media frameworks: MP3, M4A/AAC, WAV, AIFF, CAF, FLAC, MP4, MOV, and M4V. No single player can play literally every codec. Broader formats such as OGG/Opus/APE need an additional decoder framework and license review.

## Direct download limits

Downloads are limited to direct HTTPS links that return a supported single media file. YouTube links are rejected; the app does not download or extract YouTube audio or video. Use YouTube's official offline feature when available. Other files must be ones you own or are authorized to save. The app does not bypass DRM, paywalls, or download restrictions. Apple Music and Spotify subscription downloads stay in their respective apps.

## Lyrics

Bulk lyric lookup uses LRCLIB's public search API. Requests are sent one at a time with a short pause. Track title and artist are sent to find matches; selected lyrics are stored in TmanVibez's local library. Availability and matching accuracy vary. Lyrics are cached in the app library rather than written into the original audio files.

## Open and run

1. Open TmanVibez.xcodeproj in Xcode on a Mac.
2. Select the TmanVibez target and choose your Apple development team under Signing & Capabilities.
3. Change the bundle identifier if needed.
4. Run on an iPhone running iOS 17 or later.

This workspace contains source only. It does not include an iOS build environment, signed IPA, or TestFlight upload.

## Build, sideload, and test with Codemagic

The repository includes two Codemagic workflows. Both use the App Store Connect API key integration named `codemagic`.

- `ios-adhoc` creates an Ad Hoc IPA for registered iPhones.
- `ios-testflight` signs with App Store distribution and uploads the build to TestFlight. It does not submit the app for public App Store release.

For the first TestFlight upload, create the TmanVibez app record in App Store Connect using bundle ID `com.wiantribe.tmanvibez`. Codemagic also needs an App Store provisioning profile for that bundle ID. The current project version is 1.0.3 (build 4); increase the build number for each later upload.

Apple signing requires an Apple Developer Program membership. Keep the API key and its private file inside Codemagic; do not put them in this repository. Ad Hoc IPAs must be installed using a supported iOS distribution method; they cannot be installed by tapping them in Files.

## Name and domain check

An exact-name search for `TmanVibez` on October 30, 2026 found no matching app or domain. It did surface the similar artist name `Tml Vibez`, so check for potential brand confusion before public release. RDAP checks that day reported `tmanvibez.com` and `tmanvibez.ca` as likely available. This is not trademark clearance or a reservation; confirm at a registrar before buying.

## Version

1.0.3 (build 4)
