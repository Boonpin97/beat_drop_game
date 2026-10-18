# Beat Drop

*Challenge your sense.* A party rhythm game based on the Mariah Carey drum trend: the song plays, everyone taps a drum, and whoever lands closest to the beat drop wins.

Play together in the browser (up to 12 players, one shared speaker), or practise solo. Built with Flutter (web and Android) and a small Dart WebSocket server.

## How a multiplayer round works
1. The host taps **Create room** and shares the 6-letter code or the invite link (`/r/<code>`). A room holds up to 12 players.
2. Everyone else taps **Join room** and enters the code, or opens the link.
3. The host chooses whether they're playing (**I'm playing too**) and taps **Start**. After a 3-2-1 countdown the song plays **from the host's phone only**, and everyone taps the drum on their own phone.
4. After your first tap, a timer counts up and freezes at the drop to show how early you were. If the drop passes before you tap, it counts up in red instead.
5. Shortly after the drop, every screen shows the ranked results.

Each player gets their own colour, used for their avatar and as the background of their drum screen.

### Scoring and ranking
| Rating | How close to the drop |
|---|---|
| PERFECT! | under 50 ms |
| Great | under 150 ms |
| Good | under 400 ms |
| Off beat | 400 ms or more |

Ranking: early (or exact) taps come first, closest to the drop first. Then late taps, least late first; **any late tap ranks below every early one**. Players who never tapped come last.

### Why it's fair
Taps are never judged by when they reach the server:

- Each phone keeps estimating the gap between its clock and the server's, using NTP-style ping/pong and trusting the fastest round trips (`packages/shared/lib/src/clock_sync.dart`).
- Each tap is stamped on that shared clock, from the pointer event's own timestamp, so a slow network doesn't change anyone's score.
- The host phone uses Web Audio to start the song at the agreed moment, then reports when sound actually left the speaker. Each score is `tap − (heard song start + drop time)`.
- The server rejects implausible timestamps: ones from the future, or older than the trip to the server could have taken.

The coloured dots in the lobby show each phone's connection quality. Use the host phone's own speaker: Bluetooth speakers add 150–300 ms that browsers often under-report. That shifts everyone's score equally, so the ranking stays fair but the numbers drift.

## Solo practice
**Practise solo** on the home screen plays the song on your own device. Your first tap starts the stopwatch, it freezes at the drop, and a late or missed tap is shown the same way as in multiplayer.

## Assets
The file names must match `lib/game_config.dart`:

- `assets/images/drum.png`: the drum (transparent background)
- `assets/images/logo.png`: the landing-page logo
- `assets/audio/tum.wav`: the drum hit sound
- `assets/audio/song.mp3`: the song clip. **Not included in this repo.** It's a copyrighted recording, so add your own clip at this path before building.

After adding a clip, set `songDropTime` in `packages/shared/lib/src/protocol.dart` to the time of its beat drop. It lives in the shared package because the server scores against it too.

## Project layout
- `lib/main.dart`: app entry point. Reads an invite code from `/r/<code>` links.
- `lib/theme.dart`: colours, the 12-colour player palette and the app theme.
- `lib/screens/landing_screen.dart`: create room, join room, practise solo.
- `lib/screens/room_screen.dart`: lobby, multiplayer round, live timer and results.
- `lib/screens/game_screen.dart`: the solo round.
- `lib/net/room_client.dart`: WebSocket client, clock sync and reconnects.
- `lib/platform/`: the clock, sound and wake lock. Web Audio in the browser, `audioplayers` on native.
- `lib/widgets/`: the drum pad and the solo Play button.
- `lib/game_config.dart`: asset paths, drop time, server URL.
- `packages/shared/`: protocol, clock-sync estimator and scoring, used by both the app and the server.
- `server/`: the Dart WebSocket room server. Rooms live in memory.

## Run locally
```sh
cd server && dart run bin/server.dart    # ws://localhost:8080/ws
flutter run -d chrome                    # in another terminal
```
Open several browser tabs to play as different people. The app connects to `ws://localhost:8080/ws` unless you pass `--dart-define=SERVER_URL=...`.

To test with phones on the same Wi-Fi, build with `--dart-define=SERVER_URL=ws://<your-PC-IP>:8080/ws` and serve `build/web`. Some browser features (wake lock, clipboard) need HTTPS, so a deployed copy is the real test.

Android: `flutter run` on a device, or `flutter build apk --release`. Multiplayer is designed for the browser; the Android build uses `audioplayers`, which can't schedule sound as precisely as Web Audio.

## Deploy your own copy
The repo doesn't name a cloud project. Use your own Google Cloud / Firebase project; it needs billing enabled for Cloud Run.

**1. Room server on Cloud Run.** Run this from the repo root, because the Docker build needs `packages/shared`:
```sh
gcloud run deploy beatdrop-room --source . \
  --project <your-project-id> --region <region> \
  --allow-unauthenticated --timeout 3600 --session-affinity \
  --min-instances 0 --max-instances 1
```
Rooms live in memory, so keep `--max-instances 1`; one instance easily handles many 12-player rooms. Open connections keep it alive during a game. After a quiet spell, the first room waits a second or two for a cold start; `--min-instances 1` avoids that but costs money while idle.

**2. Web app on Firebase Hosting.** The command above prints a service URL like `https://beatdrop-room-xxxx.<region>.run.app`. Build against it with `wss://` and `/ws`:
```sh
firebase use --add    # once: pick your project; writes .firebaserc, which is git-ignored
flutter build web --release --dart-define=SERVER_URL=wss://<your-service-host>/ws
firebase deploy --only hosting
```
`firebase.json` serves `build/web` and rewrites every path to `index.html`, so `/r/<code>` invite links work.

## Tests
```sh
cd packages/shared && dart test   # clock sync, scoring and ranking, room codes
cd server && dart test            # room rules, colours, tap clamping, reconnects
flutter test
```
