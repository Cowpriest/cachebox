import 'dart:convert';
import 'package:http/http.dart' as http;

class JellyfinItem {
  final String name;
  final String id;
  final bool isFolder;
  final String type;

  JellyfinItem({
    required this.name,
    required this.id,
    required this.isFolder,
    required this.type,
  });

  factory JellyfinItem.fromJson(Map<String, dynamic> json) {
    return JellyfinItem(
      name: json['Name'] ?? 'Unnamed',
      id: json['Id'] ?? '',
      isFolder: json['IsFolder'] ?? false,
      type: json['Type'] ?? 'Unknown',
    );
  }
}

class JellyfinService {
  // Singleton setup
  static final JellyfinService _instance = JellyfinService._internal();

  factory JellyfinService() {
    return _instance;
  }

  JellyfinService._internal();

  // Configuration constants
  static const String _serverUrl = 'http://cacheboxcapstone.duckdns.org:8096';
  static const String _username = 'root';
  static const String _password = 'dnstuff1';

  // Internal state
  String? _accessToken;
  String? _userId;

  // Authenticate to Jellyfin
  Future<void> login() async {
    final url = Uri.parse('$_serverUrl/Users/AuthenticateByName');

    final headers = {
      'Content-Type': 'application/json',
      'X-Emby-Authorization':
          'MediaBrowser Client="CacheBox", Device="FlutterApp", DeviceId="1234", Version="1.0.0"'
    };

    final body = jsonEncode({
      'Username': _username,
      'Pw': _password,
    });

    final response = await http.post(url, headers: headers, body: body);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      _accessToken = data['AccessToken'];
      _userId = data['User']['Id'];
      print("✅ Logged into Jellyfin. Token: $_accessToken, UserID: $_userId");
    } else {
      throw Exception('❌ Jellyfin login failed: ${response.body}');
    }
  }

  // Fetch media items for user (optionally under a parent folder)
  Future<List<JellyfinItem>> fetchItems({String? parentId}) async {
    if (_accessToken == null || _userId == null) {
      await login();
    }

    final baseUrl = '$_serverUrl/Users/$_userId/Items';
    final query = parentId != null
        ? '?ParentId=$parentId&api_key=$_accessToken'
        : '?api_key=$_accessToken';
    final url = Uri.parse('$baseUrl$query');

    final response = await http.get(url, headers: {
      'Content-Type': 'application/json',
    });

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final items = (data['Items'] as List)
          .map((item) => JellyfinItem.fromJson(item))
          .toList();
      return items;
    } else {
      throw Exception(
          '❌ Failed to fetch Jellyfin items: ${response.statusCode} ${response.body}');
    }
  }

  // Build a stream URL for media playback
// Build a stream URL for media playback with forced transcoding and metadata
  String getStreamUrl(String itemId) {
    if (_accessToken == null) throw Exception("Not authenticated");

    return '$_serverUrl/Videos/$itemId/stream.mp4'
        '?api_key=$_accessToken'
        '&Container=mp4'
        '&VideoCodec=h264'
        '&AudioCodec=aac'
        '&TranscodingContainer=mp4'
        '&TranscodingProtocol=http'
        '&Static=true';
  }
}
