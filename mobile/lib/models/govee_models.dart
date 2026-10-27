import 'package:flutter/material.dart';

const String kAppVersionName = '3.3.0';
const int kAppVersionCode = 6;

const String kDefaultBackendUrl = String.fromEnvironment(
  'DEFAULT_BACKEND_URL',
  defaultValue: 'https://govee-sync.example.com',
);
const String kLanBackendUrl = String.fromEnvironment(
  'LAN_BACKEND_URL',
  defaultValue: 'http://192.168.1.100:8200',
);
const String kOwnerEmail = String.fromEnvironment(
  'OWNER_EMAIL',
  defaultValue: 'owner@example.com',
);

class ControllerConfig {
  final String id;
  final String name;
  final String ip;
  final String mac;
  final String sku;
  final int segmentCount;
  final bool enabled;
  final bool reversed;
  final String protocolMode;
  final int? brightnessOverride;

  const ControllerConfig({
    required this.id,
    required this.name,
    this.ip = '',
    this.mac = '',
    this.sku = 'H705A',
    this.segmentCount = 12,
    this.enabled = true,
    this.reversed = false,
    this.protocolMode = 'auto',
    this.brightnessOverride,
  });

  ControllerConfig copyWith({
    String? id,
    String? name,
    String? ip,
    String? mac,
    String? sku,
    int? segmentCount,
    bool? enabled,
    bool? reversed,
    String? protocolMode,
    int? brightnessOverride,
  }) {
    return ControllerConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      ip: ip ?? this.ip,
      mac: mac ?? this.mac,
      sku: sku ?? this.sku,
      segmentCount: segmentCount ?? this.segmentCount,
      enabled: enabled ?? this.enabled,
      reversed: reversed ?? this.reversed,
      protocolMode: protocolMode ?? this.protocolMode,
      brightnessOverride: brightnessOverride ?? this.brightnessOverride,
    );
  }

  factory ControllerConfig.fromJson(Map<String, dynamic> json) {
    return ControllerConfig(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Controller').toString(),
      ip: (json['ip'] ?? '').toString(),
      mac: (json['mac'] ?? '').toString(),
      sku: (json['sku'] ?? 'H705A').toString(),
      segmentCount: (json['segment_count'] is num)
          ? (json['segment_count'] as num).toInt()
          : 12,
      enabled: json['enabled'] != false,
      reversed: json['reversed'] == true,
      protocolMode: (json['protocol_mode'] ?? 'auto').toString(),
      brightnessOverride: (json['brightness_override'] is num)
          ? (json['brightness_override'] as num).toInt()
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ip': ip,
        'mac': mac,
        'sku': sku,
        'segment_count': segmentCount,
        'enabled': enabled,
        'reversed': reversed,
        'protocol_mode': protocolMode,
        'brightness_override': brightnessOverride,
      };
}

class HouseConfig {
  final String id;
  final String name;
  final int order;
  final bool enabled;
  final double timeWeight;
  final String connectionType;
  final String goveeApiKey;
  final String bridgeToken;
  final String notes;
  final List<ControllerConfig> controllers;

  const HouseConfig({
    required this.id,
    required this.name,
    this.order = 1,
    this.enabled = true,
    this.timeWeight = 1.0,
    this.connectionType = 'local_lan',
    this.goveeApiKey = '',
    this.bridgeToken = '',
    this.notes = '',
    this.controllers = const [],
  });

  int get totalSegments {
    int sum = 0;
    for (final c in controllers) {
      if (c.enabled) sum += c.segmentCount;
    }
    return sum > 0 ? sum : 9;
  }

  /// User-facing per-house speed multiplier (`0.30x` Slow .. `1.00x` Auto-Default .. `3.00x` Fast).
  /// Maps inversely to `timeWeight`: `timeWeight = 1.0 / speedMultiplier`.
  double get speedMultiplier =>
      (1.0 / timeWeight.clamp(0.1, 10.0)).clamp(0.30, 3.00);

  bool get isAutoDefaultSpeed => (timeWeight - 1.0).abs() < 0.03;

  /// Calculates the automatic segment-count compensation ratio for this house
  /// relative to the average segment count across all enabled houses.
  double autoLightCountCompensationFactor(List<HouseConfig> allHouses) {
    final active = allHouses.where((h) => h.enabled).toList();
    if (active.isEmpty) return 1.0;
    final totalSegs =
        active.fold<int>(0, (acc, h) => acc + h.totalSegments);
    if (totalSegs <= 0) return 1.0;
    final avgSegsPerHouse = totalSegs / active.length;
    final mySegs = totalSegments > 0 ? totalSegments.toDouble() : 9.0;
    return avgSegsPerHouse / mySegs;
  }

  bool get isMyHouse =>
      id == 'house-2' ||
      name.toLowerCase().contains('my house') ||
      controllers.any((c) => c.ip == '192.168.1.83' || c.sku == 'H705E');

