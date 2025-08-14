// lib/screens/files_screen.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

import '../services/file_service.dart';
import '../services/file_model.dart';
import 'video_player_screen.dart';
import 'image_viewer_screen.dart';
import 'text_viewer_screen.dart';

class FilesScreen extends StatefulWidget {
  final String groupId;
  final String? groupName;
  final String? ownerUid;
  final List<String>? adminUids;
  const FilesScreen({
    super.key,
    required this.groupId,
    this.groupName,
    this.ownerUid,
    this.adminUids,
  });
  String joinPosix(String base, String child) =>
      base.isEmpty ? child : p.posix.join(base, child);

  String normalizePosix(String path) =>
      path.isEmpty ? '' : p.posix.normalize(path);

  @override
  State<FilesScreen> createState() => _FilesScreenState();
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

    final chevronWidth =
        hasChevron
            ? (TextPainter(
                  text: TextSpan(text: '›', style: style),
                  textDirection: TextDirection.ltr,
                )..layout()).width +
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
    // Two style presets: roomy (single-row) vs compact (two-rows)
    final baseStyle =
        Theme.of(context).textTheme.bodySmall ??
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

        final useCompact =
            estimated >
            maxWidth; // if it wouldn't fit on one row, compact everything

        final style = useCompact ? compactStyle : roomyStyle;
        final padding = useCompact ? compactPadding : roomyPadding;
        final spacing = useCompact ? 1.0 : 10.0;
        final runSpacing = useCompact ? 2.0 : 4.0;
        final density =
            useCompact
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

class _FilesScreenState extends State<FilesScreen> {
  DirectoryListing? _lastListing;
  final _service = FileService();

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
    ..sort((a, b) => a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase()));

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
    setState(() {
      // Build next path using our own join/normalize; avoid server-concatenated paths
      _currentPath = widget.normalizePosix(
        widget.joinPosix(_currentPath, folder.name),
      );
    });
  }

  void _popFolder() {
    if (_currentPath.isEmpty) return;
    final idx = _currentPath.lastIndexOf('/');
    setState(() {
      _currentPath = idx >= 0 ? _currentPath.substring(0, idx) : '';
    });
  }

  @override
  Widget build(BuildContext context) {
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
          final items = <Widget>[];

          // if (_currentPath.isNotEmpty) {
          //   items.add(
          //     ListTile(
          //       leading: const Icon(Icons.arrow_upward),
          //       title: const Text('..'),
          //       onTap: _popFolder,
          //     ),
          //   );
          // }

          // Folders
          for (final folder in listing.folders) {
            items.add(
              ListTile(
                leading: const Icon(Icons.folder),
                title: Text(Uri.decodeComponent(folder.name)),
                subtitle:
                    folder.childrenCount != null
                        ? Text('${folder.childrenCount} items')
                        : null,
                onTap: () => _pushFolder(folder),
              ),
            );
          }

          // Files
          for (final file in listing.files) {
            items.add(_buildFileTile(file));
          }

          if (items.isEmpty) {
            return const Center(child: Text('This folder is empty.'));
          }
          return ListView(children: items);
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _pickAndUpload,
        label: const Text('Upload'),
        icon: const Icon(Icons.upload),
      ),
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
    final icon = _iconForExt(ext);
    final currentUid = FirebaseAuth.instance.currentUser!.uid;
    final canDelete =
        currentUid == file.uploadedByUid ||
        currentUid == widget.ownerUid ||
        (widget.adminUids?.contains(currentUid) ?? false);
    return ListTile(
      leading: Icon(icon),
      title: Text(file.fileName),
      subtitle: Text(file.uploadedByName),
      onTap: () => _openFile(file),
      trailing:
          canDelete
              ? IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _confirmDelete(file),
              )
              : null,
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

  static const _videoExts = {'.mp4', '.mkv', '.webm', '.avi', '.mpg', '.mpeg', '.wmv', '.mov', '.flv', '.ts', '.m4v'};
static const _audioExts = {'.mp3', '.m4a', '.aac', '.wav', '.flac', '.ogg', '.oga', '.opus', '.wma', '.aiff', '.alac'};
Future<void> _openFile(FileModel file) async {
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
            builder:
                (_) =>
                    ImageViewerScreen(imageUrl: url, fileName: file.fileName),
          ),
        );
      } else if (['.mp3', '.wav', '.m4a'].contains(ext)) {
        setState(() => _busy = false);
        if (!mounted) return;
        // Route audio files to VideoPlayerScreen with folder playlist
final playlist = _buildFolderPlaylist(file, includeAudio: true, includeVideo: true);
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
final playlist = _buildFolderPlaylist(file, includeAudio: true, includeVideo: true);
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
            builder:
                (_) =>
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
            builder:
                (_) => TextViewerScreen(
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
      builder:
          (_) => AlertDialog(
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
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.single;
    final path = picked.path;
    if (path == null) return;

    setState(() => _busy = true);
    try {
      // Include folder prefix in filename so uploads land in the current folder
      final targetName =
          _currentPath.isNotEmpty
              ? widget.normalizePosix(
                widget.joinPosix(_currentPath, picked.name),
              )
              : picked.name;

      await _service.uploadFile(
        widget.groupId,
        filePath: path,
        filename: targetName,
      );

      if (!mounted) return;
      setState(() {}); // reload
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Upload complete')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
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
