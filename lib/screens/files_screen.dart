// lib/screens/files_screen.dart butts
import 'dart:convert';
import 'dart:io' show File, Directory;
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/widgets.dart' show AutomaticKeepAliveClientMixin;
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:http_parser/http_parser.dart';
import 'package:flutter/cupertino.dart';

import '../services/file_service.dart';
import '../services/resume_store.dart';
import '../services/file_model.dart';
import 'video_player_screen.dart';
import 'image_viewer_screen.dart';
import 'text_viewer_screen.dart';

enum FileAction { rename, details, delete }

bool _isDigit(int cu) => cu >= 0x30 && cu <= 0x39; // '0'..'9'

int _naturalCompare(String a, String b) {
  // Case-insensitive comparison that treats digit runs as numbers (01 < 2 < 10).
  int ia = 0, ib = 0;
  final na = a.length, nb = b.length;
  while (ia < na && ib < nb) {
    final ca = a.codeUnitAt(ia);
    final cb = b.codeUnitAt(ib);

    final da = _isDigit(ca);
    final db = _isDigit(cb);

    if (da && db) {
      // Read full number runs
      final sa = ia;
      while (ia < na && _isDigit(a.codeUnitAt(ia))) ia++;
      final sb = ib;
      while (ib < nb && _isDigit(b.codeUnitAt(ib))) ib++;

      // Compare numerically
      final numA = int.parse(a.substring(sa, ia));
      final numB = int.parse(b.substring(sb, ib));
      if (numA != numB) return numA - numB;

      // If equal numerically, shorter digit run (fewer leading zeros) wins
      final lenDiff = (ia - sa) - (ib - sb);
      if (lenDiff != 0) return lenDiff;
      // else continue
    } else {
      // Compare single chars case-insensitively
      final la = String.fromCharCode(ca).toLowerCase();
      final lb = String.fromCharCode(cb).toLowerCase();
      final c = la.compareTo(lb);
      if (c != 0) return c;
      ia++;
      ib++;
    }
  }
  // Shorter remainder wins
  return (na - ia) - (nb - ib);
}

class FilesScreen extends StatefulWidget {
  final String groupId;
  final String? groupName;
  final String? ownerUid;
  final List<String>? adminUids;
  final void Function(Future<bool> Function())? registerBackHandler;
  //final void Function(Future<void> Function())? registerUploadAction;
  const FilesScreen({
    super.key,
    required this.groupId,
    this.groupName,
    this.ownerUid,
    this.adminUids,
    this.registerBackHandler,
    //this.registerUploadAction,
  });
  String joinPosix(String base, String child) =>
      base.isEmpty ? child : p.posix.join(base, child);

  String normalizePosix(String path) =>
      path.isEmpty ? '' : p.posix.normalize(path);

  @override
  State<FilesScreen> createState() => FilesScreenState();
}

class BreadcrumbChips extends StatelessWidget {
  final List<String> segments;
  final void Function(int index)? onTap;
  final int maxChars; // label abbreviation length (e.g., 5)
  final double
      maxRowsHeight; // the vertical space you allow (e.g., ~2 rows height)

  const BreadcrumbChips({
    super.key,
    required this.segments,
    this.onTap,
    this.maxChars = 6,
    this.maxRowsHeight = 65, // match your AppBar title SizedBox height
  });

  String _abbr(String s, int n) {
    final full = Uri.decodeComponent(s);
    if (full.length <= n) return full;
    return '${full.characters.take(n)}…';
  }

