import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/govee_models.dart';
import '../shaders/govee_shader.dart';

class GoveeApiService extends ChangeNotifier {
  static const String _prefBackendUrlKey = 'govee_backend_url';
  static const String _prefAuthTokenKey = 'govee_auth_token';
  static const MethodChannel _platformChannel =
      MethodChannel('com.goveesync.govee_lights_sync/platform');

  String _baseUrl = kDefaultBackendUrl;
  String _authToken = '';
  AuthStatus _authStatus = const AuthStatus();
  SystemConfig _config = SystemConfig.defaultThreeHouses();
  List<PresetScene> _presets = List<PresetScene>.from(kDefaultPresets);
  List<String> _authorizedEmails = [kOwnerEmail];

  bool _connected = false;
  bool _loading = false;
  bool _oauthPolling = false;
  String? _statusBanner;
  bool _statusIsError = false;

  double _measuredFps = 25.0;
  double _clockDriftMs = 0.0;
  String? _activePresetId = 'cyber_chase';
  bool _burstActive = false;
  String _burstLabel = '';
  double _burstRemainingSec = 0.0;
  final Map<String, List<Color>> _liveHouseColors = {};
  Map<String, String> _cloudErrors = const {};
  Map<String, Map<String, dynamic>> _activeCloudScenes = const {};

  String _latestApkVersionName = kAppVersionName;
  int _latestApkVersionCode = kAppVersionCode;
  List<Map<String, dynamic>> _apkReleases = const [];

  WebSocket? _ws;
  Timer? _pollTimer;
  Timer? _handoffTimer;
  Timer? _houseSpeedDebounce;
  bool _disposed = false;

  String get baseUrl => _baseUrl;
  String get authToken => _authToken;
  bool get hasToken => _authToken.isNotEmpty;
  AuthStatus get authStatus => _authStatus;
  SystemConfig get config => _config;
  List<PresetScene> get presets => _presets;
  List<String> get authorizedEmails => _authorizedEmails;
  bool get connected => _connected;
  bool get loading => _loading;
  bool get oauthPolling => _oauthPolling;
  String? get statusBanner => _statusBanner;
  bool get statusIsError => _statusIsError;
  double get measuredFps => _measuredFps;
  double get clockDriftMs => _clockDriftMs;
  String? get activePresetId => _activePresetId;
  bool get burstActive => _burstActive;
  String get burstLabel => _burstLabel;
  double get burstRemainingSec => _burstRemainingSec;
  Map<String, List<Color>> get liveHouseColors => _liveHouseColors;
  Map<String, String> get cloudErrors => _cloudErrors;
  Map<String, Map<String, dynamic>> get activeCloudScenes => _activeCloudScenes;

  String get installedVersionName => kAppVersionName;
  int get installedVersionCode => kAppVersionCode;
  String get latestApkVersionName => _latestApkVersionName;
  int get latestApkVersionCode => _latestApkVersionCode;
  bool get apkUpdateAvailable => _latestApkVersionCode > kAppVersionCode;
  List<Map<String, dynamic>> get apkReleases => _apkReleases;

  bool get needsSignIn =>
      _authStatus.authRequired && !_authStatus.authenticated;

  Future<void> initialize({bool enableNetwork = true}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString(_prefBackendUrlKey);
      if (savedUrl != null && savedUrl.trim().isNotEmpty) {
        _baseUrl = _cleanBaseUrl(savedUrl);
      }
      final savedToken = prefs.getString(_prefAuthTokenKey);
      if (savedToken != null && savedToken.trim().isNotEmpty) {
        _authToken = savedToken.trim();
      }
    } catch (_) {
      // Fallback for test environments without SharedPreferences plugin
    }

    _setupDeepLinkHandling();

