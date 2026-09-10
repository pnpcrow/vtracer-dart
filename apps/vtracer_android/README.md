# VTracer for Android

Raster-to-vector (SVG) conversion on Android, built on the same pure Dart
pipeline (`packages/vtracer` + `packages/visioncortex`) as the desktop/web
app in `apps/vtracer_app`.

## Getting images in — no storage permission

- **Gallery picker** — the in-app "Pick from gallery" button goes through
  the system **photo picker** (`image_picker`): the Android 13+ platform
  photo picker, with the Google-Play-services backport / a system picker
  intent on older versions. The app never reads storage on its own.
- **Share / Open-with intents** — the manifest declares `ACTION_VIEW` and
  `ACTION_SEND` handlers for `image/*`, so VTracer shows up in the system
  share sheet and in file managers' "open with" choosers. The host
  activity (`MainActivity`) copies the shared bytes over a method channel
  (buffered for cold starts via `getInitialImage`, pushed for warm starts
  via `onImageIntent`); loading an image auto-traces once.

## Saving — permission-free Downloads

"Save SVG" writes into the **public Downloads directory** through
`MediaStore.Downloads` (relative path `Download/`). On the supported API
range this requires **no permission at all**; MediaStore uniquifies the
file name on collision (`… (1).svg`). The saved name is derived from the
source image (`photo.jpg` → `photo_YYYYMMDD-HHMMSS-traced.svg`).

Because `MediaStore.Downloads` starts at API 29, **minSdk is 29
(Android 10)** — that is what makes the zero-permission design possible;
the app requests no runtime permissions anywhere. The merged release
manifest carries only the toolchain-generated, signature-scoped
`DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`.

## UI

Mobile-first port of the webapp interface: the trace options (B/W vs
color, cutout vs stacked, filter speckle, color precision, gradient step,
pixel/polygon/spline, corner threshold, segment length, splice threshold)
live in a bottom sheet (`tune` icon). Like the desktop app, conversion is
too heavy to re-run live on every slider drag — changes mark the state
dirty and are applied with **Apply**; loading an image auto-applies once.
The canvas shows a rasterized preview over a transparency checkerboard,
plus a compact info strip (input format/size, output shapes/layers/bytes/
render time). Theme (light/dark/system) and language (English/한국어/
system) preferences persist via `shared_preferences`.

Conversion runs on a background-isolate worker (`package:vtracer/
worker.dart`), keeping the UI isolate free — including the progress
updates, which surface as a slim progress bar with the pipeline phase.

## Build & test

```bash
cd apps/vtracer_android

flutter pub get           # from the repo root: dart pub get (workspace)
flutter analyze
flutter test

flutter build apk --release   # build/app/outputs/flutter-apk/app-release.apk
flutter run                   # on a connected device/emulator
```

To exercise the share intent from the command line:

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb shell am start -a android.intent.action.SEND -t image/jpeg \
  --eu android.intent.extra.STREAM content://…   # or ACTION_VIEW with -d <uri>
```