  // Rough width calculation for a chip given style/padding.
  double _chipWidth({
    required BuildContext context,
    required String label,
    required TextStyle style,
    required bool hasChevron,
    required EdgeInsets padding,
    required double spacingBetweenTextAndChevron,
    required double borderWidth,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(minWidth: 0, maxWidth: double.infinity);

    final chevronWidth = hasChevron
        ? (TextPainter(
              text: TextSpan(text: '›', style: style),
              textDirection: TextDirection.ltr,
            )..layout())
                .width +
            spacingBetweenTextAndChevron
        : 0;

    // padding + text + optional chevron + 2*borderWidth (stadium outline)
    return padding.left +
        chevronWidth +
        tp.width +
        padding.right +
        (borderWidth * 2);
  }

  @override
  Widget build(BuildContext context) {
    //super.build(context);
    // Two style presets: roomy (single-row) vs compact (two-rows)
    final baseStyle = Theme.of(context).textTheme.bodySmall ??
        const TextStyle(); // fallback if null

    final roomyStyle = baseStyle.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );

    final compactStyle = baseStyle.copyWith(
      fontSize: 11,
      fontWeight: FontWeight.w500,
    );

    // Visuals
    final outline = Theme.of(
      context,
    ).colorScheme.outlineVariant.withOpacity(.5);
    final bg = Theme.of(context).colorScheme.surfaceVariant.withOpacity(.22);

    // Presets we’ll toggle
    const roomyPadding = EdgeInsets.symmetric(horizontal: 8, vertical: 2);
    const compactPadding = EdgeInsets.symmetric(horizontal: 4, vertical: 0);
    const borderWidth = 1.0;
    const spacingBetweenTextAndChevron = 4.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;

        // 1) First, estimate total width using the ROOMY preset
        double estimated = 0;
        for (int i = 0; i < segments.length; i++) {
          final label = _abbr(segments[i], maxChars);
          estimated += _chipWidth(
            context: context,
            label: label,
            style: roomyStyle,
            hasChevron: i != 0,
            padding: roomyPadding,
            spacingBetweenTextAndChevron: spacingBetweenTextAndChevron,
            borderWidth: borderWidth,
          );
          if (i < segments.length - 1) estimated += 6; // roomy spacing
        }

        final useCompact = estimated >
            maxWidth; // if it wouldn't fit on one row, compact everything

        final style = useCompact ? compactStyle : roomyStyle;
        final padding = useCompact ? compactPadding : roomyPadding;
        final spacing = useCompact ? 1.0 : 10.0;
        final runSpacing = useCompact ? 2.0 : 4.0;
        final density = useCompact
            ? const VisualDensity(horizontal: -4, vertical: -4)
            : const VisualDensity(horizontal: -2, vertical: -2);

        // 2) Render chips with chosen preset; Wrap will handle the second row
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxRowsHeight),
          child: Wrap(
            spacing: spacing,
            runSpacing: runSpacing,
            children: [
              for (int i = 0; i < segments.length; i++)
                Tooltip(
                  message: Uri.decodeComponent(segments[i]),
                  waitDuration: const Duration(milliseconds: 300),
                  child: ActionChip(
                    visualDensity: density,
                    padding: padding,
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            _abbr(segments[i], maxChars),
                            style: style,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ),
                        if (i != segments.length - 1) ...[
                          // only show if not the last segment
                          const SizedBox(width: 4),
                          Text('›', style: style),
                        ],
                      ],
                    ),
                    onPressed: onTap == null ? null : () => onTap!(i),
                    shape: const StadiumBorder(
                      side: BorderSide(width: borderWidth),
                    ).copyWith(
                      side: BorderSide(color: outline, width: borderWidth),
                    ),
                    backgroundColor: bg,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class FilesScreenState extends State<FilesScreen>
    with AutomaticKeepAliveClientMixin<FilesScreen> {
  // You can also inject these via your app settings.
  //late final JellyfinThumbService _jf;
  // --- poster & thumbnail caches ---
  final Map<String, String?> _posterUrlByName = {}; // key: nameSansExt
  final Map<String, File?> _thumbByUrl = {}; // key: videoUrl
  String? _thumbKickoffPath;
  final _thumbGate = _AsyncGate(max: 1); // shared for all generation
  final Set<String> _thumbInFlight = {};

  // Where we keep cached images
  late final Directory _thumbsDir; // video frames
  late final Directory _postersDir; // jellyfin posters

  Future<void> pickAndUpload() => _pickAndUpload();

  /// Play or resume from the most relevant media file in the current folder.
  /// Returns true if a player screen was pushed.
  Future<bool> playResumeInCurrentFolder(BuildContext context) async {
    // Ensure we have a listing of the current folder
    final listing = _lastListing;
    if (listing == null) return false;

    // Filter to media we support (audio + video), then sort alphanumeric
    bool _isAllowed(String name) {
      final ext = p.extension(name).toLowerCase();
      final isVid = _videoExts.contains(ext);
      final isAud = _audioExts.contains(ext);
      return isVid || isAud;
    }

    final mediaFiles =
        listing.files.where((f) => _isAllowed(f.fileName)).toList()
          ..sort((a, b) => _naturalCompare(
                a.fileName.toLowerCase(),
                b.fileName.toLowerCase(),
              ));

    if (mediaFiles.isEmpty) return false;

    // Use the same resume key scheme as the player
    String _resumeKeyForUrl(String uri) {
      final b64 = base64Url.encode(utf8.encode(uri)).replaceAll('=', '');
      return 'resume:$b64';
    }

    // --- Choose start index policy ---
// 1) Prefer the file with the most recent "last played" timestamp.
// 2) If none have a timestamp, fallback to the file with the largest resume ms (>= 5s).
    int startIdx = 0;

// Helper to read "last played" timestamp written by the player
    Future<int?> _loadLastPlayed(String resumeKey) async {
      try {
        final sp = await SharedPreferences.getInstance();
        return sp.getInt('last:' + resumeKey);
      } catch (_) {
        return null;
      }
    }

// First pass: pick by most recent last-played
    int bestIdxByTs = -1;
    int bestTs = -1;
    for (var i = 0; i < mediaFiles.length; i++) {
      final key = _resumeKeyForUrl(mediaFiles[i].fileUrl);
      final ts = await _loadLastPlayed(key) ?? -1;
      if (ts > bestTs) {
        bestTs = ts;
        bestIdxByTs = i;
      }
    }
    if (bestIdxByTs >= 0 && bestTs > 0) {
      startIdx = bestIdxByTs;
    } else {
      // Second pass: fallback to largest resume position (existing behavior)
      int bestMs = -1;
      for (var i = 0; i < mediaFiles.length; i++) {
        final key = _resumeKeyForUrl(mediaFiles[i].fileUrl);
        final ms = await ResumeStore.load(key);
        if (ms != null && ms > 5000 && ms > bestMs) {
          bestMs = ms;
          startIdx = i;
        }
      }
    }

    // Build a playlist rooted at the chosen start file
    final playlist = _buildFolderPlaylist(
      mediaFiles[startIdx],
      includeAudio: true,
      includeVideo: true,
    );
    final urls = (playlist['urls'] as List).cast<String>();
    final names = (playlist['names'] as List).cast<String>();
    final idx = playlist['index'] as int;

    if (!mounted) return false;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          videoUrl: urls[idx],
          fileName: names[idx],
          playlistUrls: urls,
          playlistNames: names,
          initialIndex: idx,
          // let the player apply resume on the first event
          resumeOnInitialOpen: true,
          initialReplayAll: true,
        ),
      ),
    );
    return true;
  }

