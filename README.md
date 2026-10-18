# mariah_carey_rhythm

A Flutter Android game based on the Mariah Carey drum trend: the song plays, you tap the drum, and the app shows how close your tap was to the beat drop.

## How to play
1. Press **PLAY**. The button fades out, the drum fades in, and the song starts.
2. Tap anywhere to hit the drum. Every tap plays a "tum" sound.
3. Your **first tap** starts the stopwatch at the top of the screen. Later taps only make sound.
4. At the beat drop the stopwatch freezes and shows how early you were.
5. If you haven't tapped by the drop, the stopwatch counts up **in red** from the drop (`+0.123`). Your first tap stops it and scores as late.
6. If the song ends and you never tapped, you get **Missed!**.

The result screen shows a rating and a **Play again** button. Pressing Back during a round returns to the Play button.

| Rating | How close to the drop |
|---|---|
| PERFECT! | under 50 ms |
| Great | under 150 ms |
| Good | under 400 ms |
| Off beat | 400 ms or more |

## Assets
The names must match `lib/game_config.dart`:

- `assets/images/drum.png`: the drum picture (white background, to match the game screen)
- `assets/audio/song.mp3`: the song clip
- `assets/audio/tum.wav`: the drum hit sound

## Configuration
Everything you'd change is in `lib/game_config.dart`:

- `dropTime`: time from the start of `song.mp3` to the beat drop. It's currently **11.400 s**. Analysing the current clip puts the drop's start at 11.39 s, so this value is accurate to within about 5 ms.
- `songAsset`, `tumAsset`, `drumImageAsset`: asset paths.

## Project layout
- `lib/main.dart`: app entry point. Locks the app to portrait and uses full-screen mode.
- `lib/screens/game_screen.dart`: the only screen. Handles the Play button, drum, stopwatch, scoring and results.
- `lib/widgets/start_view.dart`: the Play button view.
- `lib/game_config.dart`: assets and drop time.

## How the timing works
- The song and drum sound load in the background while the Play button is showing.
- The game's clock (a `Stopwatch`) starts when the audio player reports the song as playing. Loading time is therefore excluded.
- The drum sound uses a low-latency `AudioPool`. It doesn't request audio focus, so it never pauses the song.

**Known limitation:** the clock starts when Android *starts* playback, not when the sound reaches your ears. Phone speakers add roughly 20–100 ms of delay, and Bluetooth earphones roughly 150–300 ms. On those, a tap that sounds exactly on the drop can score slightly late. The fix is to time rounds from the song's own playback position and add an adjustable offset.

## Build and run
```sh
flutter pub get
flutter run                 # on a connected phone or emulator
flutter build apk --release # build/app/outputs/flutter-apk/app-release.apk
```
- The release APK is signed with Flutter's debug key. That's fine for sideloading, but the Play Store needs your own signing key.
- Run `flutter build apk --split-per-abi` for smaller, per-CPU-type APKs.
- The emulator plays sound through whichever Windows audio device was the default when it started. If you switch to earphones, restart the emulator.
