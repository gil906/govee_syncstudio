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
    name: "Govee Halloween (Official)",
    category: "Halloween",
    badge: "Govee #10764",
    description: "Official Govee Halloween dynamic scene: pumpkin orange, witch purple, and eerie green chasing across segments.",
    animation: AnimationConfig(
      effect: "halloween_spooky",
      speed: 0.26,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff6b00",
      secondaryColor: "#9333ea",
      accentColor: "#22c55e",
      backgroundColor: "#0d0417",
      backgroundDim: 0.1,
      tailLength: 0.28,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "halloween_witch_cauldron",
    name: "Govee Halloween B (Official)",
    category: "Halloween",
    badge: "Govee #10765",
    description: "Official Govee Halloween B dynamic scene: bubbling cauldron green, ultraviolet purple, and ember glow.",
    animation: AnimationConfig(
      effect: "lightning_storm",
      speed: 0.34,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#10b981",
      secondaryColor: "#7e22ce",
      accentColor: "#f97316",
      backgroundColor: "#06110c",
      backgroundDim: 0.12,
      tailLength: 0.25,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "halloween_blood_meteor",
    name: "Govee Halloween D (Official)",
    category: "Halloween",
    badge: "Govee #10767",
    description: "Official Govee Halloween D dynamic scene: crimson blood red, dark amber, and bone-white flashes.",
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
    name: "Govee Halloween C (Official)",
    category: "Halloween",
    badge: "Govee #10766",
    description: "Official Govee Halloween C dynamic scene: jack-o'-lantern orange, violet, and ghostly cyan marquee.",
    animation: AnimationConfig(
      effect: "theater_chase",
      speed: 0.2,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff6b00",
      secondaryColor: "#a855f7",
      accentColor: "#06b6d4",
      backgroundColor: "#120700",
      backgroundDim: 0.1,
      tailLength: 0.22,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "halloween_poltergeist_portal",
    name: "Spooky Halloween AI (Govee DIY)",
    category: "Halloween",
    badge: "Govee DIY",
    description: "Your custom Govee DIY scene 'Spooky Halloween AI' (with Thunderstorm fallback on neighbor controllers).",
    animation: AnimationConfig(
      effect: "center_out_shockwave",
      speed: 0.3,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#9333ea",
      secondaryColor: "#00f5d4",
      accentColor: "#22c55e",
      backgroundColor: "#070210",
      backgroundDim: 0.08,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "halloween_zombie_outbreak",
    name: "Govee Halloween II (Official)",
    category: "Halloween",
    badge: "Govee #14491",
    description: "Official Govee Halloween II dynamic scene: toxic green, haunted purple, and pumpkin orange wave.",
    animation: AnimationConfig(
      effect: "cyber_snake",
      speed: 0.28,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#84cc16",
      secondaryColor: "#9333ea",
      accentColor: "#f97316",
      backgroundColor: "#050d02",
      backgroundDim: 0.09,
      tailLength: 0.25,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "halloween_frankenstein_lab",
    name: "Govee Flash (Official)",
    category: "Halloween",
    badge: "Govee #23504",
    description: "Official Govee Flash dynamic scene: high-voltage electric cyan, lime, and ultraviolet laboratory arcs.",
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
    name: "Govee Meteor (Official)",
    category: "Halloween",
    badge: "Govee #14161",
    description: "Official Govee Meteor dynamic scene: streaking fiery orange, crimson, and gold meteor tails.",
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
    name: "Govee Karst Cave (Official)",
    category: "Halloween",
    badge: "Govee #10747",
    description: "Official Govee Karst Cave dynamic scene: deep cavern purple, emerald green, and mystic teal stripes.",
    animation: AnimationConfig(
      effect: "christmas_magic",
      speed: 0.27,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#a855f7",
      secondaryColor: "#22c55e",
      accentColor: "#14b8a6",
      backgroundColor: "#06020a",
      backgroundDim: 0.08,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "halloween_hellfire_brimstone",
    name: "Govee Fire (Official)",
    category: "Halloween",
    badge: "Govee #10753",
    description: "Official Govee Fire dynamic scene: roaring crimson, flame orange, and golden ember flicker.",
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
    name: "Halloween Chasing (Govee DIY)",
    category: "Halloween",
    badge: "Govee DIY",
    description: "Your custom Govee DIY scene 'Halloween chasing' synchronized across your house and neighbor controllers.",
    animation: AnimationConfig(
      effect: "multi_house_chase",
      speed: 0.22,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff6b00",
      secondaryColor: "#9333ea",
      accentColor: "#22c55e",
      backgroundColor: "#030712",
      backgroundDim: 0.07,
      tailLength: 0.2,
      pulseCount: 3,
    ),
  ),
  PresetScene(
    id: "halloween_shadow_possession",
    name: "Orange & Purple (Govee DIY)",
    category: "Halloween",
    badge: "Govee DIY",
    description: "Your custom Govee DIY scene 'orange and purple': vivid pumpkin orange and royal purple chase.",
    animation: AnimationConfig(
      effect: "color_wipe",
      speed: 0.2,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff6b00",
      secondaryColor: "#9333ea",
      accentColor: "#a855f7",
      backgroundColor: "#08020f",
      backgroundDim: 0.08,
      tailLength: 0.25,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "halloween_black_widow_lair",
    name: "Govee Night (Official)",
    category: "Halloween",
    badge: "Govee #10795",
    description: "Official Govee Night dynamic scene: midnight indigo, deep crimson, and dark violet glow.",
    animation: AnimationConfig(
      effect: "sparkle_twinkle",
      speed: 0.3,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#6b21a8",
      secondaryColor: "#ef4444",
      accentColor: "#312e81",
      backgroundColor: "#09010d",
      backgroundDim: 0.12,
      tailLength: 0.22,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "halloween_haunted_heartbeat",
    name: "Govee Profound (Official)",
    category: "Halloween",
    badge: "Govee #10811",
    description: "Official Govee Profound dynamic scene: deep pulsing crimson, plum violet, and warm amber.",
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
    name: "Govee Fall (Official)",
    category: "Halloween",
    badge: "Govee #10757",
    description: "Official Govee Fall dynamic scene: autumn harvest orange, golden yellow, and warm amber.",
    animation: AnimationConfig(
      effect: "multi_house_chase",
      speed: 0.25,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff7b00",
      secondaryColor: "#facc15",
      accentColor: "#ea580c",
      backgroundColor: "#140800",
      backgroundDim: 0.1,
      tailLength: 0.32,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "halloween_pharaoh_curse",
    name: "Govee Sunset Glow (Official)",
    category: "Halloween",
    badge: "Govee #10739",
    description: "Official Govee Sunset Glow dynamic scene: desert gold, amber, and twilight purple.",
    animation: AnimationConfig(
      effect: "halloween_spooky",
      speed: 0.24,
      direction: "reverse",
      mappingMode: "house_normalized",
      primaryColor: "#eab308",
      secondaryColor: "#f97316",
      accentColor: "#a855f7",
      backgroundColor: "#120c02",
      backgroundDim: 0.1,
      tailLength: 0.28,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "halloween_rainbow1_spooky_prism",
    name: "Govee Rainbow (Official)",
    category: "Halloween",
    badge: "Govee #10744",
    description: "Official Govee Rainbow dynamic scene: smooth full-spectrum multi-segment rainbow wave.",
    animation: AnimationConfig(
      effect: "govee_rainbow1",
      speed: 0.22,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff0055",
      secondaryColor: "#00f5d4",
      accentColor: "#facc15",
      backgroundColor: "#e11d48",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "halloween_rainbow2_monster_blocks",
    name: "Govee Stacking (Official)",
    category: "Halloween",
    badge: "Govee #10806",
    description: "Official Govee Stacking dynamic scene: vivid color blocks stacking across the roofline.",
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
    name: "Govee Dreamlike (Official)",
    category: "Halloween",
    badge: "Govee #10815",
    description: "Official Govee Dreamlike dynamic scene: silky violet, magenta, and turquoise gradient flow.",
    animation: AnimationConfig(
      effect: "govee_rainbow1",
      speed: 0.2,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#a855f7",
      secondaryColor: "#ec4899",
      accentColor: "#06b6d4",
      backgroundColor: "#f59e0b",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "halloween_rainbow2_candy_corn_blocks",
    name: "Govee Cornfield (Official)",
    category: "Halloween",
    badge: "Govee #10749",
    description: "Official Govee Cornfield dynamic scene: golden harvest yellow, amber, and autumn green bands.",
    animation: AnimationConfig(
      effect: "govee_rainbow2",
      speed: 0.25,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#facc15",
      secondaryColor: "#f97316",
      accentColor: "#84cc16",
      backgroundColor: "#7e22ce",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "halloween_rainbow1_ectoplasm_wave",
    name: "Govee Forest (Official)",
    category: "Halloween",
    badge: "Govee #10745",
    description: "Official Govee Forest dynamic scene: lush emerald green, mint, and canopy gold wave.",
    animation: AnimationConfig(
      effect: "govee_rainbow1",
      speed: 0.28,
      direction: "pingpong",
      mappingMode: "house_normalized",
      primaryColor: "#10b981",
      secondaryColor: "#84cc16",
      accentColor: "#06b6d4",
      backgroundColor: "#ff007f",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "halloween_rainbow2_dracula_castle",
    name: "Govee Sunset (Official)",
    category: "Halloween",
    badge: "Govee #10738",
    description: "Official Govee Sunset dynamic scene: dusk crimson, fiery orange, and twilight violet.",
    animation: AnimationConfig(
      effect: "govee_rainbow2",
      speed: 0.2,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#dc2626",
      secondaryColor: "#f97316",
      accentColor: "#7e22ce",
      backgroundColor: "#312e81",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "halloween_rainbow1_pumpkin_spice",
    name: "Govee Rustling Leaves (Official)",
    category: "Halloween",
    badge: "Govee #10750",
    description: "Official Govee Rustling Leaves dynamic scene: warm amber, copper orange, and golden leaf shimmer.",
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
    name: "Govee Spin (Official)",
    category: "Halloween",
    badge: "Govee #10799",
    description: "Official Govee Spin dynamic scene: rotating multi-color carousel across all segments.",
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
    name: "Govee Twilight (Official)",
    category: "Halloween",
    badge: "Govee #10794",
    description: "Official Govee Twilight dynamic scene: evening violet, deep cyan, and magenta horizon.",
    animation: AnimationConfig(
      effect: "govee_rainbow1",
      speed: 0.26,
      direction: "reverse",
      mappingMode: "house_normalized",
      primaryColor: "#8b5cf6",
      secondaryColor: "#06b6d4",
      accentColor: "#ec4899",
      backgroundColor: "#a3e635",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "halloween_rainbow2_skeleton_rave",
    name: "Govee Dancing (Official)",
    category: "Halloween",
    badge: "Govee #10800",
    description: "Official Govee Dancing dynamic scene: upbeat rhythmic multi-color party blocks.",
    animation: AnimationConfig(
      effect: "govee_rainbow2",
      speed: 0.38,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#f43f5e",
      secondaryColor: "#a855f7",
      accentColor: "#38bdf8",
      backgroundColor: "#00f5d4",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 3,
    ),
  ),
  PresetScene(
    id: "halloween_rainbow1_full_spectrum",
    name: "Govee Gradient (Official)",
    category: "Halloween",
    badge: "Govee #10807",
    description: "Official Govee Gradient dynamic scene: seamless full-strip color-to-color gradient transition.",
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
    name: "Govee Milky Way (Official)",
    category: "Halloween",
    badge: "Govee #14159",
    description: "Official Govee Milky Way dynamic scene: cosmic starlight violet, blue, and nebula magenta.",
    animation: AnimationConfig(
      effect: "govee_rainbow2",
      speed: 0.22,
      direction: "reverse",
      mappingMode: "house_normalized",
      primaryColor: "#d946ef",
      secondaryColor: "#3b82f6",
      accentColor: "#f8fafc",
      backgroundColor: "#f59e0b",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "xmas_sleigh_ride",
    name: "Govee Sled (Official)",
    category: "Christmas",
    badge: "Govee #10763",
    description: "Official Govee Sled dynamic scene: high-speed sleigh red, icy cyan, and snow white dash.",
    animation: AnimationConfig(
      effect: "christmas_magic",
      speed: 0.24,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ef4444",
      secondaryColor: "#38bdf8",
      accentColor: "#ffffff",
      backgroundColor: "#04120a",
      backgroundDim: 0.1,
      tailLength: 0.28,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "xmas_candy_cane",
    name: "Govee Candy Cane (Official)",
    category: "Christmas",
    badge: "Govee #14165",
    description: "Official Govee Candy Cane dynamic scene: peppermint red and pure snow white stripes.",
    animation: AnimationConfig(
      effect: "multi_house_chase",
      speed: 0.25,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff1744",
      secondaryColor: "#ffffff",
      accentColor: "#ff5252",
      backgroundColor: "#120306",
      backgroundDim: 0.08,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "xmas_frozen_aurora",
    name: "Govee Winter Wonderland (Official)",
    category: "Christmas",
    badge: "Govee #10787",
    description: "Official Govee Winter Wonderland dynamic scene: sparkling ice blue, crystal white, and frost cyan.",
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
    name: "Govee Christmas (Official)",
    category: "Christmas",
    badge: "Govee #10760",
    description: "Official Govee Christmas dynamic scene: classic holiday red, evergreen, and warm gold.",
    animation: AnimationConfig(
      effect: "theater_chase",
      speed: 0.18,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ef4444",
      secondaryColor: "#10b981",
      accentColor: "#fbbf24",
      backgroundColor: "#140802",
      backgroundDim: 0.1,
      tailLength: 0.2,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "xmas_rudolph_dash",
    name: "Govee Delivering Gifts (Official)",
    category: "Christmas",
    badge: "Govee #14492",
    description: "Official Govee Delivering Gifts dynamic scene: Santa red, golden bells, and emerald green.",
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
    name: "Govee Christmas Tree (Official)",
    category: "Christmas",
    badge: "Govee #10761",
    description: "Official Govee Christmas Tree dynamic scene: pine green canopy with red and gold ornaments.",
    animation: AnimationConfig(
      effect: "center_out_shockwave",
      speed: 0.25,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#10b981",
      secondaryColor: "#ef4444",
      accentColor: "#fde047",
      backgroundColor: "#041008",
      backgroundDim: 0.1,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "xmas_grinch_heist",
    name: "Govee Leprechaun (Official)",
    category: "Christmas",
    badge: "Govee #10788",
    description: "Official Govee Leprechaun dynamic scene: vivid emerald green, lime, and shimmering gold.",
    animation: AnimationConfig(
      effect: "cyber_snake",
      speed: 0.28,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#22c55e",
      secondaryColor: "#84cc16",
      accentColor: "#facc15",
      backgroundColor: "#061004",
      backgroundDim: 0.08,
      tailLength: 0.25,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "xmas_polar_express",
    name: "Govee Winter (Official)",
    category: "Christmas",
    badge: "Govee #10758",
    description: "Official Govee Winter dynamic scene: crisp glacial blue, frost cyan, and snow white.",
    animation: AnimationConfig(
      effect: "multi_house_chase",
      speed: 0.2,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#38bdf8",
      secondaryColor: "#e0f2fe",
      accentColor: "#2563eb",
      backgroundColor: "#040814",
      backgroundDim: 0.1,
      tailLength: 0.22,
      pulseCount: 3,
    ),
  ),
  PresetScene(
    id: "xmas_gingerbread_village",
    name: "Govee Christmas Gift (Official)",
    category: "Christmas",
    badge: "Govee #10762",
    description: "Official Govee Christmas Gift dynamic scene: festive ribbon red, gold, and holly green.",
    animation: AnimationConfig(
      effect: "diwali_festival",
      speed: 0.22,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ef4444",
      secondaryColor: "#f59e0b",
      accentColor: "#22c55e",
      backgroundColor: "#140904",
      backgroundDim: 0.12,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "xmas_arctic_blizzard",
    name: "Govee Downpour (Official)",
    category: "Christmas",
    badge: "Govee #10759",
    description: "Official Govee Downpour dynamic scene: cascading ice-blue and silver-white winter flurries.",
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
    name: "Govee Warm (Official)",
    category: "Christmas",
    badge: "Govee #10816",
    description: "Official Govee Warm dynamic scene: cozy hearth amber, soft gold, and warm orange glow.",
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
    name: "Govee Children's Day (Official)",
    category: "Christmas",
    badge: "Govee #14169",
    description: "Official Govee Children's Day dynamic scene: playful toy-shop red, yellow, green, and blue.",
    animation: AnimationConfig(
      effect: "color_wipe",
      speed: 0.22,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ef4444",
      secondaryColor: "#facc15",
      accentColor: "#10b981",
      backgroundColor: "#061008",
      backgroundDim: 0.08,
      tailLength: 0.25,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "xmas_star_of_bethlehem",
    name: "Govee Christmas Eve (Official)",
    category: "Christmas",
    badge: "Govee #14166",
    description: "Official Govee Christmas Eve dynamic scene: peaceful starlight gold, warm white, and night blue.",
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
    name: "Govee Dreamland (Official)",
    category: "Christmas",
    badge: "Govee #10818",
    description: "Official Govee Dreamland dynamic scene: sugar-plum lavender, rose pink, and crystal white.",
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
    name: "Govee Christmas Wreath (Official)",
    category: "Christmas",
    badge: "Govee #14167",
    description: "Official Govee Christmas Wreath dynamic scene: evergreen holly, berry red, and warm gold.",
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
    name: "Govee Christmas Bell (Official)",
    category: "Christmas",
    badge: "Govee #14164",
    description: "Official Govee Christmas Bell dynamic scene: chiming golden bells, ruby red, and emerald.",
    animation: AnimationConfig(
      effect: "govee_rainbow1",
      speed: 0.2,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fbbf24",
      secondaryColor: "#ef4444",
      accentColor: "#10b981",
      backgroundColor: "#f59e0b",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "xmas_rainbow2_c9_blocks",
    name: "Govee Colorful (Official)",
    category: "Christmas",
    badge: "Govee #10803",
    description: "Official Govee Colorful dynamic scene: classic multi-color C9 holiday bulb blocks.",
    animation: AnimationConfig(
      effect: "govee_rainbow2",
      speed: 0.22,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ef4444",
      secondaryColor: "#10b981",
      accentColor: "#3b82f6",
      backgroundColor: "#fbbf24",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "xmas_rainbow1_peppermint_silk",
    name: "Red White Running (Govee DIY)",
    category: "Christmas",
    badge: "Govee DIY",
    description: "Your custom Govee DIY scene 'red white running' (with Candy Cane fallback on neighbor controllers).",
    animation: AnimationConfig(
      effect: "govee_rainbow1",
      speed: 0.24,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff1744",
      secondaryColor: "#ffffff",
      accentColor: "#ff5252",
      backgroundColor: "#fde047",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "xmas_rainbow2_candy_shoppe",
    name: "Govee Amusement (Official)",
    category: "Christmas",
    badge: "Govee #14172",
    description: "Official Govee Amusement dynamic scene: festive candy-shop red, cyan, yellow, and magenta.",
    animation: AnimationConfig(
      effect: "govee_rainbow2",
      speed: 0.25,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff1744",
      secondaryColor: "#00f5d4",
      accentColor: "#facc15",
      backgroundColor: "#ec4899",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 3,
    ),
  ),
  PresetScene(
    id: "xmas_rainbow1_arctic_aurora",
    name: "Govee Aurora (Official)",
    category: "Christmas",
    badge: "Govee #10746",
    description: "Official Govee Aurora dynamic scene: northern lights emerald green, cyan, and arctic violet.",
    animation: AnimationConfig(
      effect: "govee_rainbow1",
      speed: 0.18,
      direction: "pingpong",
      mappingMode: "house_normalized",
      primaryColor: "#00f5d4",
      secondaryColor: "#10b981",
      accentColor: "#8b5cf6",
      backgroundColor: "#8b5cf6",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "xmas_rainbow2_glacier_blocks",
    name: "Govee Lake (Official)",
    category: "Christmas",
    badge: "Govee #14162",
    description: "Official Govee Lake dynamic scene: rippling glacier blue, aqua, and crystal white.",
    animation: AnimationConfig(
      effect: "govee_rainbow2",
      speed: 0.22,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#38bdf8",
      secondaryColor: "#06b6d4",
      accentColor: "#ffffff",
      backgroundColor: "#2dd4bf",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "xmas_rainbow1_royal_nativity",
    name: "Govee Star (Official)",
    category: "Christmas",
    badge: "Govee #10742",
    description: "Official Govee Star dynamic scene: shimmering golden starlight and midnight sky.",
    animation: AnimationConfig(
      effect: "govee_rainbow1",
      speed: 0.18,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fbbf24",
      secondaryColor: "#fef08a",
      accentColor: "#3b82f6",
      backgroundColor: "#fef3c7",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "xmas_rainbow2_toy_soldier",
    name: "Govee Swing (Official)",
    category: "Christmas",
    badge: "Govee #10802",
    description: "Official Govee Swing dynamic scene: rhythmic pendulum of ruby red, gold, and royal blue.",
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
    name: "Govee Cherry Blossoms (Official)",
    category: "Christmas",
    badge: "Govee #10754",
    description: "Official Govee Cherry Blossoms dynamic scene: soft pastel pink, lavender, and blossom white.",
    animation: AnimationConfig(
      effect: "govee_rainbow1",
      speed: 0.2,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#f472b6",
      secondaryColor: "#e879f9",
      accentColor: "#ffffff",
      backgroundColor: "#7dd3fc",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "xmas_rainbow2_jingle_bell_rock",
    name: "Govee Music Show (Official)",
    category: "Christmas",
    badge: "Govee #14171",
    description: "Official Govee Music Show dynamic scene: energetic stage lights in red, green, and cyan.",
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
    name: "Govee Flower Parade (Official)",
    category: "Christmas",
    badge: "Govee #14174",
    description: "Official Govee Flower Parade dynamic scene: vibrant holiday parade of rose, gold, and emerald.",
    animation: AnimationConfig(
      effect: "rainbow_wave",
      speed: 0.22,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#f43f5e",
      secondaryColor: "#fbbf24",
      accentColor: "#10b981",
      backgroundColor: "#000000",
      backgroundDim: 0.0,
      tailLength: 0.25,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "xmas_rainbow2_wreath_and_holly",
    name: "Govee St. Patrick's (Official)",
    category: "Christmas",
    badge: "Govee #10783",
    description: "Official Govee Saint Patrick's Day dynamic scene: vivid shamrock green, emerald, and gold.",
    animation: AnimationConfig(
      effect: "govee_rainbow2",
      speed: 0.2,
      direction: "reverse",
      mappingMode: "house_normalized",
      primaryColor: "#059669",
      secondaryColor: "#22c55e",
      accentColor: "#facc15",
      backgroundColor: "#fbbf24",
      backgroundDim: 0.15,
      tailLength: 0.25,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "xmas_frost_vs_flame",
    name: "Govee ZDP Duo (Official)",
    category: "Christmas",
    badge: "Govee #23508",
    description: "Official Govee ZDP Duo dynamic scene: dual-tone ice blue and fiery orange contrast.",
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
    name: "Govee Candlelight (Official)",
    category: "Diwali",
    badge: "Govee #10782",
    description: "Official Govee Candlelight dynamic scene: warm flickering golden diya oil lamp glow.",
    animation: AnimationConfig(
      effect: "diwali_festival",
      speed: 0.22,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#f59e0b",
      secondaryColor: "#fbbf24",
      accentColor: "#ea580c",
      backgroundColor: "#170902",
      backgroundDim: 0.14,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "diwali_rangoli_wave",
    name: "Govee Flower Field (Official)",
    category: "Diwali",
    badge: "Govee #10751",
    description: "Official Govee Flower Field dynamic scene: vibrant rangoli magenta, marigold orange, and cyan.",
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
    name: "Govee Hooray (Official)",
    category: "Diwali",
    badge: "Govee #14175",
    description: "Official Govee Hooray dynamic scene: celebratory bursts of gold, magenta, and violet.",
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
    name: "Govee Sunrise (Official)",
    category: "Diwali",
    badge: "Govee #10737",
    description: "Official Govee Sunrise dynamic scene: sacred warm amber, saffron orange, and golden radiance.",
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
    name: "Govee Universe (Official)",
    category: "Center-Out (My House)",
    badge: "Govee #10743",
    description: "Official Govee Universe dynamic scene: deep-space cyan, galaxy purple, and neon magenta.",
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
    name: "Govee Morning (Official)",
    category: "Center-Out (My House)",
    badge: "Govee #10792",
    description: "Official Govee Morning dynamic scene: golden dawn ripple with warm white and amber.",
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
    name: "Govee ZDP Trio (Official)",
    category: "Center-Out (My House)",
    badge: "Govee #23509",
    description: "Official Govee ZDP Trio dynamic scene: triple-band emerald, electric blue, and crimson.",
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
    name: "Govee Flow (Official)",
    category: "Cyber & Party",
    badge: "Govee #10804",
    description: "Official Govee Flow dynamic scene: multi-color neon stream flowing across segments.",
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
    name: "Govee Active (Official)",
    category: "Cyber & Party",
    badge: "Govee #10819",
    description: "Official Govee Active dynamic scene: high-speed bouncing cyan, indigo, and rose pulses.",
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
    name: "Govee Enthusiastic (Official)",
    category: "Cyber & Party",
    badge: "Govee #10812",
    description: "Official Govee Enthusiastic dynamic scene: vibrant full-saturation spectrum wave.",
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
    name: "Govee Fluctuate (Official)",
    category: "Cyber & Party",
    badge: "Govee #10805",
    description: "Official Govee Fluctuate dynamic scene: synchronized breathing wave in emerald, blue, and violet.",
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
    name: "Govee Game Day (Official)",
    category: "Celebrations",
    badge: "Govee #10785",
    description: "Official Govee Game Day dynamic scene: stadium action chase in green, navy, and gold.",
    animation: AnimationConfig(
      effect: "multi_house_chase",
      speed: 0.34,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#69be28",
      secondaryColor: "#002244",
      accentColor: "#facc15",
      backgroundColor: "#001122",
      backgroundDim: 0.12,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "july4_fireworks",
    name: "Govee Fireworks (Official)",
    category: "Celebrations",
    badge: "Govee #10781",
    description: "Official Govee Fireworks dynamic scene: skyrocket bursts in red, white, and royal blue.",
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
    name: "Govee Carnival (Official)",
    category: "Celebrations",
    badge: "Govee #10776",
    description: "Official Govee Carnival dynamic scene: festive marquee in gold, crimson, and purple.",
    animation: AnimationConfig(
      effect: "theater_chase",
      speed: 0.18,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fbbf24",
      secondaryColor: "#ef4444",
      accentColor: "#a855f7",
      backgroundColor: "#120604",
      backgroundDim: 0.1,
      tailLength: 0.2,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "hearth_fire",
    name: "Govee Firefly (Official)",
    category: "Celebrations",
    badge: "Govee #10752",
    description: "Official Govee Firefly dynamic scene: warm glowing amber and golden fireflies.",
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