    if (enableNetwork) {
      await refreshAll();
      _connectWebSocket();
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 6), (_) {
        refreshLiveStateSilently();
      });
    }
  }

  void _setupDeepLinkHandling() {
    _platformChannel.setMethodCallHandler((call) async {
      if (call.method == 'onDeepLink') {
        final rawLink = call.arguments?.toString() ?? '';
        if (rawLink.isNotEmpty) {
          await handleIncomingDeepLink(rawLink);
        }
      }
    });

    Future.microtask(() async {
      try {
        final initial =
            await _platformChannel.invokeMethod<String>('getInitialDeepLink');
        if (initial != null && initial.isNotEmpty) {
          await handleIncomingDeepLink(initial);
        }
      } catch (_) {}
    });
  }

  Future<void> handleIncomingDeepLink(String rawUri) async {
    try {
      final uri = Uri.parse(rawUri.trim());
      final tok =
          (uri.queryParameters['token'] ?? uri.queryParameters['auth_token'] ?? '')
              .trim();
      if (tok.isNotEmpty) {
        _handoffTimer?.cancel();
        _oauthPolling = false;
        await setAuthToken(tok);
        final email = uri.queryParameters['email'] ?? '';
        setBanner(
          email.isNotEmpty
              ? 'Signed in as $email via OAuth deep link'
              : 'Signed in via OAuth deep link',
        );
      }
    } catch (_) {}
  }

  String _cleanBaseUrl(String raw) {
    String s = raw.trim();
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'https://$s';
    }
    return s;
  }

  void setBanner(String? message, {bool isError = false}) {
    _statusBanner = message;
    _statusIsError = isError;
    _safeNotify();
  }

  Future<void> setBackendUrl(String newUrl) async {
    _baseUrl = _cleanBaseUrl(newUrl);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefBackendUrlKey, _baseUrl);
    } catch (_) {}
    setBanner('Switched endpoint to $_baseUrl');
    _ws?.close();
    _ws = null;
    await refreshAll();
    _connectWebSocket();
  }

  Future<void> setAuthToken(String token) async {
    final cleaned = token
        .trim()
        .replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '')
        .trim();
    _authToken = cleaned;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (cleaned.isEmpty) {
        await prefs.remove(_prefAuthTokenKey);
      } else {
        await prefs.setString(_prefAuthTokenKey, cleaned);
      }
    } catch (_) {}
    _ws?.close();
    _ws = null;
    await refreshAll();
    _connectWebSocket();
  }

  Future<void> launchOAuthSignIn(String provider) async {
    final rand = math.Random.secure();
    final handoffBytes = List<int>.generate(16, (_) => rand.nextInt(256));
    final handoff = handoffBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final url =
        '$_baseUrl/api/auth/$provider/login?mobile=1&redirect_scheme=${Uri.encodeComponent("goveesync://auth")}&handoff=$handoff';

    _oauthPolling = true;
    setBanner('Opening ${provider == "google" ? "Google" : "GitHub"} Sign-In…');

    try {
      await _platformChannel.invokeMethod('launchExternalUrl', {'url': url});
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
      setBanner('Copied OAuth login URL to clipboard: $url');
    }

    _startBridgePolling(handoff);
  }

  void _startBridgePolling(String handoff) {
    _handoffTimer?.cancel();
    int attempts = 0;
    _handoffTimer =
        Timer.periodic(const Duration(milliseconds: 1600), (timer) async {
      attempts++;
      if (attempts > 90 || _disposed) {
        timer.cancel();
        _oauthPolling = false;
        _safeNotify();
        return;
      }
      try {
        final res = await _httpRequest('GET', '/api/auth/bridge-poll/$handoff');
        if (res is Map && res['ready'] == true && res['token'] != null) {
          timer.cancel();
          _oauthPolling = false;
          final tok = res['token'].toString();
          await setAuthToken(tok);
          final userMap = res['user'] is Map ? res['user'] as Map : const {};
          final em = (userMap['email'] ?? '').toString();
          setBanner(
            em.isNotEmpty
                ? 'Authenticated as $em!'
                : 'Authenticated successfully!',
          );
        }
      } catch (_) {}
    });
  }

  Future<void> logout() async {
    try {
      await _httpRequest('POST', '/api/auth/logout');
    } catch (_) {}
    await setAuthToken('');
    _authStatus = AuthStatus(
      authenticated: false,
      user: null,
      googleEnabled: _authStatus.googleEnabled,
      githubEnabled: _authStatus.githubEnabled,
      owner: kOwnerEmail,
      authRequired: _authStatus.authRequired,
    );
    setBanner('Signed out of Govee Sync Studio');
  }

  Future<void> refreshAll() async {
    _loading = true;
    _safeNotify();
    try {
      final authJson = await _httpRequest('GET', '/api/auth/status');
      if (authJson is Map) {
        _authStatus = AuthStatus.fromJson(Map<String, dynamic>.from(authJson));
      }

      final presetsJson = await _httpRequest('GET', '/api/presets');
      if (presetsJson is List && presetsJson.isNotEmpty) {
        _presets = presetsJson
            .whereType<Map>()
            .map((m) => PresetScene.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      }

      final cfgJson = await _httpRequest('GET', '/api/config');
      if (cfgJson is Map) {
        _config = SystemConfig.fromJson(Map<String, dynamic>.from(cfgJson));
        _authorizedEmails = List<String>.from(_config.authorizedEmails);
      }

      final stateJson = await _httpRequest('GET', '/api/state');
      if (stateJson is Map) {
        _applyLiveSnapshot(Map<String, dynamic>.from(stateJson));
      }

      if (_authStatus.authenticated || !_authStatus.authRequired) {
        await fetchAuthorizedUsersSilently();
        await fetchApkInfoSilently();
      }

      _connected = true;
    } on _ApiHttpException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        _connected = true;
        setBanner(e.message, isError: true);
      } else {
        _connected = false;
        setBanner('Server error (${e.statusCode}): ${e.message}', isError: true);
      }
    } catch (_) {
      _connected = false;
    } finally {
      _loading = false;
      _safeNotify();
    }
  }

  Future<void> refreshLiveStateSilently() async {
    try {
      final stateJson = await _httpRequest('GET', '/api/state');
      if (stateJson is Map) {
        _applyLiveSnapshot(Map<String, dynamic>.from(stateJson));
        _connected = true;
        _safeNotify();
      }
    } catch (_) {}
  }

  void _applyLiveSnapshot(Map<String, dynamic> snap) {
    if (snap['measured_fps'] is num) {
      _measuredFps = (snap['measured_fps'] as num).toDouble();
    }
    if (snap['clock_drift_ms'] is num) {
      _clockDriftMs = (snap['clock_drift_ms'] as num).toDouble();
    }
    if (snap['active_preset_id'] != null) {
      _activePresetId = snap['active_preset_id'].toString();
    }
    if (snap['cloud_errors'] is Map) {
      _cloudErrors = (snap['cloud_errors'] as Map).map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      );
    }
    if (snap['active_cloud_scenes'] is Map) {
      final rawScenes = snap['active_cloud_scenes'] as Map;
      final parsedScenes = <String, Map<String, dynamic>>{};
      rawScenes.forEach((k, v) {
        if (v is Map) {
          parsedScenes[k.toString()] = Map<String, dynamic>.from(v);
        }
      });
      _activeCloudScenes = parsedScenes;
    }
    _burstActive = snap['burst_active'] == true;
    _burstLabel = (snap['burst_label'] ?? '').toString();
    _burstRemainingSec = (snap['burst_remaining_sec'] is num)
        ? (snap['burst_remaining_sec'] as num).toDouble()
        : 0.0;

    if (snap['config'] is Map) {
      _config = SystemConfig.fromJson(
          Map<String, dynamic>.from(snap['config'] as Map));
      _authorizedEmails = List<String>.from(_config.authorizedEmails);
    } else if (snap['running'] is bool) {
      _config = _config.copyWith(
        animation: _config.animation.copyWith(running: snap['running'] == true),
      );
    }

    final schedStatusMap = snap['schedule_status'] is Map
        ? Map<String, dynamic>.from(snap['schedule_status'] as Map)
        : (snap['schedule'] is Map
            ? Map<String, dynamic>.from(snap['schedule'] as Map)
            : null);
    if (schedStatusMap != null) {
      final mergedSched = Map<String, dynamic>.from(_config.schedule.toJson())
        ..addAll(schedStatusMap);
      _config = _config.copyWith(
        schedule: ScheduleConfig.fromJson(mergedSched),
      );
    }

    if (snap['segments'] is List) {
      final Map<String, List<Color>> grouped = {};
      for (final seg in snap['segments']) {
        if (seg is Map) {
          final hid = (seg['house_id'] ?? '').toString();
          final hex = (seg['hex_color'] ?? '#000000').toString();
          if (hid.isNotEmpty) {
            grouped.putIfAbsent(hid, () => <Color>[]).add(hexToColor(hex));
          }
        }
      }
      if (grouped.isNotEmpty) {
        _liveHouseColors
          ..clear()
          ..addAll(grouped);
      }
    }
  }

  void _connectWebSocket() async {
    if (_disposed) return;
    _ws?.close();
    _ws = null;
    try {
      String wsUrl = _baseUrl.replaceFirst('https://', 'wss://').replaceFirst('http://', 'ws://');
      wsUrl = '$wsUrl/ws/live';
      if (_authToken.isNotEmpty) {
        wsUrl = '$wsUrl?token=${Uri.encodeComponent(_authToken)}';
      }
      final socket =
          await WebSocket.connect(wsUrl).timeout(const Duration(seconds: 6));
      _ws = socket;
      _connected = true;
      _safeNotify();

      socket.listen(
        (raw) {
          try {
            final data = jsonDecode(raw.toString());
            if (data is Map) {
              _applyLiveSnapshot(Map<String, dynamic>.from(data));
              _connected = true;
              _safeNotify();
            }
          } catch (_) {}
        },
        onDone: () {
          _ws = null;
        },
        onError: (_) {
          _ws = null;
        },
      );
    } catch (_) {
      _ws = null;
    }
  }

  // --- Animation & Sync Controls ---

  Future<void> playAnimation() async {
    _config = _config.copyWith(
      animation: _config.animation.copyWith(running: true),
    );
    _safeNotify();
    try {
      await _httpRequest('POST', '/api/animation/play', body: {});
      setBanner('Master 3-House Sync Running');
      await refreshLiveStateSilently();
    } catch (e) {
      setBanner('Play error: $e', isError: true);
    }
  }

  Future<void> pauseAnimation() async {
    _config = _config.copyWith(
      animation: _config.animation.copyWith(running: false),
    );
    _safeNotify();
    try {
      await _httpRequest('POST', '/api/animation/pause', body: {});
      setBanner('Master Clock Paused (holding colors)');
    } catch (e) {
      setBanner('Pause error: $e', isError: true);
    }
  }

  Future<void> stopAndTurnOff() async {
    _config = _config.copyWith(
      animation: _config.animation.copyWith(running: false),
    );
    _liveHouseColors.clear();
    _safeNotify();
    try {
      await _httpRequest('POST', '/api/animation/stop', body: {
        'blackout_on_stop': true,
        'turn_off': true,
      });
      setBanner('Stopped Sync & Turned Off All Physical Lights');
    } catch (e) {
      setBanner('Stop error: $e', isError: true);
    }
  }

  Future<void> applyPreset(PresetScene preset) async {
    _activePresetId = preset.id;
    _config = _config.copyWith(
      animation: preset.animation.copyWith(running: true),
    );
    _liveHouseColors.clear();
    _safeNotify();
    try {
      final res = await _httpRequest('POST', '/api/presets/${preset.id}', body: {});
      if (res is Map) {
        _config = SystemConfig.fromJson(Map<String, dynamic>.from(res));
      }
      setBanner('Activated "${preset.name}" across all 3 houses');
    } catch (e) {
      setBanner('Loaded "${preset.name}" locally ($e)', isError: false);
    }
  }

  Future<void> patchAnimation(Map<String, dynamic> patch) async {
    final merged = Map<String, dynamic>.from(_config.animation.toJson())
      ..addAll(patch);
    final updatedAnim = AnimationConfig.fromJson(merged);
    _config = _config.copyWith(animation: updatedAnim);
    final activeId = _activePresetId ?? '';
    if (activeId.isNotEmpty) {
      _presets = _presets
          .map((p) => p.id == activeId
              ? p.copyWith(animation: updatedAnim, isCustomized: true)
              : p)
          .toList();
    }
    _liveHouseColors.clear();
    _safeNotify();
    try {
      final res = await _httpRequest('PATCH', '/api/animation', body: patch);
      if (res is Map) {
        final serverAnim =
            AnimationConfig.fromJson(Map<String, dynamic>.from(res));
        _config = _config.copyWith(animation: serverAnim);
        if (activeId.isNotEmpty) {
          _presets = _presets
              .map((p) => p.id == activeId
                  ? p.copyWith(animation: serverAnim, isCustomized: true)
                  : p)
              .toList();
        }
        _safeNotify();
      }
    } catch (e) {
      setBanner('Animation update error: $e', isError: true);
    }
  }

  Future<void> resetPresetDefaults(String presetId) async {
    try {
      final res = await _httpRequest('POST', '/api/presets/$presetId/reset', body: {});
      if (res is Map) {
        if (res['config'] is Map) {
          _config = SystemConfig.fromJson(
              Map<String, dynamic>.from(res['config'] as Map));
        }
        if (res['preset'] is Map) {
          final updatedPreset = PresetScene.fromJson(
              Map<String, dynamic>.from(res['preset'] as Map));
          _presets = _presets
              .map((p) => p.id == presetId ? updatedPreset : p)
              .toList();
        }
        _liveHouseColors.clear();
        _safeNotify();
        setBanner('Restored default speed & colors for scene');
      }
    } catch (e) {
      setBanner('Reset scene error: $e', isError: true);
    }
  }

  Future<void> triggerCelebrationBurst(String burstType,
      {double durationSec = 12.0}) async {
    try {
      final res = await _httpRequest('POST', '/api/animation/burst', body: {
        'type': burstType,
        'duration_sec': durationSec,
      });
      if (res is Map) {
        final label = (res['label'] ?? 'Street Celebration Burst').toString();
        _burstActive = true;
        _burstLabel = label;
        if (res['animation'] is Map) {
          _config = _config.copyWith(
            animation: AnimationConfig.fromJson(
                Map<String, dynamic>.from(res['animation'] as Map)),
          );
        }
        setBanner('⚡ Triggered $label (${durationSec.toInt()}s)');
      }
    } catch (e) {
      setBanner('Burst error: $e', isError: true);
    }
  }

  // --- Street Order & House Management ---

  Future<void> toggleHouseEnabled(String houseId, bool enabled) async {
    final updated = _config.houses
        .map((h) => h.id == houseId ? h.copyWith(enabled: enabled) : h)
        .toList();
    _config = _config.copyWith(houses: updated);
    if (!enabled) {
      _liveHouseColors.remove(houseId);
    }
    _safeNotify();
    try {
      final res = await _httpRequest(
        'PATCH',
        '/api/houses/$houseId/toggle',
        body: {'enabled': enabled},
      );
      if (res is Map) {
        if (res['config'] is Map) {
          _config = SystemConfig.fromJson(
              Map<String, dynamic>.from(res['config'] as Map));
        } else {
          _config = SystemConfig.fromJson(Map<String, dynamic>.from(res));
        }
      }
      final enabledCount =
          _config.houses.where((h) => h.enabled).length;
      setBanner(
        enabled
            ? 'Enabled house ($enabledCount active houses in sync)'
            : 'Disabled house ($enabledCount active houses in sync)',
      );
    } catch (e) {
      setBanner('Toggled house locally ($e)');
    }
  }

  Future<void> addHouse({
    required String name,
    int segmentCount = 12,
    String connectionType = 'govee_cloud',
    String sku = 'H705A',
    int controllerCount = 1,
    String goveeApiKey = '',
  }) async {
    final nextNum = _config.houses.length + 1;
    final cleanName =
        name.trim().isEmpty ? 'Neighbor $nextNum (House #$nextNum)' : name.trim();
    final newHouse = HouseConfig(
      id: 'house-$nextNum-${DateTime.now().millisecondsSinceEpoch % 1000}',
      name: cleanName,
      order: nextNum,
      enabled: true,
      connectionType: connectionType,
      goveeApiKey: goveeApiKey.trim(),
      controllers: List.generate(
        math.max(1, controllerCount),
        (i) => ControllerConfig(
          id: 'h$nextNum-ctrl-${i + 1}',
          name: '$cleanName - Strip #${i + 1} ($sku)',
          sku: sku,
          segmentCount: segmentCount,
        ),
      ),
    );
    _config = _config.copyWith(houses: [..._config.houses, newHouse]);
    _safeNotify();
    try {
      final res = await _httpRequest(
        'POST',
        '/api/houses/add',
        body: {
          'name': cleanName,
          'segment_count': segmentCount,
          'connection_type': connectionType,
          'sku': sku,
          'controller_count': controllerCount,
          'govee_api_key': goveeApiKey.trim(),
        },
      );
      if (res is Map) {
        if (res['config'] is Map) {
          _config = SystemConfig.fromJson(
              Map<String, dynamic>.from(res['config'] as Map));
        } else {
          _config = SystemConfig.fromJson(Map<String, dynamic>.from(res));
        }
      }
      setBanner('Added "$cleanName" (#${_config.houses.length} in sequence)');
    } catch (e) {
      setBanner('Added "$cleanName" locally ($e)');
    }
  }

  Future<void> deleteHouse(String houseId) async {
    if (_config.houses.length <= 1) {
      setBanner('At least 1 house must remain configured', isError: true);
      return;
    }
    final remaining = _config.houses
        .where((h) => h.id != houseId)
        .toList()
        .asMap()
        .entries
        .map((e) => e.value.copyWith(order: e.key + 1))
        .toList();
    _config = _config.copyWith(houses: remaining);
    _liveHouseColors.remove(houseId);
    _safeNotify();
    try {
      final res = await _httpRequest('DELETE', '/api/houses/$houseId');
      if (res is Map) {
        if (res['config'] is Map) {
          _config = SystemConfig.fromJson(
              Map<String, dynamic>.from(res['config'] as Map));
        } else {
          _config = SystemConfig.fromJson(Map<String, dynamic>.from(res));
        }
      }
      setBanner('Removed house (${_config.houses.length} remaining)');
    } catch (e) {
      setBanner('Removed house locally ($e)');
    }
  }

  Future<void> reorderHouses(List<String> houseIds) async {
    final mapById = {for (final h in _config.houses) h.id: h};
    final updated = <HouseConfig>[];
    for (int i = 0; i < houseIds.length; i++) {
      final h = mapById[houseIds[i]];
      if (h != null) {
        updated.add(h.copyWith(order: i + 1));
      }
    }
    if (updated.length == _config.houses.length) {
      _config = _config.copyWith(houses: updated);
      _safeNotify();
    }
    try {
      final res = await _httpRequest('POST', '/api/houses/reorder', body: {
        'house_ids': houseIds,
      });
      if (res is Map) {
        _config = SystemConfig.fromJson(Map<String, dynamic>.from(res));
      }
      setBanner('Updated 1st -> 2nd -> 3rd street house sequence');
    } catch (e) {
      setBanner('House reorder error: $e', isError: true);
    }
  }

  Future<void> saveHouses(List<HouseConfig> houses,
      {String? globalApiKey}) async {
    _config = _config.copyWith(
      houses: houses,
      goveeApiKey: globalApiKey ?? _config.goveeApiKey,
    );
    _safeNotify();
    try {
      final res =
          await _httpRequest('PUT', '/api/config', body: _config.toJson());
      if (res is Map) {
        _config = SystemConfig.fromJson(Map<String, dynamic>.from(res));
      }
      setBanner('Saved house credentials & controller settings');
    } catch (e) {
      setBanner('Save houses error: $e', isError: true);
    }
  }

  /// Adjusts a specific house's transit speed multiplier (`0.30x` Slow .. `1.00x` Auto-Default .. `3.00x` Fast).
  /// Maps inversely to `house.timeWeight = 1.0 / speedMultiplier`.
  Future<void> setHouseSpeedMultiplier(
    String houseId,
    double speedMultiplier, {
    bool immediateSave = false,
  }) async {
    final clampedSpeed = speedMultiplier.clamp(0.30, 3.00);
    final newTimeWeight =
        double.parse((1.0 / clampedSpeed).clamp(0.1, 10.0).toStringAsFixed(3));
    final updatedHouses = _config.houses
        .map((h) => h.id == houseId ? h.copyWith(timeWeight: newTimeWeight) : h)
        .toList();
    _config = _config.copyWith(houses: updatedHouses);
    _liveHouseColors.clear();
    _safeNotify();

    _houseSpeedDebounce?.cancel();
    if (immediateSave) {
      await _persistHouseSpeedUpdate(
        'Updated house speed to ${clampedSpeed.toStringAsFixed(2)}x',
      );
    } else {
      _houseSpeedDebounce =
          Timer(const Duration(milliseconds: 220), () async {
        await _persistHouseSpeedUpdate(
          'Updated house speed to ${clampedSpeed.toStringAsFixed(2)}x',
        );
      });
    }
  }

  /// Resets one house (or all houses if `houseId == null`) to `timeWeight = 1.0`
  /// (`1.00x` Auto-Default speed compensated by segment count).
  Future<void> resetHouseSpeedToAutoDefault({String? houseId}) async {
    _houseSpeedDebounce?.cancel();
    final updatedHouses = _config.houses.map((h) {
      if (houseId == null || h.id == houseId) {
        return h.copyWith(timeWeight: 1.0);
      }
      return h;
    }).toList();
    _config = _config.copyWith(houses: updatedHouses);
    _liveHouseColors.clear();
    _safeNotify();

    await _persistHouseSpeedUpdate(
      houseId == null
          ? 'Reset all houses to Auto Default Speed (compensated by light count)'
          : 'Reset house to 1.00x Auto Default Speed (by light count)',
    );
  }

  Future<void> _persistHouseSpeedUpdate(String bannerMsg) async {
    try {
      final res =
          await _httpRequest('PUT', '/api/config', body: _config.toJson());
      if (res is Map) {
        _config = SystemConfig.fromJson(Map<String, dynamic>.from(res));
        _safeNotify();
      }
      setBanner(bannerMsg);
    } catch (_) {
      setBanner(bannerMsg);
    }
  }

  Future<void> updateControllerWallZones(
    String controllerId,
    List<Map<String, dynamic>> wallZones,
  ) async {
    final updatedHouses = _config.houses.map((h) {
      final updatedCtrls = h.controllers.map((c) {
        if (c.id == controllerId) {
          return c.copyWith(wallZones: wallZones);
        }
        return c;
      }).toList();
      return h.copyWith(controllers: updatedCtrls);
    }).toList();
    _config = _config.copyWith(houses: updatedHouses);
    _safeNotify();

    try {
      final res = await _httpRequest(
        'PATCH',
        '/api/controllers/$controllerId/zones',
        body: {'wall_zones': wallZones},
      );
      if (res is Map && res['config'] is Map) {
        _config = SystemConfig.fromJson(
            Map<String, dynamic>.from(res['config'] as Map));
        _safeNotify();
      }
      setBanner('Updated 3D house wall segment split');
    } catch (e) {
      setBanner('Updated 3D wall split locally ($e)');
    }
  }

  Future<void> locateControllerSegment(
      String controllerId, int segmentIndex) async {
    try {
      await _httpRequest(
        'POST',
        '/api/controllers/$controllerId/locate-segment',
        body: {'segment_index': segmentIndex},
      );
      setBanner(
        'Spotlighted Corner Segment #${segmentIndex + 1} in White on physical house',
      );
    } catch (e) {
      setBanner('Spotlight segment error: $e', isError: true);
    }
  }

  Future<void> discoverHouseCloudDevices(String houseId, String apiKey) async {
    try {
      setBanner('Querying Govee Cloud OpenAPI for $houseId…');
      final res = await _httpRequest(
        'POST',
        '/api/houses/$houseId/discover-cloud',
        body: {
          'api_key': apiKey,
          'auto_populate': true,
        },
      );
      if (res is Map) {
        final count = res['discovered_count'] ?? 0;
        if (res['config'] is Map) {
          _config = SystemConfig.fromJson(
              Map<String, dynamic>.from(res['config'] as Map));
        } else {
          await refreshAll();
        }
        setBanner('Discovered $count Govee Cloud device(s) for $houseId');
      }
    } catch (e) {
      setBanner('Cloud discovery error: $e', isError: true);
    }
  }

  Future<void> testPhysicalLight(String controllerId,
      {String color = '#00f5d4'}) async {
    try {
      setBanner('Sending test pulse ($color) to $controllerId…');
      final res = await _httpRequest(
        'POST',
        '/api/controllers/$controllerId/test',
        body: {'color': color},
      );
      if (res is Map) {
        final ip = (res['ip'] ?? 'cloud').toString();
        setBanner('Test pulse sent to $controllerId ($ip)');
      }
    } catch (e) {
      setBanner('Test light error: $e', isError: true);
    }
  }

  // --- Pro Features: Playlist & Schedule ---

  Future<void> patchPlaylist(Map<String, dynamic> patch) async {
    final merged = Map<String, dynamic>.from(_config.playlist.toJson())
      ..addAll(patch);
    _config = _config.copyWith(playlist: PlaylistConfig.fromJson(merged));
    _safeNotify();
    try {
      final res = await _httpRequest('PATCH', '/api/playlist', body: patch);
      if (res is Map && res['config'] is Map) {
        _config = SystemConfig.fromJson(
            Map<String, dynamic>.from(res['config'] as Map));
      }
      setBanner('Updated Playlist Jukebox settings');
    } catch (e) {
      setBanner('Playlist update error: $e', isError: true);
    }
  }

  Future<void> patchSchedule(Map<String, dynamic> patch) async {
    final merged = Map<String, dynamic>.from(_config.schedule.toJson())
      ..addAll(patch);
    _config = _config.copyWith(schedule: ScheduleConfig.fromJson(merged));
    _safeNotify();
    try {
      final res = await _httpRequest('PATCH', '/api/schedule', body: patch);
      if (res is Map) {
        if (res['config'] is Map) {
          _config = SystemConfig.fromJson(
              Map<String, dynamic>.from(res['config'] as Map));
        }
        final statusMap = res['schedule_status'] is Map
            ? Map<String, dynamic>.from(res['schedule_status'] as Map)
            : (res['schedule'] is Map
                ? Map<String, dynamic>.from(res['schedule'] as Map)
                : null);
        if (statusMap != null) {
          final mergedStatus =
              Map<String, dynamic>.from(_config.schedule.toJson())
                ..addAll(statusMap);
          _config = _config.copyWith(
            schedule: ScheduleConfig.fromJson(mergedStatus),
          );
        }
        _safeNotify();
      }
      setBanner('Updated 24/7 Autonomous Container Schedule');
    } catch (e) {
      setBanner('Schedule update error: $e', isError: true);
    }
  }

  Future<void> autoDetectTimezoneAndDst() async {
    final info = ScheduleConfig.detectPhoneTimezoneInfo();
    final updated = _config.schedule.copyWith(
      timezone: info.ianaTimezone,
      tzAbbrev: info.tzAbbrev,
      dstActive: info.dstActive,
      utcOffset: info.utcOffset,
    );
    _config = _config.copyWith(schedule: updated);
    _safeNotify();
    await patchSchedule({'timezone': info.ianaTimezone});
    setBanner(
      'Auto-detected ${info.ianaTimezone} • ${info.tzAbbrev} (${info.dstActive ? "DST Active" : "Standard Time"}, UTC${info.utcOffset})',
    );
  }

  // --- Authorized Users Management ---

  Future<void> fetchAuthorizedUsersSilently() async {
    try {
      final res = await _httpRequest('GET', '/api/auth/users');
      if (res is Map && res['authorized_emails'] is List) {
        _authorizedEmails = (res['authorized_emails'] as List)
            .map((e) => e.toString().trim().toLowerCase())
            .where((e) => e.isNotEmpty)
            .toList();
        _safeNotify();
      }
    } catch (_) {}
  }

  Future<void> addAuthorizedEmail(String email) async {
    final clean = email.trim().toLowerCase();
    if (clean.isEmpty || !clean.contains('@')) {
      setBanner('Enter a valid email address', isError: true);
      return;
    }
    try {
      final res = await _httpRequest('POST', '/api/auth/users', body: {
        'email': clean,
      });
      if (res is Map && res['authorized_emails'] is List) {
        _authorizedEmails = (res['authorized_emails'] as List)
            .map((e) => e.toString())
            .toList();
      } else if (!_authorizedEmails.contains(clean)) {
        _authorizedEmails = [..._authorizedEmails, clean];
      }
      setBanner('Added $clean to authorized users');
    } catch (e) {
      setBanner('Could not add user: $e', isError: true);
    }
  }

  Future<void> removeAuthorizedEmail(String email) async {
    final clean = email.trim().toLowerCase();
    if (clean == kOwnerEmail) {
      setBanner('Owner account ($kOwnerEmail) is permanent', isError: true);
      return;
    }
    try {
      final res = await _httpRequest(
        'DELETE',
        '/api/auth/users/${Uri.encodeComponent(clean)}',
      );
      if (res is Map && res['authorized_emails'] is List) {
        _authorizedEmails = (res['authorized_emails'] as List)
            .map((e) => e.toString())
            .toList();
      } else {
        _authorizedEmails =
            _authorizedEmails.where((e) => e != clean).toList();
      }
      setBanner('Removed $clean from authorized users');
    } catch (e) {
      setBanner('Could not remove user: $e', isError: true);
    }
  }

  // --- APK Versioning, OTA Update Check & Archive Download ---

  Future<void> fetchApkInfoSilently({bool showFeedback = false}) async {
    try {
      final res = await _httpRequest('GET', '/api/apk/info');
      if (res is Map) {
        if (res['version_name'] != null) {
          _latestApkVersionName = res['version_name'].toString();
        }
        if (res['version_code'] is num) {
          _latestApkVersionCode = (res['version_code'] as num).toInt();
        }
        if (res['releases'] is List) {
          _apkReleases = (res['releases'] as List)
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList();
        }
        _safeNotify();
        if (showFeedback) {
          if (apkUpdateAvailable) {
            setBanner(
              'New APK update v$_latestApkVersionName (Build $_latestApkVersionCode) available!',
            );
          } else {
            setBanner(
              'App is up to date (v$kAppVersionName • Build $kAppVersionCode)',
            );
          }
        }
      }
    } catch (_) {
      if (showFeedback) {
        setBanner('Checked APK version (v$kAppVersionName • Build $kAppVersionCode)');
      }
    }
  }

  Future<void> downloadApkVersion({String? version}) async {
    final verParam = (version ?? '').trim();
    final qp = <String>[];
    if (verParam.isNotEmpty) {
      qp.add('version=${Uri.encodeComponent(verParam)}');
    }
    if (_authToken.isNotEmpty) {
      qp.add('token=${Uri.encodeComponent(_authToken)}');
    }
    final query = qp.isEmpty ? '' : '?${qp.join("&")}';
    final url = '$_baseUrl/api/apk/download$query';
    setBanner(
      verParam.isNotEmpty
          ? 'Downloading Govee Sync Studio APK v$verParam…'
          : 'Downloading latest Govee Sync Studio APK…',
    );
    try {
      await _platformChannel.invokeMethod('launchExternalUrl', {'url': url});
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
      setBanner('Copied APK download link to clipboard: $url');
    }
  }

  // --- Low-level HTTP helper ---

  Future<dynamic> _httpRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 7);
    try {
      final uri = Uri.parse('$_baseUrl$path');
      final req = await client.openUrl(method, uri);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (_authToken.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_authToken');
        req.headers.set('X-Auth-Token', _authToken);
      }
      if (body != null) {
        final encoded = utf8.encode(jsonEncode(body));
        req.headers.contentType = ContentType.json;
        req.headers.contentLength = encoded.length;
        req.add(encoded);
      }
      final resp = await req.close().timeout(const Duration(seconds: 10));
      final respBody = await resp.transform(utf8.decoder).join();
      dynamic decoded;
      if (respBody.isNotEmpty) {
        try {
          decoded = jsonDecode(respBody);
        } catch (_) {
          decoded = respBody;
        }
      }
      if (resp.statusCode >= 400) {
        final msg = (decoded is Map && decoded['detail'] != null)
            ? decoded['detail'].toString()
            : 'HTTP ${resp.statusCode}';
        throw _ApiHttpException(resp.statusCode, msg);
      }
      return decoded;
    } finally {
      client.close(force: false);
    }
  }

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _handoffTimer?.cancel();
    _houseSpeedDebounce?.cancel();
    _ws?.close();
    super.dispose();
  }
}

class _ApiHttpException implements Exception {
  final int statusCode;
  final String message;

  const _ApiHttpException(this.statusCode, this.message);

  @override
  String toString() => message;
}