// Cache file paths
  Future<File> _posterCacheFile(FileModel f) async {
    final k = _keyForFile(f);
    return File('${_postersDir.path}/$k.jpg'); // jpg or png, consistent is fine
  }

  Future<File> _thumbCacheFile(FileModel f) async {
    final k = _keyForFile(f);
    return File('${_thumbsDir.path}/$k.png');
  }

  // Notifies the UI when a specific file’s thumb/poster becomes available.
  final Map<String, ValueNotifier<File?>> _thumbNotifier =
      {}; // key = _keyForFile(f)

  ValueNotifier<File?> _ensureNotifier(FileModel f) {
    final k = _keyForFile(f);
    return _thumbNotifier.putIfAbsent(k, () => ValueNotifier<File?>(null));
  }

  Future<void> _publishThumbToUi(FileModel f, File imgFile) async {
    // Precache decoded pixels to avoid one-frame “pop in”
    try {
      if (mounted) {
        await precacheImage(FileImage(imgFile), context);
      }
    } catch (_) {}
    _ensureNotifier(f).value = imgFile;
  }

// Unique, stable keys (feel free to tweak)
  String _keyForFile(FileModel f) {
    // Use logical path so same names in different folders don’t collide
    final s = f.storagePath; // "<gid>/Folder/foo.mkv"
    final b64 = base64Url.encode(utf8.encode(s)).replaceAll('=', '');
    return b64;
  }

// Simple concurrency gate so we don't spawn tons of encoders
  final _jfGate = _AsyncGate(max: 4); // at most 4 JF requests

  static String _pathKey(String groupId) => 'files_path:$groupId';
  final ScrollController _scroll = ScrollController();

  String? _restoredForPath; // guard so we restore once per path
  static String _scrollKey(String gid, String path) =>
      'files_scroll:$gid:$path';

  // Strip a single extension (e.g. "Movie.mkv" -> "Movie")
  String _nameSansExt(String name) => p.basenameWithoutExtension(name);

  String _safeNameFromUrl(String url) {
    // Stable-ish filename for cache. URL-safe base64 without padding.
    final b64 = base64Url.encode(utf8.encode(url)).replaceAll('=', '');
    return b64;
  }

  // Point to your Node proxy (LAN IP or DuckDNS; NOT localhost for devices)
  static const String _jfApiBase = 'http://cacheboxcapstone.duckdns.org:3000';