  HouseConfig copyWith({
    String? id,
    String? name,
    int? order,
    bool? enabled,
    double? timeWeight,
    String? connectionType,
    String? goveeApiKey,
    String? bridgeToken,
    String? notes,
    List<ControllerConfig>? controllers,
  }) {
    return HouseConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      order: order ?? this.order,
      enabled: enabled ?? this.enabled,
      timeWeight: timeWeight ?? this.timeWeight,
      connectionType: connectionType ?? this.connectionType,
      goveeApiKey: goveeApiKey ?? this.goveeApiKey,
      bridgeToken: bridgeToken ?? this.bridgeToken,
      notes: notes ?? this.notes,
      controllers: controllers ?? this.controllers,
    );
  }

  factory HouseConfig.fromJson(Map<String, dynamic> json) {
    final rawCtrls = json['controllers'];
    final ctrls = <ControllerConfig>[];
    if (rawCtrls is List) {
      for (final item in rawCtrls) {
        if (item is Map<String, dynamic>) {
          ctrls.add(ControllerConfig.fromJson(item));
        } else if (item is Map) {
          ctrls.add(ControllerConfig.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return HouseConfig(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? 'House').toString(),
      order: (json['order'] is num) ? (json['order'] as num).toInt() : 1,
      enabled: json['enabled'] != false,
      timeWeight: (json['time_weight'] is num)
          ? (json['time_weight'] as num).toDouble()
          : 1.0,
      connectionType: (json['connection_type'] ?? 'local_lan').toString(),
      goveeApiKey: (json['govee_api_key'] ?? '').toString(),
      bridgeToken: (json['bridge_token'] ?? '').toString(),
      notes: (json['notes'] ?? '').toString(),
      controllers: ctrls,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'order': order,
        'enabled': enabled,
        'time_weight': timeWeight,
        'connection_type': connectionType,
        'govee_api_key': goveeApiKey,
        'bridge_token': bridgeToken,
        'notes': notes,
        'controllers': controllers.map((c) => c.toJson()).toList(),
      };
}

class AnimationConfig {
  final bool running;
  final bool blackoutOnStop;
  final String effect;
  final double speed;
  final String direction;
  final String mappingMode;
  final int fps;
  final int intensity;
  final String primaryColor;
  final String secondaryColor;
  final String accentColor;
  final String backgroundColor;
  final double backgroundDim;
  final double tailLength;
  final int pulseCount;
  final bool supersample;

  const AnimationConfig({
    this.running = true,
    this.blackoutOnStop = true,
    this.effect = 'multi_house_chase',
    this.speed = 0.25,
    this.direction = 'forward',
    this.mappingMode = 'house_normalized',
    this.fps = 25,
    this.intensity = 100,
    this.primaryColor = '#00f5d4',
    this.secondaryColor = '#7b2cbf',
    this.accentColor = '#ff007f',
    this.backgroundColor = '#060814',
    this.backgroundDim = 0.08,
    this.tailLength = 0.24,
    this.pulseCount = 1,
    this.supersample = true,
  });

  AnimationConfig copyWith({
    bool? running,
    bool? blackoutOnStop,
    String? effect,
    double? speed,
    String? direction,
    String? mappingMode,
    int? fps,
    int? intensity,
    String? primaryColor,
    String? secondaryColor,
    String? accentColor,
    String? backgroundColor,
    double? backgroundDim,
    double? tailLength,
    int? pulseCount,
    bool? supersample,
  }) {
    return AnimationConfig(
      running: running ?? this.running,
      blackoutOnStop: blackoutOnStop ?? this.blackoutOnStop,
      effect: effect ?? this.effect,
      speed: speed ?? this.speed,
      direction: direction ?? this.direction,
      mappingMode: mappingMode ?? this.mappingMode,
      fps: fps ?? this.fps,
      intensity: intensity ?? this.intensity,
      primaryColor: primaryColor ?? this.primaryColor,
      secondaryColor: secondaryColor ?? this.secondaryColor,
      accentColor: accentColor ?? this.accentColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      backgroundDim: backgroundDim ?? this.backgroundDim,
      tailLength: tailLength ?? this.tailLength,
      pulseCount: pulseCount ?? this.pulseCount,
      supersample: supersample ?? this.supersample,
    );
  }

  factory AnimationConfig.fromJson(Map<String, dynamic> json) {
    return AnimationConfig(
      running: json['running'] != false,
      blackoutOnStop: json['blackout_on_stop'] != false,
      effect: (json['effect'] ?? 'multi_house_chase').toString(),
      speed: (json['speed'] is num) ? (json['speed'] as num).toDouble() : 0.25,
      direction: (json['direction'] ?? 'forward').toString(),
      mappingMode: (json['mapping_mode'] ?? 'house_normalized').toString(),
      fps: (json['fps'] is num) ? (json['fps'] as num).toInt() : 25,
      intensity:
          (json['intensity'] is num) ? (json['intensity'] as num).toInt() : 100,
      primaryColor: (json['primary_color'] ?? '#00f5d4').toString(),
      secondaryColor: (json['secondary_color'] ?? '#7b2cbf').toString(),
      accentColor: (json['accent_color'] ?? '#ff007f').toString(),
      backgroundColor: (json['background_color'] ?? '#060814').toString(),
      backgroundDim: (json['background_dim'] is num)
          ? (json['background_dim'] as num).toDouble()
          : 0.08,
      tailLength: (json['tail_length'] is num)
          ? (json['tail_length'] as num).toDouble()
          : 0.24,
      pulseCount:
          (json['pulse_count'] is num) ? (json['pulse_count'] as num).toInt() : 1,
      supersample: json['supersample'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
        'running': running,
        'blackout_on_stop': blackoutOnStop,
        'effect': effect,
        'speed': speed,
        'direction': direction,
        'mapping_mode': mappingMode,
        'fps': fps,
        'intensity': intensity,
        'primary_color': primaryColor,
        'secondary_color': secondaryColor,
        'accent_color': accentColor,
        'background_color': backgroundColor,
        'background_dim': backgroundDim,
        'tail_length': tailLength,
        'pulse_count': pulseCount,
        'supersample': supersample,
      };
}

class PlaylistConfig {
  final bool enabled;
  final List<String> presetIds;
  final int intervalSec;

  const PlaylistConfig({
    this.enabled = false,
    this.presetIds = const [
      'cyber_chase',
      'xmas_sleigh_ride',
      'diwali_golden_diya',
      'halloween_haunted_chase',
    ],
    this.intervalSec = 60,
  });

  PlaylistConfig copyWith({
    bool? enabled,
    List<String>? presetIds,
    int? intervalSec,
  }) {
    return PlaylistConfig(
      enabled: enabled ?? this.enabled,
      presetIds: presetIds ?? this.presetIds,
      intervalSec: intervalSec ?? this.intervalSec,
    );
  }

  factory PlaylistConfig.fromJson(Map<String, dynamic> json) {
    final ids = <String>[];
    if (json['preset_ids'] is List) {
      for (final x in json['preset_ids']) {
        ids.add(x.toString());
      }
    }
    return PlaylistConfig(
      enabled: json['enabled'] == true,
      presetIds: ids.isEmpty
          ? const [
              'cyber_chase',
              'xmas_sleigh_ride',
              'diwali_golden_diya',
              'halloween_haunted_chase',
            ]
          : ids,
      intervalSec: (json['interval_sec'] is num)
          ? (json['interval_sec'] as num).toInt()
          : 60,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'preset_ids': presetIds,
        'interval_sec': intervalSec,
      };
}

class ScheduleConfig {
  final bool enabled;
  final String startTime;
  final String stopTime;
  final String presetId;
  final String timezone;
  final List<String> daysOfWeek;
  final bool turnOffLightsOnStop;
  final bool overrideGoveeAppSchedules;
  final String tzAbbrev;
  final bool dstActive;
  final String utcOffset;
  final String currentLocalTime;
  final bool isWithinActiveWindow;

  const ScheduleConfig({
    this.enabled = false,
    this.startTime = '17:30',
    this.stopTime = '23:00',
    this.presetId = 'cyber_chase',
    this.timezone = 'America/Los_Angeles',
    this.daysOfWeek = const [
      'mon',
      'tue',
      'wed',
      'thu',
      'fri',
      'sat',
      'sun',
    ],
    this.turnOffLightsOnStop = true,
    this.overrideGoveeAppSchedules = false,
    this.tzAbbrev = 'PDT',
    this.dstActive = true,
    this.utcOffset = '-07:00',
    this.currentLocalTime = '',
    this.isWithinActiveWindow = false,
  });

  static ({String ianaTimezone, String tzAbbrev, bool dstActive, String utcOffset})
      detectPhoneTimezoneInfo() {
    final now = DateTime.now();
    final rawName = now.timeZoneName.trim();
    final offsetMin = now.timeZoneOffset.inMinutes;
    final sign = offsetMin >= 0 ? '+' : '-';
    final absMin = offsetMin.abs();
    final hh = (absMin ~/ 60).toString().padLeft(2, '0');
    final mm = (absMin % 60).toString().padLeft(2, '0');
    final formattedOffset = '$sign$hh:$mm';

    final upper = rawName.toUpperCase();
    String iana = 'America/Los_Angeles';
    bool dst = upper.contains('DT') || upper.contains('SUMMER');

    if (rawName.contains('/')) {
      iana = rawName;
    } else if (upper == 'PDT' || upper == 'PST' || offsetMin == -420 || offsetMin == -480) {
      iana = 'America/Los_Angeles';
      dst = (upper == 'PDT' || offsetMin == -420);
    } else if (upper == 'MDT' || upper == 'MST' || offsetMin == -360) {
      iana = 'America/Denver';
      dst = (upper == 'MDT' || offsetMin == -360);
    } else if (upper == 'CDT' || upper == 'CST' || offsetMin == -300) {
      iana = 'America/Chicago';
      dst = (upper == 'CDT' || offsetMin == -300);
    } else if (upper == 'EDT' || upper == 'EST' || offsetMin == -240) {
      iana = 'America/New_York';
      dst = (upper == 'EDT' || offsetMin == -240);
    } else if (offsetMin == 0) {
      iana = 'UTC';
      dst = false;
    }

    final abbrev = rawName.isNotEmpty
        ? rawName
        : (iana == 'America/Los_Angeles' ? (dst ? 'PDT' : 'PST') : 'LOCAL');

    return (
      ianaTimezone: iana,
      tzAbbrev: abbrev,
      dstActive: dst,
      utcOffset: formattedOffset,
    );
  }

  ScheduleConfig copyWith({
    bool? enabled,
    String? startTime,
    String? stopTime,
    String? presetId,
    String? timezone,
    List<String>? daysOfWeek,
    bool? turnOffLightsOnStop,
    bool? overrideGoveeAppSchedules,
    String? tzAbbrev,
    bool? dstActive,
    String? utcOffset,
    String? currentLocalTime,
    bool? isWithinActiveWindow,
  }) {
    return ScheduleConfig(
      enabled: enabled ?? this.enabled,
      startTime: startTime ?? this.startTime,
      stopTime: stopTime ?? this.stopTime,
      presetId: presetId ?? this.presetId,
      timezone: timezone ?? this.timezone,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      turnOffLightsOnStop: turnOffLightsOnStop ?? this.turnOffLightsOnStop,
      overrideGoveeAppSchedules:
          overrideGoveeAppSchedules ?? this.overrideGoveeAppSchedules,
      tzAbbrev: tzAbbrev ?? this.tzAbbrev,
      dstActive: dstActive ?? this.dstActive,
      utcOffset: utcOffset ?? this.utcOffset,
      currentLocalTime: currentLocalTime ?? this.currentLocalTime,
      isWithinActiveWindow: isWithinActiveWindow ?? this.isWithinActiveWindow,
    );
  }

  factory ScheduleConfig.fromJson(Map<String, dynamic> json) {
    final days = <String>[];
    if (json['days_of_week'] is List) {
      for (final d in json['days_of_week']) {
        final s = d.toString().trim().toLowerCase();
        if (s.isNotEmpty && !days.contains(s)) {
          days.add(s.length > 3 ? s.substring(0, 3) : s);
        }
      }
    }
    final phoneInfo = detectPhoneTimezoneInfo();
    return ScheduleConfig(
      enabled: json['enabled'] == true,
      startTime: (json['start_time'] ?? '17:30').toString(),
      stopTime: (json['stop_time'] ?? '23:00').toString(),
      presetId: (json['preset_id'] ?? 'cyber_chase').toString(),
      timezone: (json['timezone'] ?? phoneInfo.ianaTimezone).toString(),
      daysOfWeek: days.isEmpty
          ? const ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun']
          : days,
      turnOffLightsOnStop: json['turn_off_lights_on_stop'] != false,
      overrideGoveeAppSchedules: json['override_govee_app_schedules'] == true,
      tzAbbrev: (json['tz_abbrev'] ?? phoneInfo.tzAbbrev).toString(),
      dstActive: json['dst_active'] is bool
          ? json['dst_active'] == true
          : phoneInfo.dstActive,
      utcOffset: (json['utc_offset'] ?? phoneInfo.utcOffset).toString(),
      currentLocalTime: (json['current_local_time'] ?? '').toString(),
      isWithinActiveWindow: json['is_within_active_window'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'start_time': startTime,
        'stop_time': stopTime,
        'preset_id': presetId,
        'timezone': timezone,
        'days_of_week': daysOfWeek,
        'turn_off_lights_on_stop': turnOffLightsOnStop,
        'override_govee_app_schedules': overrideGoveeAppSchedules,
      };
}

class SystemConfig {
  final String systemName;
  final String goveeApiKey;
  final bool lanEnabled;
  final bool cloudFallbackEnabled;
  final bool verbosePacketLogging;
  final List<HouseConfig> houses;
  final AnimationConfig animation;
  final PlaylistConfig playlist;
  final ScheduleConfig schedule;
  final List<String> authorizedEmails;

  const SystemConfig({
    this.systemName = 'Govee Multi-House Light Sync',
    this.goveeApiKey = '',
    this.lanEnabled = true,
    this.cloudFallbackEnabled = true,
    this.verbosePacketLogging = true,
    required this.houses,
    this.animation = const AnimationConfig(),
    this.playlist = const PlaylistConfig(),
    this.schedule = const ScheduleConfig(),
    this.authorizedEmails = const [kOwnerEmail],
  });

  List<HouseConfig> get sortedHouses {
    final copy = List<HouseConfig>.from(houses);
    copy.sort((a, b) {
      final cmp = a.order.compareTo(b.order);
      return cmp != 0 ? cmp : a.id.compareTo(b.id);
    });
    return copy;
  }

  SystemConfig copyWith({
    String? systemName,
    String? goveeApiKey,
    bool? lanEnabled,
    bool? cloudFallbackEnabled,
    bool? verbosePacketLogging,
    List<HouseConfig>? houses,
    AnimationConfig? animation,
    PlaylistConfig? playlist,
    ScheduleConfig? schedule,
    List<String>? authorizedEmails,
  }) {
    return SystemConfig(
      systemName: systemName ?? this.systemName,
      goveeApiKey: goveeApiKey ?? this.goveeApiKey,
      lanEnabled: lanEnabled ?? this.lanEnabled,
      cloudFallbackEnabled: cloudFallbackEnabled ?? this.cloudFallbackEnabled,
      verbosePacketLogging: verbosePacketLogging ?? this.verbosePacketLogging,
      houses: houses ?? this.houses,
      animation: animation ?? this.animation,
      playlist: playlist ?? this.playlist,
      schedule: schedule ?? this.schedule,
      authorizedEmails: authorizedEmails ?? this.authorizedEmails,
    );
  }

  factory SystemConfig.defaultThreeHouses() {
    return const SystemConfig(
      houses: [
        HouseConfig(
          id: 'house-1',
          name: 'Neighbor 1 (Left House)',
          order: 1,
          enabled: true,
          timeWeight: 1.0,
          connectionType: 'govee_cloud',
          notes:
              '2 Govee controllers across front eaves and garage (24 segments)',
          controllers: [
            ControllerConfig(
              id: 'h1-ctrl-1',
              name: 'Neighbor 1 - Left Eaves',
              mac: 'AA:BB:CC:DD:EE:02',
              sku: 'H705A',
              segmentCount: 12,
            ),
            ControllerConfig(
              id: 'h1-ctrl-2',
              name: 'Neighbor 1 - Right Garage',
              mac: 'AA:BB:CC:DD:EE:03',
              sku: 'H705A',
              segmentCount: 12,
            ),
          ],
        ),
        HouseConfig(
          id: 'house-2',
          name: 'My House (Middle - Me)',
          order: 2,
          enabled: true,
          timeWeight: 1.0,
          connectionType: 'local_lan',
          notes:
              'My Govee Outdoor Lights H705E on 192.168.1.83 (9 segments, time-compensated in middle)',
          controllers: [
            ControllerConfig(
              id: 'h2-ctrl-1',
              name: 'Govee Outdoor Lights 2 (H705E)',
              ip: '192.168.1.83',
              mac: 'AA:BB:CC:DD:EE:FF:00:02',
              sku: 'H705E',
              segmentCount: 9,
            ),
          ],
        ),
        HouseConfig(
          id: 'house-3',
          name: 'Neighbor 2 (Right House)',
          order: 3,
          enabled: true,
          timeWeight: 1.0,
          connectionType: 'govee_cloud',
          notes: '2 longer Govee H706A controllers across two-story roofline (30 segments)',
          controllers: [
            ControllerConfig(
              id: 'h3-ctrl-1',
              name: 'Neighbor 2 - Upper Peak',
              mac: 'AA:BB:CC:DD:EE:04',
              sku: 'H706A',
              segmentCount: 15,
            ),
            ControllerConfig(
              id: 'h3-ctrl-2',
              name: 'Neighbor 2 - Lower Porch',
              mac: 'AA:BB:CC:DD:EE:05',
              sku: 'H706A',
              segmentCount: 15,
            ),
          ],
        ),
      ],
    );
  }

  factory SystemConfig.fromJson(Map<String, dynamic> json) {
    final housesList = <HouseConfig>[];
    if (json['houses'] is List) {
      for (final item in json['houses']) {
        if (item is Map<String, dynamic>) {
          housesList.add(HouseConfig.fromJson(item));
        } else if (item is Map) {
          housesList.add(HouseConfig.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    final emails = <String>[];
    if (json['authorized_emails'] is List) {
      for (final em in json['authorized_emails']) {
        final s = em.toString().trim().toLowerCase();
        if (s.isNotEmpty && !emails.contains(s)) {
          emails.add(s);
        }
      }
    }
    if (!emails.contains(kOwnerEmail)) {
      emails.insert(0, kOwnerEmail);
    }

    return SystemConfig(
      systemName:
          (json['system_name'] ?? 'Govee Multi-House Light Sync').toString(),
      goveeApiKey: (json['govee_api_key'] ?? '').toString(),
      lanEnabled: json['lan_enabled'] != false,
      cloudFallbackEnabled: json['cloud_fallback_enabled'] != false,
      verbosePacketLogging: json['verbose_packet_logging'] != false,
      houses: housesList.isEmpty
          ? SystemConfig.defaultThreeHouses().houses
          : housesList,
      animation: json['animation'] is Map
          ? AnimationConfig.fromJson(
              Map<String, dynamic>.from(json['animation'] as Map))
          : const AnimationConfig(),
      playlist: json['playlist'] is Map
          ? PlaylistConfig.fromJson(
              Map<String, dynamic>.from(json['playlist'] as Map))
          : const PlaylistConfig(),
      schedule: json['schedule'] is Map
          ? ScheduleConfig.fromJson(
              Map<String, dynamic>.from(json['schedule'] as Map))
          : const ScheduleConfig(),
      authorizedEmails: emails,
    );
  }

  Map<String, dynamic> toJson() => {
        'system_name': systemName,
        'govee_api_key': goveeApiKey,
        'lan_enabled': lanEnabled,
        'cloud_fallback_enabled': cloudFallbackEnabled,
        'verbose_packet_logging': verbosePacketLogging,
        'houses': houses.map((h) => h.toJson()).toList(),
        'animation': animation.toJson(),
        'playlist': playlist.toJson(),
        'schedule': schedule.toJson(),
        'authorized_emails': authorizedEmails,
      };
}

class PresetScene {
  final String id;
  final String name;
  final String category;
  final String badge;
  final String description;
  final AnimationConfig animation;
  final bool isCustomized;

  const PresetScene({
    required this.id,
    required this.name,
    required this.category,
    required this.badge,
    required this.description,
    required this.animation,
    this.isCustomized = false,
  });

  PresetScene copyWith({
    AnimationConfig? animation,
    bool? isCustomized,
  }) {
    return PresetScene(
      id: id,
      name: name,
      category: category,
      badge: badge,
      description: description,
      animation: animation ?? this.animation,
      isCustomized: isCustomized ?? this.isCustomized,
    );
  }

  factory PresetScene.fromJson(Map<String, dynamic> json) {
    final animMap = json['animation'] is Map
        ? Map<String, dynamic>.from(json['animation'] as Map)
        : <String, dynamic>{};
    return PresetScene(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Scene').toString(),
      category: (json['category'] ?? 'Cyber & Party').toString(),
      badge: (json['badge'] ?? 'Scene').toString(),
      description: (json['description'] ?? '').toString(),
      animation: AnimationConfig.fromJson(animMap),
      isCustomized: json['is_customized'] == true,
    );
  }
}

class BurstProfile {
  final String id;
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;

  const BurstProfile({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

class AuthUser {
  final String email;
  final String name;
  final String picture;
  final String provider;
  final bool isOwner;

  const AuthUser({
    required this.email,
    this.name = '',
    this.picture = '',
    this.provider = 'google',
    this.isOwner = false,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final em = (json['email'] ?? '').toString().trim().toLowerCase();
    return AuthUser(
      email: em,
      name: (json['name'] ?? em).toString(),
      picture: (json['picture'] ?? '').toString(),
      provider: (json['provider'] ?? 'oauth').toString(),
      isOwner: json['is_owner'] == true || em == kOwnerEmail,
    );
  }
}

class AuthStatus {
  final bool authenticated;
  final AuthUser? user;
  final bool googleEnabled;
  final bool githubEnabled;
  final String owner;
  final bool authRequired;

  const AuthStatus({
    this.authenticated = false,
    this.user,
    this.googleEnabled = true,
    this.githubEnabled = true,
    this.owner = kOwnerEmail,
    this.authRequired = true,
  });

  factory AuthStatus.fromJson(Map<String, dynamic> json) {
    AuthUser? parsedUser;
    if (json['user'] is Map) {
      parsedUser =
          AuthUser.fromJson(Map<String, dynamic>.from(json['user'] as Map));
    }
    return AuthStatus(
      authenticated: json['authenticated'] == true,
      user: parsedUser,
      googleEnabled: json['google_enabled'] != false,
      githubEnabled: json['github_enabled'] != false,
      owner: (json['owner'] ?? kOwnerEmail).toString(),
      authRequired: json['auth_required'] != false,
    );
  }
}

const List<BurstProfile> kBurstProfiles = [
  BurstProfile(
    id: 'touchdown',
    label: 'Touchdown Blitz',
    subtitle: 'Center-Out Seahawks Shockwave (12s)',
    icon: Icons.sports_football,
    color: Color(0xFF69BE28),
  ),
  BurstProfile(
    id: 'strobe',
    label: 'Hyper Neon Party',
    subtitle: 'High-speed 3-house marquee blitz (12s)',
    icon: Icons.bolt,
    color: Color(0xFF00F5D4),
  ),
  BurstProfile(
    id: 'lightning',
    label: 'Megavolt Storm',
    subtitle: 'Chain lightning across all 3 roofs (12s)',
    icon: Icons.thunderstorm,
    color: Color(0xFF38BDF8),
  ),
  BurstProfile(
    id: 'new_year',
    label: 'Skyrocket Finale',
    subtitle: 'Ping-pong firework meteors (12s)',
    icon: Icons.auto_awesome,
    color: Color(0xFFFBBF24),
  ),
];

const List<PresetScene> kDefaultPresets = [
  PresetScene(
    id: "halloween_haunted_chase",
    name: "Haunted Street Phantom Chase",
    category: "Halloween",
    badge: "Spooky",
    description: "Haunted purple, toxic green, and pumpkin orange phantom orbs traveling House 1 -> 2 -> 3 with rooftop lightning flashes.",
    animation: AnimationConfig(
      effect: "halloween_spooky",
      speed: 0.26,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#9333ea",
      secondaryColor: "#22c55e",
      accentColor: "#f97316",
      backgroundColor: "#0d0417",
      backgroundDim: 0.1,
      tailLength: 0.28,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "halloween_witch_cauldron",
    name: "Witch's Cauldron & Thunder",
    category: "Halloween",
    badge: "Storm",
    description: "Bubbling toxic green cauldron mist and ultraviolet storm clouds with blood-red chain lightning jumping across houses.",
    animation: AnimationConfig(
      effect: "lightning_storm",
      speed: 0.34,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#10b981",
      secondaryColor: "#7e22ce",
      accentColor: "#ef4444",
      backgroundColor: "#06110c",
      backgroundDim: 0.12,
      tailLength: 0.25,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "halloween_blood_meteor",
    name: "Vampire Blood Moon Meteor",
    category: "Halloween",
    badge: "Gothic",
    description: "Piercing bone-white and crimson blood-moon meteors streaking across the neighborhood with smoldering ember tails.",
    animation: AnimationConfig(
      effect: "comet_meteor",
      speed: 0.3,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#dc2626",
      secondaryColor: "#ea580c",
      accentColor: "#fef2f2",
      backgroundColor: "#140303",
      backgroundDim: 0.08,
      tailLength: 0.3,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "halloween_pumpkin_marquee",
    name: "Jack-O'-Lantern Marquee",
    category: "Halloween",
    badge: "Classic",
    description: "Crisp pumpkin orange, witch purple, and lantern gold theater marquee synchronized across all three houses.",
    animation: AnimationConfig(
      effect: "theater_chase",
      speed: 0.2,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff6b00",
      secondaryColor: "#a855f7",
      accentColor: "#facc15",
      backgroundColor: "#120700",
      backgroundDim: 0.1,
      tailLength: 0.22,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "halloween_poltergeist_portal",
    name: "Poltergeist Portal (From My House)",
    category: "Halloween",
    badge: "Center-Out",
    description: "Spectral ectoplasm cyan and ghostly violet dimensional rifts erupting from My Middle House (#2) outward into both neighbors.",
    animation: AnimationConfig(
      effect: "center_out_shockwave",
      speed: 0.3,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#00f5d4",
      secondaryColor: "#9333ea",
      accentColor: "#22c55e",
      backgroundColor: "#070210",
      backgroundDim: 0.08,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "halloween_zombie_outbreak",
    name: "Zombie Biohazard Breach",
    category: "Halloween",
    badge: "Dual Snake",
    description: "Radioactive toxic-lime and hazard-yellow serpents slithering from opposite ends of the street and clashing in blood-red sparks at the middle house.",
    animation: AnimationConfig(
      effect: "cyber_snake",
      speed: 0.28,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#84cc16",
      secondaryColor: "#eab308",
      accentColor: "#dc2626",
      backgroundColor: "#050d02",
      backgroundDim: 0.09,
      tailLength: 0.25,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "halloween_frankenstein_lab",
    name: "Frankenstein's Tesla Coil Lab",
    category: "Halloween",
    badge: "High Voltage",
    description: "Crackling laboratory cyan and monster-green voltage surging down the street with blinding white-violet Jacob's Ladder arcs.",
    animation: AnimationConfig(
      effect: "lightning_storm",
      speed: 0.42,
      direction: "pingpong",
      mappingMode: "house_normalized",
      primaryColor: "#38bdf8",
      secondaryColor: "#22c55e",
      accentColor: "#e879f9",
      backgroundColor: "#020814",
      backgroundDim: 0.1,
      tailLength: 0.22,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "halloween_headless_horseman",
    name: "Gallop of the Headless Horseman",
    category: "Halloween",
    badge: "Fast Bounce",
    description: "Relentless flaming pumpkin-orange and shadow-crimson comet galloping back and forth across all three rooflines.",
    animation: AnimationConfig(
      effect: "comet_meteor",
      speed: 0.44,
      direction: "pingpong",
      mappingMode: "house_normalized",
      primaryColor: "#ff5500",
      secondaryColor: "#dc2626",
      accentColor: "#fde047",
      backgroundColor: "#0c030c",
      backgroundDim: 0.06,
      tailLength: 0.34,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "halloween_beetlejuice_sandworm",
    name: "Sandworm Graveyard Stripes",
    category: "Halloween",
    badge: "Twisted",
    description: "Hypnotic rotating neon-lime, ghost-white, and ultraviolet carnival stripes twisting continuously from house to house.",
    animation: AnimationConfig(
      effect: "christmas_magic",
      speed: 0.27,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#a855f7",
      secondaryColor: "#22c55e",
      accentColor: "#f8fafc",
      backgroundColor: "#06020a",
      backgroundDim: 0.08,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "halloween_hellfire_brimstone",
    name: "Underworld Hellfire & Brimstone",
    category: "Halloween",
    badge: "Inferno",
    description: "Roaring abyssal blood-crimson, molten magma orange, and sulfur-gold flames licking across all three houses.",
    animation: AnimationConfig(
      effect: "fire_sparkle",
      speed: 0.36,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#dc2626",
      secondaryColor: "#ea580c",
      accentColor: "#facc15",
      backgroundColor: "#140202",
      backgroundDim: 0.14,
      tailLength: 0.28,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "halloween_phantom_ghost_train",
    name: "Midnight Phantom Ghost Train",
    category: "Halloween",
    badge: "3 Carriages",
    description: "Three glowing ectoplasm-teal and spectral-blue train carriages chugging in sequence across Neighbor 1 -> My House -> Neighbor 2.",
    animation: AnimationConfig(
      effect: "multi_house_chase",
      speed: 0.22,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#2dd4bf",
      secondaryColor: "#6366f1",
      accentColor: "#c084fc",
      backgroundColor: "#030712",
      backgroundDim: 0.07,
      tailLength: 0.2,
      pulseCount: 3,
    ),
  ),
  PresetScene(
    id: "halloween_shadow_possession",
    name: "Creeping Shadow Possession Wipe",
    category: "Halloween",
    badge: "Takeover",
    description: "Slow, ominous supernatural color wipe overtaking the street in waves of pumpkin amber, cursed emerald, and midnight purple.",
    animation: AnimationConfig(
      effect: "color_wipe",
      speed: 0.2,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#f97316",
      secondaryColor: "#7e22ce",
      accentColor: "#10b981",
      backgroundColor: "#08020f",
      backgroundDim: 0.08,
      tailLength: 0.25,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "halloween_black_widow_lair",
    name: "Black Widow Venom & Webs",
    category: "Halloween",
    badge: "Venomous",
    description: "Velvet obsidian-violet spiderweb glow punctured by sudden venomous scarlet and ruby fangs across every eave.",
    animation: AnimationConfig(
      effect: "sparkle_twinkle",
      speed: 0.3,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ef4444",
      secondaryColor: "#6b21a8",
      accentColor: "#f43f5e",
      backgroundColor: "#09010d",
      backgroundDim: 0.12,
      tailLength: 0.22,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "halloween_haunted_heartbeat",
    name: "Tell-Tale Heartbeat Pulse",
    category: "Halloween",
    badge: "Lockstep",
    description: "Throbbing crimson-to-amethyst heartbeat pulsing across all three houses in eerie synchronized lockstep.",
    animation: AnimationConfig(
      effect: "breathing_pulse",
      speed: 0.32,
      direction: "forward",
      mappingMode: "parallel_zones",
      primaryColor: "#e11d48",
      secondaryColor: "#581c87",
      accentColor: "#ff6b00",
      backgroundColor: "#0a0106",
      backgroundDim: 0.08,
      tailLength: 0.25,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "halloween_candy_corn_parade",
    name: "Trick-or-Treat Candy Corn Parade",
    category: "Halloween",
    badge: "Family Fun",
    description: "Playful harvest orange, buttercup yellow, and marshmallow white tri-color wave marching down the neighborhood.",
    animation: AnimationConfig(
      effect: "multi_house_chase",
      speed: 0.25,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff7b00",
      secondaryColor: "#facc15",
      accentColor: "#ffffff",
      backgroundColor: "#140800",
      backgroundDim: 0.1,
      tailLength: 0.32,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "halloween_pharaoh_curse",
    name: "Curse of the Ancient Mummy",
    category: "Halloween",
    badge: "Mystic",
    description: "Swirling cursed sarcophagus gold, scarab emerald, and mystic violet sandstorm sweeping across all three houses.",
    animation: AnimationConfig(
      effect: "halloween_spooky",
      speed: 0.24,
      direction: "reverse",
      mappingMode: "house_normalized",
      primaryColor: "#eab308",
      secondaryColor: "#14b8a6",
      accentColor: "#a855f7",
      backgroundColor: "#120c02",
      backgroundDim: 0.1,
      tailLength: 0.28,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "halloween_rainbow1_spooky_prism",
    name: "Halloween Rainbow 1: Haunted Prism Flow",
    category: "Halloween",
    badge: "Rainbow 1 Style",
    description: "Govee Rainbow 1 style: 100%-lit seamless gradient ribbon of pumpkin orange, witch purple, toxic green, and blood crimson gliding across all 3 houses.",
    animation: AnimationConfig(
      effect: "govee_rainbow1",
      speed: 0.22,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff6b00",
      secondaryColor: "#9333ea",
      accentColor: "#22c55e",
      backgroundColor: "#e11d48",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "halloween_rainbow2_monster_blocks",
    name: "Halloween Rainbow 2: Monster Mash Blocks",
    category: "Halloween",
    badge: "Rainbow 2 Style",
    description: "Govee Rainbow 2 style: Crisp marching color blocks of carved pumpkin, ultraviolet, slime green, and bone gold stepping cleanly roof to roof.",
    animation: AnimationConfig(
      effect: "govee_rainbow2",
      speed: 0.24,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff6b00",
      secondaryColor: "#a855f7",
      accentColor: "#10b981",
      backgroundColor: "#facc15",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "halloween_rainbow1_hocus_pocus",
    name: "Halloween Rainbow 1: Sanderson Sisters Silk",
    category: "Halloween",
    badge: "Rainbow 1 Style",
    description: "Continuous gapless velvet gradient of Winifred emerald, Sarah amethyst, Mary crimson, and harvest gold flowing across the street.",
    animation: AnimationConfig(
      effect: "govee_rainbow1",
      speed: 0.2,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#10b981",
      secondaryColor: "#8b5cf6",
      accentColor: "#ef4444",
      backgroundColor: "#f59e0b",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "halloween_rainbow2_candy_corn_blocks",
    name: "Halloween Rainbow 2: Candy Corn Ribbon",
    category: "Halloween",
    badge: "Rainbow 2 Style",
    description: "Govee Rainbow 2 segmented blocks of bright candy-corn orange, lemon yellow, marshmallow white, and royal purple marching in unison.",
    animation: AnimationConfig(
      effect: "govee_rainbow2",
      speed: 0.25,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff7b00",
      secondaryColor: "#facc15",
      accentColor: "#ffffff",
      backgroundColor: "#7e22ce",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "halloween_rainbow1_ectoplasm_wave",
    name: "Halloween Rainbow 1: Ectoplasm Neon Spectrum",
    category: "Halloween",
    badge: "Rainbow 1 Style",
    description: "100%-lit supernatural neon spectrum blending ghost cyan, radioactive green, ultraviolet, and hot magenta across all 3 houses.",
    animation: AnimationConfig(
      effect: "govee_rainbow1",
      speed: 0.28,
      direction: "pingpong",
      mappingMode: "house_normalized",
      primaryColor: "#00f5d4",
      secondaryColor: "#84cc16",
      accentColor: "#9333ea",
      backgroundColor: "#ff007f",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "halloween_rainbow2_dracula_castle",
    name: "Halloween Rainbow 2: Dracula's Crimson Court",
    category: "Halloween",
    badge: "Rainbow 2 Style",
    description: "Stepped Gothic blocks of blood crimson, royal plum, candle gold, and midnight indigo gliding across every gable.",
    animation: AnimationConfig(
      effect: "govee_rainbow2",
      speed: 0.2,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#dc2626",
      secondaryColor: "#6b21a8",
      accentColor: "#fbbf24",
      backgroundColor: "#312e81",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "halloween_rainbow1_pumpkin_spice",
    name: "Halloween Rainbow 1: Harvest Moon Gradient",
    category: "Halloween",
    badge: "Rainbow 1 Style",
    description: "Warm autumn sunset gradient of harvest pumpkin, golden cider, crimson maple, and twilight violet spanning the whole block.",
    animation: AnimationConfig(
      effect: "govee_rainbow1",
      speed: 0.18,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#f97316",
      secondaryColor: "#eab308",
      accentColor: "#dc2626",
      backgroundColor: "#7c3aed",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "halloween_rainbow2_goblin_parade",
    name: "Halloween Rainbow 2: Goblin Neon Parade",
    category: "Halloween",
    badge: "Rainbow 2 Style",
    description: "High-contrast Govee Rainbow 2 bands of goblin green, electric violet, tangerine orange, and laser magenta.",
    animation: AnimationConfig(
      effect: "govee_rainbow2",
      speed: 0.3,
      direction: "pingpong",
      mappingMode: "house_normalized",
      primaryColor: "#22c55e",
      secondaryColor: "#8b5cf6",
      accentColor: "#ff6b00",
      backgroundColor: "#ec4899",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 3,
    ),
  ),
  PresetScene(
    id: "halloween_rainbow1_witches_brew",
    name: "Halloween Rainbow 1: Swirling Witches' Brew",
    category: "Halloween",
    badge: "Rainbow 1 Style",
    description: "Continuous bubbling potion gradient of emerald, teal, deep amethyst, and chartreuse flowing seamlessly house to house.",
    animation: AnimationConfig(
      effect: "govee_rainbow1",
      speed: 0.26,
      direction: "reverse",
      mappingMode: "house_normalized",
      primaryColor: "#10b981",
      secondaryColor: "#06b6d4",
      accentColor: "#9333ea",
      backgroundColor: "#a3e635",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "halloween_rainbow2_skeleton_rave",
    name: "Halloween Rainbow 2: Skeleton Dance Party",
    category: "Halloween",
    badge: "Rainbow 2 Style",
    description: "Fast, punchy Rainbow 2 color blocks of bone white, neon purple, pumpkin orange, and cyber cyan.",
    animation: AnimationConfig(
      effect: "govee_rainbow2",
      speed: 0.38,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#f8fafc",
      secondaryColor: "#a855f7",
      accentColor: "#f97316",
      backgroundColor: "#00f5d4",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 3,
    ),
  ),
  PresetScene(
    id: "halloween_rainbow1_full_spectrum",
    name: "Halloween Rainbow 1: Haunted Full Spectrum",
    category: "Halloween",
    badge: "Rainbow 1 Style",
    description: "Classic 360-degree Govee HSV Rainbow 1 spectrum gliding across all three houses with spooky dual-wave density.",
    animation: AnimationConfig(
      effect: "rainbow_wave",
      speed: 0.26,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff6b00",
      secondaryColor: "#9333ea",
      accentColor: "#22c55e",
      backgroundColor: "#000000",
      backgroundDim: 0.0,
      tailLength: 0.25,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "halloween_rainbow2_warlock_crystal",
    name: "Halloween Rainbow 2: Warlock Crystal Bands",
    category: "Halloween",
    badge: "Rainbow 2 Style",
    description: "Shimmering crystal color blocks of mystic magenta, midnight blue, toxic lime, and fiery amber.",
    animation: AnimationConfig(
      effect: "govee_rainbow2",
      speed: 0.22,
      direction: "reverse",
      mappingMode: "house_normalized",
      primaryColor: "#d946ef",
      secondaryColor: "#3b82f6",
      accentColor: "#84cc16",
      backgroundColor: "#f59e0b",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "xmas_sleigh_ride",
    name: "Santa's Sleigh Across the Street",
    category: "Christmas",
    badge: "Holiday Magic",
    description: "Rotating crimson, snow-white, and emerald candy-cane ribbons with a sparkling gold sleigh gliding House 1 -> 2 -> 3.",
    animation: AnimationConfig(
      effect: "christmas_magic",
      speed: 0.24,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ef4444",
      secondaryColor: "#10b981",
      accentColor: "#fbbf24",
      backgroundColor: "#04120a",
      backgroundDim: 0.1,
      tailLength: 0.28,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "xmas_candy_cane",
    name: "Peppermint Candy Cane Flow",
    category: "Christmas",
    badge: "Festive",
    description: "Silky candy-red, crisp snow-white, and holly-green chase flowing seamlessly from rooftop to rooftop.",
    animation: AnimationConfig(
      effect: "multi_house_chase",
      speed: 0.25,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff1744",
      secondaryColor: "#ffffff",
      accentColor: "#00e676",
      backgroundColor: "#120306",
      backgroundDim: 0.08,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "xmas_frozen_aurora",
    name: "Winter Wonderland & Falling Snow",
    category: "Christmas",
    badge: "Snowfall",
    description: "Glacier ice-blue and royal-blue northern lights with synchronized diamond-white snow sparkles across every eave.",
    animation: AnimationConfig(
      effect: "sparkle_twinkle",
      speed: 0.22,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#38bdf8",
      secondaryColor: "#f8fafc",
      accentColor: "#3b82f6",
      backgroundColor: "#020b18",
      backgroundDim: 0.1,
      tailLength: 0.24,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "xmas_nutcracker_marquee",
    name: "Nutcracker Gold & Ruby Marquee",
    category: "Christmas",
    badge: "Royal",
    description: "Warm holiday gold, ruby red, and evergreen marquee lights dancing in lockstep across all three houses.",
    animation: AnimationConfig(
      effect: "theater_chase",
      speed: 0.18,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#f59e0b",
      secondaryColor: "#dc2626",
      accentColor: "#059669",
      backgroundColor: "#140802",
      backgroundDim: 0.1,
      tailLength: 0.2,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "xmas_rudolph_dash",
    name: "Rudolph's Glowing Red-Nose Dash",
    category: "Christmas",
    badge: "Reindeer Run",
    description: "Bright cherry-red leading nose followed by golden reindeer antlers and shimmering stardust leaping from roof to roof.",
    animation: AnimationConfig(
      effect: "comet_meteor",
      speed: 0.34,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff1744",
      secondaryColor: "#fbbf24",
      accentColor: "#10b981",
      backgroundColor: "#080f08",
      backgroundDim: 0.08,
      tailLength: 0.34,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "xmas_north_pole_beacon",
    name: "North Pole Beacon (From My House)",
    category: "Christmas",
    badge: "Center-Out",
    description: "Festive candy-red, snow-white, and evergreen waves radiating outward from My Middle House (#2) to both neighbors!",
    animation: AnimationConfig(
      effect: "center_out_shockwave",
      speed: 0.25,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ef4444",
      secondaryColor: "#10b981",
      accentColor: "#ffffff",
      backgroundColor: "#041008",
      backgroundDim: 0.1,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "xmas_grinch_heist",
    name: "The Grinch Stole the Street Lights",
    category: "Christmas",
    badge: "Dual Snake",
    description: "Mischievous Grinch lime-green and Santa suit crimson snakes slithering from opposite houses and colliding in snowy sparks.",
    animation: AnimationConfig(
      effect: "cyber_snake",
      speed: 0.28,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#65a30d",
      secondaryColor: "#ef4444",
      accentColor: "#fef08a",
      backgroundColor: "#061004",
      backgroundDim: 0.08,
      tailLength: 0.25,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "xmas_polar_express",
    name: "The Polar Express Steam Train",
    category: "Christmas",
    badge: "3 Coaches",
    description: "Three warm golden-lantern passenger coaches with frost-blue steam trails chugging steadily across all three homes.",
    animation: AnimationConfig(
      effect: "multi_house_chase",
      speed: 0.2,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#f59e0b",
      secondaryColor: "#fde047",
      accentColor: "#38bdf8",
      backgroundColor: "#040814",
      backgroundDim: 0.1,
      tailLength: 0.22,
      pulseCount: 3,
    ),
  ),
  PresetScene(
    id: "xmas_gingerbread_village",
    name: "Gingerbread & Gumdrop Village",
    category: "Christmas",
    badge: "Sweet",
    description: "Warm cinnamon amber, royal icing white, and sugar-plum magenta gumdrops twinkling across the three rooflines.",
    animation: AnimationConfig(
      effect: "diwali_festival",
      speed: 0.22,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#d97706",
      secondaryColor: "#ec4899",
      accentColor: "#22c55e",
      backgroundColor: "#140904",
      backgroundDim: 0.12,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "xmas_arctic_blizzard",
    name: "Arctic Blizzard & Frostbite Gust",
    category: "Christmas",
    badge: "Snow Squall",
    description: "Swirling sub-zero cyan and cobalt wind gusts with crystalline diamond-white snow-squall flashes sweeping the street.",
    animation: AnimationConfig(
      effect: "lightning_storm",
      speed: 0.36,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#06b6d4",
      secondaryColor: "#3b82f6",
      accentColor: "#ffffff",
      backgroundColor: "#020b18",
      backgroundDim: 0.12,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "xmas_yule_log_hearth",
    name: "Cozy Christmas Eve Yule Log",
    category: "Christmas",
    badge: "Fireside",
    description: "Crackling chestnut-red, warm hearth-amber, and golden pine embers glowing across every roofline.",
    animation: AnimationConfig(
      effect: "fire_sparkle",
      speed: 0.24,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ea580c",
      secondaryColor: "#f59e0b",
      accentColor: "#fef08a",
      backgroundColor: "#140502",
      backgroundDim: 0.14,
      tailLength: 0.24,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "xmas_elf_workshop_ribbon",
    name: "Santa's Workshop Gift-Wrap Wipe",
    category: "Christmas",
    badge: "Progressive",
    description: "Playful ribbon wipe wrapping Neighbor 1 -> My House -> Neighbor 2 in alternating bows of holly red, elf green, and gold.",
    animation: AnimationConfig(
      effect: "color_wipe",
      speed: 0.22,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ef4444",
      secondaryColor: "#10b981",
      accentColor: "#fbbf24",
      backgroundColor: "#061008",
      backgroundDim: 0.08,
      tailLength: 0.25,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "xmas_star_of_bethlehem",
    name: "Star of Bethlehem Silent Night",
    category: "Christmas",
    badge: "Center Star",
    description: "Radiant celestial gold and champagne starlight shining outward from My Middle House (#2) across a midnight-blue sky.",
    animation: AnimationConfig(
      effect: "center_out_shockwave",
      speed: 0.18,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fde047",
      secondaryColor: "#f59e0b",
      accentColor: "#38bdf8",
      backgroundColor: "#020617",
      backgroundDim: 0.14,
      tailLength: 0.3,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "xmas_sugar_plum_fairy",
    name: "Dance of the Sugar Plum Fairy",
    category: "Christmas",
    badge: "Enchanted",
    description: "Whimsical lavender, rose-pink, and silver-tiara fairy dust dancing and twinkling across all three houses.",
    animation: AnimationConfig(
      effect: "sparkle_twinkle",
      speed: 0.26,
      direction: "pingpong",
      mappingMode: "house_normalized",
      primaryColor: "#c084fc",
      secondaryColor: "#f472b6",
      accentColor: "#ffffff",
      backgroundColor: "#0f0418",
      backgroundDim: 0.1,
      tailLength: 0.24,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "xmas_mistletoe_harmony",
    name: "Under the Mistletoe Harmonic Glow",
    category: "Christmas",
    badge: "Lockstep",
    description: "Deep synchronized pine-emerald and holly-berry crimson breathing glow uniting all three homes in calm holiday warmth.",
    animation: AnimationConfig(
      effect: "breathing_pulse",
      speed: 0.2,
      direction: "forward",
      mappingMode: "parallel_zones",
      primaryColor: "#10b981",
      secondaryColor: "#ef4444",
      accentColor: "#fde047",
      backgroundColor: "#041208",
      backgroundDim: 0.1,
      tailLength: 0.25,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "xmas_rainbow1_classic_C9",
    name: "Christmas Rainbow 1: Vintage C9 Bulb Flow",
    category: "Christmas",
    badge: "Rainbow 1 Style",
    description: "Govee Rainbow 1 style: 100%-lit nostalgic C9 holiday gradient of ruby red, emerald green, royal blue, and warm amber gold gliding across all 3 houses.",
    animation: AnimationConfig(
      effect: "govee_rainbow1",
      speed: 0.2,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ef4444",
      secondaryColor: "#10b981",
      accentColor: "#3b82f6",
      backgroundColor: "#f59e0b",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "xmas_rainbow2_c9_blocks",
    name: "Christmas Rainbow 2: Classic C9 Color Blocks",
    category: "Christmas",
    badge: "Rainbow 2 Style",
    description: "Govee Rainbow 2 style: Crisp marching C9 holiday blocks of cherry red, pine green, sapphire blue, and warm gold stepping cleanly roof to roof.",
    animation: AnimationConfig(
      effect: "govee_rainbow2",
      speed: 0.22,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ef4444",
      secondaryColor: "#10b981",
      accentColor: "#2563eb",
      backgroundColor: "#fbbf24",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "xmas_rainbow1_peppermint_silk",
    name: "Christmas Rainbow 1: Peppermint Ribbon Silk",
    category: "Christmas",
    badge: "Rainbow 1 Style",
    description: "Gapless, buttery-smooth Govee Rainbow 1 gradient of candy-cane red, pure snow white, holly emerald, and champagne gold.",
    animation: AnimationConfig(
      effect: "govee_rainbow1",
      speed: 0.24,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff1744",
      secondaryColor: "#ffffff",
      accentColor: "#00e676",
      backgroundColor: "#fde047",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "xmas_rainbow2_candy_shoppe",
    name: "Christmas Rainbow 2: North Pole Candy Shoppe",
    category: "Christmas",
    badge: "Rainbow 2 Style",
    description: "Vivid Govee Rainbow 2 color bands of peppermint red, frosting white, mint green, and gumdrop magenta marching across all three homes.",
    animation: AnimationConfig(
      effect: "govee_rainbow2",
      speed: 0.25,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff1744",
      secondaryColor: "#ffffff",
      accentColor: "#10b981",
      backgroundColor: "#ec4899",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 3,
    ),
  ),
  PresetScene(
    id: "xmas_rainbow1_arctic_aurora",
    name: "Christmas Rainbow 1: Lapland Aurora Ribbon",
    category: "Christmas",
    badge: "Rainbow 1 Style",
    description: "100%-lit northern lights ribbon blending glacier cyan, aurora emerald, royal sapphire, and polar violet across the street.",
    animation: AnimationConfig(
      effect: "govee_rainbow1",
      speed: 0.18,
      direction: "pingpong",
      mappingMode: "house_normalized",
      primaryColor: "#00f5d4",
      secondaryColor: "#10b981",
      accentColor: "#3b82f6",
      backgroundColor: "#8b5cf6",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "xmas_rainbow2_glacier_blocks",
    name: "Christmas Rainbow 2: Crystal Icicle Blocks",
    category: "Christmas",
    badge: "Rainbow 2 Style",
    description: "Stepped Govee Rainbow 2 blocks of diamond white, sky blue, deep cobalt, and frost teal with subtle crystal shimmer.",
    animation: AnimationConfig(
      effect: "govee_rainbow2",
      speed: 0.22,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ffffff",
      secondaryColor: "#38bdf8",
      accentColor: "#1d4ed8",
      backgroundColor: "#2dd4bf",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "xmas_rainbow1_royal_nativity",
    name: "Christmas Rainbow 1: Three Kings Royal Gold",
    category: "Christmas",
    badge: "Rainbow 1 Style",
    description: "Luxurious continuous gradient of frankincense gold, royal purple, ruby crimson, and warm starlight white.",
    animation: AnimationConfig(
      effect: "govee_rainbow1",
      speed: 0.18,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fbbf24",
      secondaryColor: "#7e22ce",
      accentColor: "#dc2626",
      backgroundColor: "#fef3c7",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "xmas_rainbow2_toy_soldier",
    name: "Christmas Rainbow 2: Toy Soldier Parade",
    category: "Christmas",
    badge: "Rainbow 2 Style",
    description: "Crisp marching Rainbow 2 blocks of regiment red, trumpet gold, uniform blue, and emerald green across all three rooflines.",
    animation: AnimationConfig(
      effect: "govee_rainbow2",
      speed: 0.26,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#dc2626",
      secondaryColor: "#facc15",
      accentColor: "#2563eb",
      backgroundColor: "#059669",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 3,
    ),
  ),
  PresetScene(
    id: "xmas_rainbow1_pastel_macaron",
    name: "Christmas Rainbow 1: Pastel Sugar-Plum Flow",
    category: "Christmas",
    badge: "Rainbow 1 Style",
    description: "Soft, dreamy Govee Rainbow 1 gradient of rose pink, lavender, mint cream, and ice blue flowing down the street.",
    animation: AnimationConfig(
      effect: "govee_rainbow1",
      speed: 0.2,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#f472b6",
      secondaryColor: "#c084fc",
      accentColor: "#6ee7b7",
      backgroundColor: "#7dd3fc",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "xmas_rainbow2_jingle_bell_rock",
    name: "Christmas Rainbow 2: Jingle Bell Rock Party",
    category: "Christmas",
    badge: "Rainbow 2 Style",
    description: "Upbeat, fast-stepping Rainbow 2 color blocks of holly red, lime green, electric cyan, and gold bouncing across the houses.",
    animation: AnimationConfig(
      effect: "govee_rainbow2",
      speed: 0.36,
      direction: "pingpong",
      mappingMode: "house_normalized",
      primaryColor: "#ef4444",
      secondaryColor: "#22c55e",
      accentColor: "#00f5d4",
      backgroundColor: "#facc15",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 3,
    ),
  ),
  PresetScene(
    id: "xmas_rainbow1_full_spectrum",
    name: "Christmas Rainbow 1: Holiday Prism Spectrum",
    category: "Christmas",
    badge: "Rainbow 1 Style",
    description: "Full 360-degree Govee Rainbow 1 HSV spectrum ribbon wrapping all three houses in continuous holiday color.",
    animation: AnimationConfig(
      effect: "rainbow_wave",
      speed: 0.22,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ef4444",
      secondaryColor: "#10b981",
      accentColor: "#fbbf24",
      backgroundColor: "#000000",
      backgroundDim: 0.0,
      tailLength: 0.25,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "xmas_rainbow2_wreath_and_holly",
    name: "Christmas Rainbow 2: Evergreen & Berry Bands",
    category: "Christmas",
    badge: "Rainbow 2 Style",
    description: "Rich Govee Rainbow 2 bands of deep forest pine, bright holly green, crimson berry, and warm candle gold.",
    animation: AnimationConfig(
      effect: "govee_rainbow2",
      speed: 0.2,
      direction: "reverse",
      mappingMode: "house_normalized",
      primaryColor: "#059669",
      secondaryColor: "#22c55e",
      accentColor: "#dc2626",
      backgroundColor: "#fbbf24",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "xmas_frost_vs_flame",
    name: "Jack Frost vs. Heat Miser Clash",
    category: "Christmas",
    badge: "Epic Clash",
    description: "Glacier ice-blue and blazing holiday-red waves racing from opposite ends of the block and bursting into gold at the middle house!",
    animation: AnimationConfig(
      effect: "cyber_snake",
      speed: 0.3,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#38bdf8",
      secondaryColor: "#ef4444",
      accentColor: "#fde047",
      backgroundColor: "#050914",
      backgroundDim: 0.08,
      tailLength: 0.26,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "diwali_golden_diya",
    name: "Golden Diya Oil Lamp Cascade",
    category: "Diwali",
    badge: "Shubh Deepavali",
    description: "Warm saffron gold, glowing amber, and vermilion diya oil-lamp shimmer cascading across all three homes.",
    animation: AnimationConfig(
      effect: "diwali_festival",
      speed: 0.22,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#f59e0b",
      secondaryColor: "#fbbf24",
      accentColor: "#ef4444",
      backgroundColor: "#170902",
      backgroundDim: 0.14,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "diwali_rangoli_wave",
    name: "Royal Rangoli Jewel Wave",
    category: "Diwali",
    badge: "Rangoli",
    description: "Vibrant rani pink, marigold orange, and peacock turquoise silk wave inspired by traditional festival rangoli art.",
    animation: AnimationConfig(
      effect: "multi_house_chase",
      speed: 0.26,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ec4899",
      secondaryColor: "#f97316",
      accentColor: "#06b6d4",
      backgroundColor: "#140410",
      backgroundDim: 0.1,
      tailLength: 0.28,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "diwali_firecracker_sparkle",
    name: "Festival of Lights Sparkle",
    category: "Diwali",
    badge: "Phuljhari",
    description: "Dazzling golden sparkler bursts over a royal magenta and violet festival wave.",
    animation: AnimationConfig(
      effect: "sparkle_twinkle",
      speed: 0.3,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fde047",
      secondaryColor: "#d946ef",
      accentColor: "#8b5cf6",
      backgroundColor: "#11051c",
      backgroundDim: 0.1,
      tailLength: 0.24,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "diwali_aarti_flame",
    name: "Sacred Aarti Flame Flow",
    category: "Diwali",
    badge: "Aarti",
    description: "Warm flickering temple flame and golden ember glow radiating across the entire street.",
    animation: AnimationConfig(
      effect: "fire_sparkle",
      speed: 0.28,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ea580c",
      secondaryColor: "#facc15",
      accentColor: "#dc2626",
      backgroundColor: "#180600",
      backgroundDim: 0.14,
      tailLength: 0.24,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "center_supernova",
    name: "Middle House Supernova Blast",
    category: "Center-Out (My House)",
    badge: "Middle -> Out",
    description: "Symmetrical neon shockwave originating at My House (#2 in the middle) and blasting outward to both neighbors simultaneously!",
    animation: AnimationConfig(
      effect: "center_out_shockwave",
      speed: 0.28,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#00f5d4",
      secondaryColor: "#8b5cf6",
      accentColor: "#ff007f",
      backgroundColor: "#050714",
      backgroundDim: 0.08,
      tailLength: 0.26,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "center_golden_ripple",
    name: "Heart of the Street Golden Ripple",
    category: "Center-Out (My House)",
    badge: "Symmetrical",
    description: "Warm golden-amber waves radiating outward from the center of My House into Neighbor 1 (Left) and Neighbor 2 (Right).",
    animation: AnimationConfig(
      effect: "center_out_shockwave",
      speed: 0.22,
      direction: "pingpong",
      mappingMode: "house_normalized",
      primaryColor: "#fbbf24",
      secondaryColor: "#f97316",
      accentColor: "#ffffff",
      backgroundColor: "#120902",
      backgroundDim: 0.1,
      tailLength: 0.28,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "center_serpent_clash",
    name: "Twin Serpent Collision at My House",
    category: "Center-Out (My House)",
    badge: "Dual Clash",
    description: "Opposing neon green and electric blue serpents racing from Neighbor 1 and Neighbor 2 to collide in a white-hot burst at My House!",
    animation: AnimationConfig(
      effect: "cyber_snake",
      speed: 0.28,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#10b981",
      secondaryColor: "#3b82f6",
      accentColor: "#f43f5e",
      backgroundColor: "#040814",
      backgroundDim: 0.08,
      tailLength: 0.24,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "cyber_chase",
    name: "Cyberpunk 3-House Chase",
    category: "Cyber & Party",
    badge: "Signature",
    description: "Silky neon cyan -> violet -> magenta chase flowing House 1 -> House 2 -> House 3 with equal-time house compensation.",
    animation: AnimationConfig(
      effect: "multi_house_chase",
      speed: 0.25,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#00f5d4",
      secondaryColor: "#7b2cbf",
      accentColor: "#ff007f",
      backgroundColor: "#060814",
      backgroundDim: 0.08,
      tailLength: 0.24,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "dual_comet_pingpong",
    name: "Twin Comet Bounce",
    category: "Cyber & Party",
    badge: "Ping-Pong",
    description: "High-energy white-hot comets bouncing back and forth across all three houses.",
    animation: AnimationConfig(
      effect: "comet_meteor",
      speed: 0.32,
      direction: "pingpong",
      mappingMode: "house_normalized",
      primaryColor: "#38bdf8",
      secondaryColor: "#6366f1",
      accentColor: "#f43f5e",
      backgroundColor: "#05070f",
      backgroundDim: 0.05,
      tailLength: 0.28,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "seamless_rainbow",
    name: "Seamless Neighborhood Rainbow",
    category: "Cyber & Party",
    badge: "Spectrum",
    description: "Continuous spectrum wave spanning all houses with zero seam or phase drift.",
    animation: AnimationConfig(
      effect: "rainbow_wave",
      speed: 0.2,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff0055",
      secondaryColor: "#00ffcc",
      accentColor: "#ffee00",
      backgroundColor: "#000000",
      backgroundDim: 0.0,
      tailLength: 0.25,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "harmonic_pulse",
    name: "Lockstep Breathing Pulse",
    category: "Cyber & Party",
    badge: "Ambient",
    description: "Deep synchronized breathing glow across all houses simultaneously.",
    animation: AnimationConfig(
      effect: "breathing_pulse",
      speed: 0.22,
      direction: "forward",
      mappingMode: "parallel_zones",
      primaryColor: "#10b981",
      secondaryColor: "#3b82f6",
      accentColor: "#8b5cf6",
      backgroundColor: "#030712",
      backgroundDim: 0.06,
      tailLength: 0.25,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "seahawks_gameday",
    name: "Seahawks 12th Man Touchdown",
    category: "Celebrations",
    badge: "Game Day",
    description: "Action Green, College Navy, and Wolf Grey stadium wave roaring across all three houses for game day!",
    animation: AnimationConfig(
      effect: "multi_house_chase",
      speed: 0.34,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#69be28",
      secondaryColor: "#002244",
      accentColor: "#a5acaf",
      backgroundColor: "#001122",
      backgroundDim: 0.12,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "july4_fireworks",
    name: "4th of July / New Year Skyrocket",
    category: "Celebrations",
    badge: "Fireworks",
    description: "Patriotic crimson, starlight white, and liberty blue skyrockets bursting across the rooflines.",
    animation: AnimationConfig(
      effect: "comet_meteor",
      speed: 0.35,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ef4444",
      secondaryColor: "#ffffff",
      accentColor: "#3b82f6",
      backgroundColor: "#040816",
      backgroundDim: 0.08,
      tailLength: 0.26,
      pulseCount: 3,
    ),
  ),
  PresetScene(
    id: "holiday_marquee",
    name: "Synchronized Theater Marquee",
    category: "Celebrations",
    badge: "Marquee",
    description: "Crisp gold & crimson marquee lights compensated for uneven controller lengths.",
    animation: AnimationConfig(
      effect: "theater_chase",
      speed: 0.18,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fbbf24",
      secondaryColor: "#ef4444",
      accentColor: "#ffffff",
      backgroundColor: "#120604",
      backgroundDim: 0.1,
      tailLength: 0.2,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "hearth_fire",
    name: "Neighborhood Bonfire",
    category: "Celebrations",
    badge: "Warm Hearth",
    description: "Organic flickering ember & flame wave across all rooflines.",
    animation: AnimationConfig(
      effect: "fire_sparkle",
      speed: 0.3,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff5500",
      secondaryColor: "#ffaa00",
      accentColor: "#ffee88",
      backgroundColor: "#140400",
      backgroundDim: 0.12,
      tailLength: 0.22,
      pulseCount: 1,
    ),
  ),
];
