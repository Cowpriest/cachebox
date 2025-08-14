
# MediaKit Migration for CacheBox

This patch replaces `video_player`/Chewie with **media_kit** for video playback (in-app, wide codec support including many AVI files).

## pubspec.yaml

Add these dependencies (remove Chewie if you no longer need it):

```yaml
dependencies:
  media_kit: ^latest
  media_kit_video: ^latest

# Platform-specific native libs (pick the platforms you build for)
# Android:
  media_kit_libs_android_video: ^latest
# iOS:
  media_kit_libs_ios_video: ^latest
# macOS:
  media_kit_libs_macos_video: ^latest
# Windows:
  media_kit_libs_windows_video: ^latest
# Linux (if packaging with bundled mpv):
  media_kit_libs_linux: ^latest  # or ensure system libmpv is available
```

> You can keep `video_player` for other features if you want, but it's not required for video anymore.

## main.dart

Make sure you initialize MediaKit **before** runApp:

```dart
import 'package:media_kit/media_kit.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MyApp());
}
```

## Usage

All video file extensions now route to `VideoPlayerScreen` (media_kit). Supported examples: `.mp4, .mkv, .webm, .avi, .mpg, .mpeg, .wmv, .mov, .flv, .ts, .m4v`.

## Desktop Notes

- **Windows/macOS/Linux**: include the appropriate `media_kit_libs_*` package. On Linux you may choose to depend on system `libmpv` or bundle via `media_kit_libs_linux`.
- If you embed this in a **Flutter desktop** build, test a few AVI samples to confirm codecs are linked as expected.

## Nice-to-haves (optional)

- Add gesture-based controls (double-tap seek), subtitle loading, and remember last playback position per file.
- If you have network streams that require headers/cookies, open with `Media(widget.videoUrl, httpHeaders: {...})`.