// Build & save a Jellyfin poster (if found). Returns true if saved.
  Future<bool> _buildAndSaveJfPoster(FileModel f, {String? folderHint}) async {
    try {
      final nameSansExt = p.basenameWithoutExtension(f.fileName);
      final uri = Uri.parse('$_jfApiBase/api/jf/poster').replace(
        queryParameters: {
          'name': nameSansExt,
          if (folderHint != null && folderHint.isNotEmpty) 'hint': folderHint,
        },
      );

      final r = await http.get(uri).timeout(const Duration(seconds: 5));
      if (r.statusCode == 200 &&
          (r.headers['content-type'] ?? '').startsWith('image/')) {
        final out = await _posterCacheFile(f);
        await out.writeAsBytes(r.bodyBytes, flush: true);
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> refreshCurrentFolderThumbnails() async {
    final listing = _lastListing;
    if (listing == null) return;

    final segs = _currentPath.split('/').where((s) => s.isNotEmpty).toList();
    final folderHint = segs.isNotEmpty ? segs.last : null;

    // Only videos in the current folder
    final videos = listing.files.where((f) {
      final ext = p.extension(f.fileName).toLowerCase();
      return _videoExts.contains(ext);
    }).toList();

    // Optionally: cap concurrency (simple for-loop is fine too)
    for (final f in videos) {
      final poster = await _posterCacheFile(f);
      final thumb = await _thumbCacheFile(f);
      if (await poster.exists() || await thumb.exists()) {
        continue; // already cached, skip
      }
      final okPoster = await _buildAndSaveJfPoster(f, folderHint: folderHint);
      if (!okPoster) {
        final okLocal = await _buildAndSaveLocalThumb(f);
        if (okLocal) {
          final file = await _thumbCacheFile(f);
          await _publishThumbToUi(f, file);
        }
      } else {
        final file = await _posterCacheFile(f);
        await _publishThumbToUi(f, file);
      }
    }

    // No setState here. Individual tiles update via ValueNotifiers.
    return;
  }

  Future<void> _refreshOneFile(FileModel f) async {
    final segs = _currentPath.split('/').where((s) => s.isNotEmpty).toList();
    final folderHint = segs.isNotEmpty ? segs.last : null;

    final poster = await _posterCacheFile(f);
    final thumb = await _thumbCacheFile(f);
    if (await poster.exists() || await thumb.exists()) {
      // if name changed, consider clearing old cache file; else keep
    }

    final okPoster = await _buildAndSaveJfPoster(f, folderHint: folderHint);
    if (okPoster) {
      final img = await _posterCacheFile(f);
      await _publishThumbToUi(f, img);
    } else {
      final okLocal = await _buildAndSaveLocalThumb(f);
      if (okLocal) {
        final img = await _thumbCacheFile(f);
        await _publishThumbToUi(f, img);
      }
    }
    if (mounted) setState(() {}); // keeps non-thumb parts fresh
  }

// Build & save a local frame thumbnail (fallback). Returns true if saved.
  Future<bool> _buildAndSaveLocalThumb(FileModel f, {int timeMs = 5000}) async {
    final out = await _thumbCacheFile(f);
    if (await out.exists()) return true;

    final k = _keyForFile(f);
    if (_thumbInFlight.contains(k)) return false;

    return _thumbGate.run<bool>(() async {
      if (await out.exists()) return true;
      _thumbInFlight.add(k);
      try {
        final gen = await VideoThumbnail.thumbnailFile(
          video: f.fileUrl,
          timeMs: timeMs,
          imageFormat: ImageFormat.PNG,
          maxWidth: 256,
          quality: 75,
          thumbnailPath: out.path,
        );
        await Future.delayed(const Duration(milliseconds: 30));
        return gen != null;
      } finally {
        _thumbInFlight.remove(k);
      }
    });
  }

  String _jfPosterUrlFor(String nameSansExt, {String? folderHint}) {
    final qp = <String, String>{'name': nameSansExt};
    if (folderHint != null && folderHint.isNotEmpty) qp['hint'] = folderHint;
    return Uri.parse('$_jfApiBase/api/jf/poster')
        .replace(queryParameters: qp)
        .toString();
  }

  Future<File?> _ensureVideoThumbCached(String videoUrl,
      {int timeMs = 5000}) async {
    // cache hit
    final cached = _thumbByUrl[videoUrl];
    if (cached != null) return cached;

    final tmpDir = await getTemporaryDirectory();
    final thumbsDir = Directory('${tmpDir.path}/video_thumbs');
    if (!await thumbsDir.exists()) {
      await thumbsDir.create(recursive: true);
    }
    final outPath = '${thumbsDir.path}/${_safeNameFromUrl(videoUrl)}.png';
    final outFile = File(outPath);
    if (await outFile.exists()) {
      _thumbByUrl[videoUrl] = outFile;
      return outFile;
    }

    // cap CPU usage by allowing only a couple encodes concurrently
    return await _thumbGate.run<File?>(() async {
      try {
        final gen = await VideoThumbnail.thumbnailFile(
          video: videoUrl,
          timeMs: timeMs,
          imageFormat: ImageFormat.PNG,
          maxWidth: 256,
          quality: 75,
          thumbnailPath: outPath,
        );
        if (gen == null) return null;
        final f = File(gen);
        _thumbByUrl[videoUrl] = f;
        return f;
      } catch (_) {
        return null;
      }
    });
  }

  /// Returns a small leading widget (image or icon) for a *video* file.
  /// Prefers Jellyfin poster; falls back to local generated frame.
  Future<Widget> _buildVideoLeading(FileModel file) async {
    final ext = p.extension(file.fileName).toLowerCase();
    final isVideo = _videoExts.contains(ext);
    if (!isVideo) return const Icon(Icons.insert_drive_file_outlined);

    final poster = await _posterCacheFile(file);
    if (await poster.exists()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(poster, width: 64, height: 64, fit: BoxFit.cover),
      );
    }

    final thumb = await _thumbCacheFile(file);
    if (await thumb.exists()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(thumb, width: 64, height: 64, fit: BoxFit.cover),
      );
    }

    // Nothing cached yet → show placeholder only
    return const Icon(Icons.movie_outlined);
  }

  Future<void> _saveScrollFor(String path) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble(_scrollKey(widget.groupId, path), _scroll.offset);
  }

  Future<void> _restoreScrollFor(String path) async {
    final sp = await SharedPreferences.getInstance();
    final off = sp.getDouble(_scrollKey(widget.groupId, path)) ?? 0.0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      _scroll.jumpTo(off.clamp(0.0, max));
    });
  }

  @override
  bool get wantKeepAlive => true;
  void initState() {
    super.initState();
    // Init cache dirs (once)
    (() async {
      final tmp = await getTemporaryDirectory();
      _thumbsDir = Directory('${tmp.path}/video_thumbs');
      _postersDir = Directory('${tmp.path}/jf_posters');
      if (!await _thumbsDir.exists()) await _thumbsDir.create(recursive: true);
      if (!await _postersDir.exists())
        await _postersDir.create(recursive: true);
    })();
    widget.registerBackHandler?.call(_onBackRequested);
    //widget.registerUploadAction?.call(_pickAndUpload);
    _restorePath();
  }

  @override
  void didUpdateWidget(covariant FilesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.registerBackHandler != widget.registerBackHandler) {
      widget.registerBackHandler?.call(_onBackRequested);
    }
    // if (oldWidget.registerUploadAction != widget.registerUploadAction) {
    //   widget.registerUploadAction?.call(_pickAndUpload); // keep it fresh
    // }
  }

  @override
  void dispose() {
    //widget.registerUploadAction?.call(() async {});
    _scroll.dispose();
    super.dispose();
  }

  DirectoryListing? _lastListing;
  final _service = FileService();

  String _prettyPathFor(FileModel f) {
    // Convert storagePath like "<groupId>/Memes/Funny/pic.png" to "Files/Memes/Funny/pic.png"
    final sp = f.storagePath;
    final marker = '${widget.groupId}/';

    // Case 1: exact group root
    if (sp == widget.groupId || sp.isEmpty) return 'Files';

    // Case 2: strip "<groupId>/" prefix if present
    if (sp.startsWith(marker)) {
      final rel = sp.substring(marker.length); // e.g., "Memes/Funny/pic.png"
      return rel.isEmpty ? 'Files' : 'Files/$rel';
    }

    // Fallback (already normalized by your FileService): prefix with Files
    return 'Files/${sp.replaceFirst(RegExp(r'^/+'), '')}';
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double size = bytes.toDouble();
    int unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(size < 10 && unit > 0 ? 1 : 0)} ${units[unit]}';
  }

  String _formatDate(DateTime dt) {
    // Simple, local time formatting
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<Map<String, String>> _headFor(String url) async {
    // HEAD request to read size/type without downloading content
    final resp = await http.head(Uri.parse(url));
    final headers = <String, String>{};
    resp.headers.forEach((k, v) => headers[k.toLowerCase()] = v);
    return headers;
  }

  Widget _kvRow(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$k: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }

  Future<bool> _onBackRequested() async {
    // Adjust these to your actual path state & go-up method
    final atRoot = _currentPath.isEmpty || _currentPath == "/";
    if (!atRoot) {
      _popFolder(); // your existing "go up one level" function
      return true; // consumed
    }
    return false; // at root: not handled (parent will do nothing)
  }

  /// Track the current virtual path ('' = root). No trailing slash.
  String _currentPath = '';

  /// For loading state while navigating or downloading.
  bool _busy = false;

  Future<DirectoryListing> _load() {
    // API expects a trailing slash for non-root
    final apiPath =
        _currentPath.isEmpty ? '' : '${widget.normalizePosix(_currentPath)}/';
    return _service.listEntries(widget.groupId, path: apiPath, sync: false);
  }

  /// Build a simple folder-scoped playlist for the current file.
  /// Returns a map:
  ///  - 'urls':  List<String> of media URLs
  ///  - 'names': List<String> of display names (usually file names)
  ///  - 'index': int index of the current file within the playlist
  Map<String, Object> _buildFolderPlaylist(
    FileModel current, {
    bool includeAudio = false,
    bool includeVideo = true,
  }) {
    // Safety valve: if both are false, default to video.
    if (!includeAudio && !includeVideo) {
      includeVideo = true;
    }

    // If we don't have a listing yet, just return the current file as a 1-item playlist.
    final listing = _lastListing;
    if (listing == null) {
      return {
        'urls': <String>[current.fileUrl],
        'names': <String>[current.fileName],
        'index': 0,
      };
    }

    bool _isAllowed(String fileName) {
      final ext = fileName.contains('.')
          ? fileName.substring(fileName.lastIndexOf('.')).toLowerCase()
          : '';
      final isVid = _videoExts.contains(ext);
      final isAud = _audioExts.contains(ext);
      if (includeAudio && includeVideo) return isVid || isAud;
      if (includeVideo) return isVid;
      if (includeAudio) return isAud;
      return false;
    }

    // Filter to allowed media types from the current folder, then sort alphanumerically by name.
    final mediaFiles = listing.files
        .where((f) => _isAllowed(f.fileName))
        .toList()
      ..sort((a, b) =>
          _naturalCompare(a.fileName.toLowerCase(), b.fileName.toLowerCase()));

    // Build parallel URL/name lists.
    final urls = <String>[];
    final names = <String>[];
    for (final f in mediaFiles) {
      urls.add(f.fileUrl);
      names.add(f.fileName);
    }

    // Find index of the current item; match by URL first, then by ID.
    var idx = urls.indexOf(current.fileUrl);
    if (idx < 0) {
      final byId = mediaFiles.indexWhere((f) => f.id == current.id);
      idx = byId;
    }

    // If the current file wasn't in the filtered/sorted list (e.g., type mismatch),
    // append it so playback still works predictably.
    if (idx < 0) {
      urls.add(current.fileUrl);
      names.add(current.fileName);
      idx = urls.length - 1;
    }

    return {
      'urls': urls,
      'names': names,
      'index': idx,
    };
  }

  void _pushFolder(FolderModel folder) {
    _saveScrollFor(_currentPath);
    setState(() {
      // Build next path using our own join/normalize; avoid server-concatenated paths
      _currentPath = widget.normalizePosix(
        widget.joinPosix(_currentPath, folder.name),
      );
      _restoredForPath = null;
    });
    _savePath();
  }

  void _popFolder() {
    if (_currentPath.isEmpty) return;
    _saveScrollFor(_currentPath);
    final idx = _currentPath.lastIndexOf('/');
    setState(() {
      _currentPath = idx >= 0 ? _currentPath.substring(0, idx) : '';
      _restoredForPath = null;
    });
    _savePath();
  }

  Future<void> _restorePath() async {
    final sp = await SharedPreferences.getInstance();
    final saved = sp.getString(_pathKey(widget.groupId)) ?? '';
    if (!mounted) return;
    setState(() => _currentPath = saved);
  }

  Future<void> _savePath() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_pathKey(widget.groupId), _currentPath);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: SizedBox(
          height: 65, // ~2 compact rows of chips fit here
          child: Align(
            alignment: Alignment.centerLeft,
            child: BreadcrumbChips(
              segments: [
                'Files',
                ..._currentPath.split('/').where((s) => s.isNotEmpty),
              ],
              maxChars: 6,
              maxRowsHeight: 65, // same as SizedBox(height)
              onTap: (idx) {
                final segs =
                    _currentPath.split('/').where((s) => s.isNotEmpty).toList();
                setState(() {
                  _currentPath = (idx == 0) ? '' : segs.take(idx).join('/');
                });
                _savePath();
              },
            ),
          ),
        ),
      ),

      body: FutureBuilder<DirectoryListing>(
        future: _load(),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }

          final listing =
              snap.data ?? const DirectoryListing(folders: [], files: []);
          _lastListing = listing;

          // Proactively build thumbs/posters for the current folder (post-frame; once per path)
          if (_thumbKickoffPath != _currentPath) {
            _thumbKickoffPath = _currentPath;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              unawaited(refreshCurrentFolderThumbnails());
            });
          }

          // Natural sort (case-insensitive)
          final sortedFolders = [...listing.folders]..sort((a, b) =>
              _naturalCompare(a.name.toLowerCase(), b.name.toLowerCase()));

          final sortedFiles = [...listing.files]..sort((a, b) =>
              _naturalCompare(
                  a.fileName.toLowerCase(), b.fileName.toLowerCase()));

          // Build a single list of entries (folders first, then files)
          final entries = <Object>[];
          entries.addAll(sortedFolders); // FolderModel
          entries.addAll(sortedFiles); // FileModel

          if (entries.isEmpty) {
            return const Center(child: Text('This folder is empty.'));
          }

          // Restore once per path after layout
          if (_restoredForPath != _currentPath) {
            _restoredForPath = _currentPath;
            _restoreScrollFor(_currentPath);
          }

          return CupertinoScrollbar(
            controller: _scroll,
            thickness: 4,
            child: ListView.builder(
              key: PageStorageKey('files:${widget.groupId}/$_currentPath'),
              controller: _scroll,
              primary: false, // since we're providing a controller
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: entries.length,
              cacheExtent: 800,
              itemBuilder: (ctx, i) {
                final e = entries[i];
                if (e is FolderModel) {
                  return ListTile(
                    leading: const Icon(Icons.folder),
                    title: Text(Uri.decodeComponent(e.name)),
                    subtitle: e.childrenCount != null
                        ? Text('${e.childrenCount} items')
                        : null,
                    onTap: () => _pushFolder(e),
                  );
                } else {
                  final f = e as FileModel;
                  return _buildFileTile(f);
                }
              },
            ),
          );
        },
      ),

      // floatingActionButton: FloatingActionButton.extended(
      //   onPressed: _busy ? null : _pickAndUpload,
      //   label: const Text('Upload'),
      //   icon: const Icon(Icons.upload),
      // ),
    );
  }

  // void _debugPerms(FileModel f) {
  //   final uid = FirebaseAuth.instance.currentUser?.uid;
  //   debugPrint('[perm] me=$uid '
  //       'uploader=${f.uploadedByUid} '
  //       'owner=${widget.ownerUid} '
  //       'admins=${widget.adminUids}');
  // }

  Widget _buildFileTile(FileModel file) {
    //_debugPerms(file);
    final ext = p.extension(file.fileName).toLowerCase();
    //final icon = _iconForExt(ext);
    final currentUid = FirebaseAuth.instance.currentUser!.uid;
    final canDelete = currentUid == file.uploadedByUid ||
        currentUid == widget.ownerUid ||
        (widget.adminUids?.contains(currentUid) ?? false);
    Widget leading;

// determine types
    final isImage = ['.png', '.jpg', '.jpeg', '.gif', '.webp'].contains(ext);
    final isVideo =
        ['.mp4', '.mkv', '.webm', '.avi', '.mov', '.m4v', '.ts'].contains(ext);
    final isAudio = _audioExts.contains(ext);

    if (isImage) {
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          file.fileUrl,
          width: 64,
          height: 64,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(Icons.image_outlined),
        ),
      );
    } else if (isVideo) {
      final key = _keyForFile(file);
      final vn = _ensureNotifier(file);

      // Seed the notifier synchronously if a cached file already exists.
      // Schedule seeding/kickoff after the current frame to avoid build-time updates
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(() async {
          // Check poster first, then thumb.
          final poster = await _posterCacheFile(file);
          final thumb = await _thumbCacheFile(file);
          if (await poster.exists()) {
            if (_ensureNotifier(file).value == null) {
              await _publishThumbToUi(file, poster);
            }
            return;
          }
          if (await thumb.exists()) {
            if (_ensureNotifier(file).value == null) {
              await _publishThumbToUi(file, thumb);
            }
            return;
          }

          // Nothing cached yet → build one in background
          final segs =
              _currentPath.split('/').where((s) => s.isNotEmpty).toList();
          final folderHint = segs.isNotEmpty ? segs.last : null;
          final okPoster =
              await _buildAndSaveJfPoster(file, folderHint: folderHint);
          if (okPoster) {
            final f = await _posterCacheFile(file);
            await _publishThumbToUi(file, f);
          } else {
            final okLocal = await _buildAndSaveLocalThumb(file);
            if (okLocal) {
              final f = await _thumbCacheFile(file);
              await _publishThumbToUi(file, f);
            }
          }
        }());
      });

      leading = ValueListenableBuilder<File?>(
        valueListenable: vn,
        builder: (ctx, imgFile, _) {
          if (imgFile != null) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(
                imgFile,
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                // Hint the decoder to keep it small in memory:
                cacheWidth: 128, // optional: smaller decode
              ),
            );
          }
          // Placeholder while the notifier is still null
          return const SizedBox(
            width: 64,
            height: 64,
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
      );
    } else if (isAudio) {
      leading = const Icon(Icons.audiotrack);
    } else {
      leading = const Icon(Icons.insert_drive_file_outlined);
    }
    return ListTile(
      leading: leading,
      title: Text(file.fileName),
      subtitle: Text(file.uploadedByName),
      onTap: () => _openFile(file),
      trailing: PopupMenuButton<FileAction>(
        onSelected: (act) => _onFileAction(file, act),
        itemBuilder: (ctx) {
          final items = <PopupMenuEntry<FileAction>>[
            const PopupMenuItem(
              value: FileAction.details,
              child: Text('Details'),
            ),
          ];
          if (canDelete) {
            items.addAll([
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: FileAction.rename,
                child: Text('Rename'),
              ),
              const PopupMenuItem(
                value: FileAction.delete,
                child: Text('Delete'),
              ),
            ]);
          }
          return items;
        },
      ),
    );
  }

  Future<void> _onFileAction(FileModel f, FileAction action) async {
    switch (action) {
      case FileAction.rename:
        await _renameFile(f);
        break;
      case FileAction.details:
        await _showFileDetails(f);
        break;
      case FileAction.delete:
        await _confirmDelete(f); // you already have this
        break;
    }
  }

  /// ---- RENAME ----
  Future<void> _renameFile(FileModel f) async {
    final controller = TextEditingController(text: f.fileName);

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename file'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'New name',
            hintText: 'example.txt',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final newName = controller.text.trim();
    if (newName.isEmpty || newName == f.fileName) return;

    try {
      // 1) Rename on the server (your API returns void)
      await _service.renameFile(
        widget.groupId,
        fileId: f.id,
        newFileName: newName,
      );

      // 2) Reload this folder to get the accurate, updated FileModel
      final listing = await _load();

      // Prefer matching by id (stable); fallback to name if needed
      FileModel? updated =
          listing.files.firstWhere((x) => x.id == f.id, orElse: () => f);
      if (updated == f) {
        // If id match failed, try by new name
        try {
          updated = listing.files.firstWhere((x) => x.fileName == newName);
        } catch (_) {
          // As a last resort, synthesize a temp record (okay for poster/thumbnail refresh)
          updated = FileModel(
            id: f.id,
            fileName: newName,
            fileUrl: f
                .fileUrl, // may be slightly stale; our refresh does not need it if JF hits
            uploadedByUid: f.uploadedByUid,
            uploadedByName: f.uploadedByName,
            storagePath: f.storagePath.replaceFirst(
              RegExp(r'[^/]+$'), // replace the leaf name
              newName,
            ),
            mimeType: f.mimeType,
          );
        }
      }

      // 3) Refresh thumbnails/poster for just this file
      await _refreshOneFile(updated);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Renamed')),
      );
      setState(() {}); // refresh listing in UI
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rename failed: $e')),
      );
    }
  }

  /// ---- DETAILS ----
  Future<void> _showFileDetails(FileModel f) async {
    // Gather “safe” details the UI can show
    final String fileName = f.fileName;
    final String typeHint =
        (f.mimeType ?? '').isNotEmpty ? f.mimeType! : 'unknown';
    final String uploadedBy = (f.uploadedByName ?? '').isNotEmpty
        ? f.uploadedByName!
        : (f.uploadedByUid ?? 'unknown');

    // Try to read size/type/last-modified from HTTP headers (HEAD)
    int? sizeBytes;
    String? contentType;
    DateTime? lastModified;

    try {
      final h = await _headFor(f.fileUrl);
      if (h['content-length'] != null) {
        final parsed = int.tryParse(h['content-length']!);
        if (parsed != null && parsed >= 0) sizeBytes = parsed;
      }
      if (h['content-type'] != null) {
        contentType = h['content-type'];
      }
      if (h['last-modified'] != null) {
        final lm = DateTime.tryParse(h['last-modified']!);
        if (lm != null) lastModified = lm.toLocal();
      }
    } catch (_) {
      // HEAD may not be supported by all file handlers; ignore silently
    }

    // Prefer server-provided mimeType, else HEAD content-type
    final shownType =
        typeHint != 'unknown' ? typeHint : (contentType ?? 'unknown');

    // If your metadata includes uploadedAt (ISO8601), show it
    DateTime? uploadedAt;
    try {
      // Your server sets uploadedAt in metadata; adjust key if different
      // If your FileModel doesn't expose it, skip this
      final map = (f as dynamic); // avoid breaking your model
      final str = map.uploadedAt as String?;
      if (str != null && str.isNotEmpty) {
        final dt = DateTime.tryParse(str);
        if (dt != null) uploadedAt = dt.toLocal();
      }
    } catch (_) {}

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('File details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kvRow('Name', fileName),
            _kvRow('Type', shownType),
            if (sizeBytes != null) _kvRow('Size', _formatBytes(sizeBytes)),
            if (uploadedAt != null) _kvRow('Uploaded', _formatDate(uploadedAt)),
            if (lastModified != null)
              _kvRow('Last modified', _formatDate(lastModified)),
            _kvRow('Path', _prettyPathFor(f)), // logical path within the group
            _kvRow('Uploaded by', uploadedBy),
            // Deliberately NOT showing internal server paths or raw URL.
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$k: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }

  IconData _iconForExt(String ext) {
    switch (ext) {
      case '.png':
      case '.jpg':
      case '.jpeg':
      case '.gif':
      case '.webp':
        return Icons.image_outlined;
      case '.mp4':
      case '.mkv':
      case '.webm':
      case '.avi':
        return Icons.movie_outlined;
      case '.mp3':
      case '.wav':
      case '.m4a':
        return Icons.audiotrack;
      case '.pdf':
        return Icons.picture_as_pdf_outlined;
      case '.txt':
      case '.md':
      case '.json':
      case '.csv':
        return Icons.description_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  static const _videoExts = {
    '.mp4',
    '.mkv',
    '.webm',
    '.avi',
    '.mpg',
    '.mpeg',
    '.wmv',
    '.mov',
    '.flv',
    '.ts',
    '.m4v'
  };
  static const _audioExts = {
    '.mp3',
    '.m4a',
    '.aac',
    '.wav',
    '.flac',
    '.ogg',
    '.oga',
    '.opus',
    '.wma',
    '.aiff',
    '.alac'
  };
  Future<void> _openFile(FileModel file) async {
    await _saveScrollFor(_currentPath);
    setState(() => _busy = true);
    try {
      final url = file.fileUrl;
      final ext = p.extension(file.fileName).toLowerCase();

      if (['.png', '.jpg', '.jpeg', '.gif', '.webp'].contains(ext)) {
        setState(() => _busy = false);
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ImageViewerScreen(imageUrl: url, fileName: file.fileName),
          ),
        );
      } else if (['.mp3', '.wav', '.m4a'].contains(ext)) {
        setState(() => _busy = false);
        if (!mounted) return;
        // Route audio files to VideoPlayerScreen with folder playlist
        final playlist =
            _buildFolderPlaylist(file, includeAudio: true, includeVideo: true);
        final playlistUrls = playlist['urls'] as List<String>;
        final playlistNames = playlist['names'] as List<String>;
        final initialIndex = playlist['index'] as int;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VideoPlayerScreen(
              videoUrl: url,
              fileName: file.fileName,
              playlistUrls: playlistUrls,
              playlistNames: playlistNames,
              initialIndex: initialIndex,
            ),
          ),
        );
      } else if (['.mp4', '.mkv', '.webm', '.avi'].contains(ext)) {
        setState(() => _busy = false);
        if (!mounted) return;
        // Route video files to VideoPlayerScreen with folder playlist
        final playlist =
            _buildFolderPlaylist(file, includeAudio: true, includeVideo: true);
        final playlistUrls = playlist['urls'] as List<String>;
        final playlistNames = playlist['names'] as List<String>;
        final initialIndex = playlist['index'] as int;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VideoPlayerScreen(
              videoUrl: url,
              fileName: file.fileName,
              playlistUrls: playlistUrls,
              playlistNames: playlistNames,
              initialIndex: initialIndex,
              resumeOnInitialOpen: true,
            ),
          ),
        );
      } else if (ext == '.pdf') {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode != 200) {
          throw Exception('Failed to download PDF (${response.statusCode})');
        }
        final tmpDir = await getTemporaryDirectory();
        final tmpPath = '${tmpDir.path}/${file.fileName}';
        await File(tmpPath).writeAsBytes(response.bodyBytes, flush: true);

        setState(() => _busy = false);
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                PdfViewerScreen(filePath: tmpPath, fileName: file.fileName),
          ),
        );
      } else {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode != 200) {
          throw Exception('Failed to download file (${response.statusCode})');
        }
        final text = utf8.decode(response.bodyBytes);
        setState(() => _busy = false);
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TextViewerScreen(
              textContent: text,
              fileName: file.fileName,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => _busy = false);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Open failed: $e')));
    }
  }

  Future<void> _confirmDelete(FileModel file) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete file'),
        content: Text('Delete "${file.fileName}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await _service.deleteFile(widget.groupId, file.id);
        if (!mounted) return;
        setState(() {}); // reload
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  Future<void> _pickAndUpload() async {
    // Pick by path/stream. Do NOT load bytes into RAM.
    final result = await FilePicker.platform.pickFiles(
      withData: false,
      withReadStream: true,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    if (!mounted) return;

    final picked = result.files.single;
    final path = picked.path; // prefer file path when present
    final stream = picked.readStream; // fallback stream
    final length = picked.size; // bytes length (int)
    final filename = picked.name;

    setState(() => _busy = true);

    try {
      // STREAMING upload: no big Uint8List allocations.
      await _service.uploadFileStreaming(
        groupId: widget.groupId,
        serverFolderPath:
            _currentPath, // if your API needs a trailing slash, use:
        // _currentPath.isEmpty ? '' : '$_currentPath/'
        filename: filename,
        filePath: path, // use path if available...
        stream: path == null ? stream : null, // ...else stream
        length: path == null ? length : null, // length required for stream
      );

      // Refresh UI: try to find the new file quickly, else just reload the folder.
      DirectoryListing listing = await _load();
      _lastListing = listing;

      // If we can see it by name, refresh just that file's poster/thumb.
      try {
        final created = listing.files.firstWhere((f) => f.fileName == filename);
        await _refreshOneFile(created);
      } catch (_) {
        // fine: not visible yet or server-side indexing delay; proceed
      }

      if (!mounted) return;
      setState(() {}); // re-render list
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload complete')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// Simple PDF viewer screen (unchanged except for AppBar title using fileName).
class PdfViewerScreen extends StatefulWidget {
  final String filePath;
  final String fileName;
  const PdfViewerScreen({
    super.key,
    required this.filePath,
    required this.fileName,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  late final PdfControllerPinch _pdfController;
  @override
  void initState() {
    super.initState();
    _pdfController = PdfControllerPinch(
      document: PdfDocument.openFile(widget.filePath),
    );
  }

  @override
  void dispose() {
    _pdfController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.fileName)),
      body: PdfViewPinch(controller: _pdfController),
    );
  }
}

class _AsyncGate {
  int _inFlight = 0;
  final int max;
  final List<Completer<void>> _waiters = [];
  _AsyncGate({this.max = 2});

  Future<T> run<T>(Future<T> Function() task) async {
    if (_inFlight >= max) {
      final c = Completer<void>();
      _waiters.add(c);
      await c.future;
    }
    _inFlight++;
    try {
      return await task();
    } finally {
      _inFlight--;
      if (_waiters.isNotEmpty) {
        _waiters.removeAt(0).complete();
      }
    }
  }
}
