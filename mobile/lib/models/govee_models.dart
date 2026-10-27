import 'package:flutter/material.dart';

const String kAppVersionName = '3.8.0';
const int kAppVersionCode = 11;

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

/// Represents one architectural roof/wall section of a house in 2D and 3D space.
class ArchSection {
  final String id;
  final String label;
  /// `'triangle_gable'`, `'steep_gable'`, `'flat_eave'`, `'hip_roof'`, `'shed_slope'`, `'dormer_peak'`
  final String shape;
  /// `'front'`, `'left'`, `'right'`, `'back'`
  final String wall;
  /// `1` or `2`
  final int story;
  final double xStart;
  final double xEnd;
  final double eaveHeight;
  final double peakHeight;
  final double peakOffset;
  final double depthOffset;
  final bool hasGarage;
  final bool hasDoor;
  final String windowStyle;

  const ArchSection({
    required this.id,
    required this.label,
    this.shape = 'triangle_gable',
    this.wall = 'front',
    this.story = 1,
    this.xStart = 0.05,
    this.xEnd = 0.95,
    this.eaveHeight = 0.50,
    this.peakHeight = 0.88,
    this.peakOffset = 0.50,
    this.depthOffset = 0.0,
    this.hasGarage = false,
    this.hasDoor = false,
    this.windowStyle = 'standard',
  });

  bool get isPitchedGable =>
      shape == 'triangle_gable' ||
      shape == 'steep_gable' ||
      shape == 'dormer_peak';

  ArchSection copyWith({
    String? id,
    String? label,
    String? shape,
    String? wall,
    int? story,
    double? xStart,
    double? xEnd,
    double? eaveHeight,
    double? peakHeight,
    double? peakOffset,
    double? depthOffset,
    bool? hasGarage,
    bool? hasDoor,
    String? windowStyle,
  }) {
    return ArchSection(
      id: id ?? this.id,
      label: label ?? this.label,
      shape: shape ?? this.shape,
      wall: wall ?? this.wall,
      story: story ?? this.story,
      xStart: xStart ?? this.xStart,
      xEnd: xEnd ?? this.xEnd,
      eaveHeight: eaveHeight ?? this.eaveHeight,
      peakHeight: peakHeight ?? this.peakHeight,
      peakOffset: peakOffset ?? this.peakOffset,
      depthOffset: depthOffset ?? this.depthOffset,
      hasGarage: hasGarage ?? this.hasGarage,
      hasDoor: hasDoor ?? this.hasDoor,
      windowStyle: windowStyle ?? this.windowStyle,
    );
  }

  factory ArchSection.fromJson(Map<String, dynamic> json) {
    final shape = (json['shape'] ?? 'triangle_gable').toString().trim();
    final eaveH = (json['eave_height'] is num)
        ? (json['eave_height'] as num).toDouble().clamp(0.20, 0.95)
        : 0.50;
    final peakH = (json['peak_height'] is num)
        ? (json['peak_height'] as num).toDouble().clamp(0.20, 1.00)
        : (shape == 'flat_eave' ? eaveH : 0.88);
    return ArchSection(
      id: (json['id'] ?? 'sec-front').toString(),
      label: (json['label'] ?? 'Roof Section').toString(),
      shape: shape,
      wall: (json['wall'] ?? 'front').toString().trim().toLowerCase(),
      story: (json['story'] is num)
          ? (json['story'] as num).toInt().clamp(1, 2)
          : 1,
      xStart: (json['x_start'] is num)
          ? (json['x_start'] as num).toDouble().clamp(0.0, 0.98)
          : 0.05,
      xEnd: (json['x_end'] is num)
          ? (json['x_end'] as num).toDouble().clamp(0.02, 1.0)
          : 0.95,
      eaveHeight: eaveH,
      peakHeight: peakH,
      peakOffset: (json['peak_offset'] is num)
          ? (json['peak_offset'] as num).toDouble().clamp(0.15, 0.85)
          : 0.50,
      depthOffset: (json['depth_offset'] is num)
          ? (json['depth_offset'] as num).toDouble().clamp(-0.40, 0.40)
          : 0.0,
      hasGarage: json['has_garage'] == true,
      hasDoor: json['has_door'] == true,
      windowStyle: (json['window_style'] ?? 'standard').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'shape': shape,
        'wall': wall,
        'story': story,
        'x_start': double.parse(xStart.toStringAsFixed(3)),
        'x_end': double.parse(xEnd.toStringAsFixed(3)),
        'eave_height': double.parse(eaveHeight.toStringAsFixed(3)),
        'peak_height': double.parse(peakHeight.toStringAsFixed(3)),
        'peak_offset': double.parse(peakOffset.toStringAsFixed(3)),
        'depth_offset': double.parse(depthOffset.toStringAsFixed(3)),
        'has_garage': hasGarage,
        'has_door': hasDoor,
        'window_style': windowStyle,
      };
}

/// Complete 3D & 2D multi-section architectural blueprint for a house.
class HouseArchitecture {
  final String presetStyle;
  final String defaultViewMode;
  final double cameraYaw;
  final double cameraPitch;
  final double cameraZoom;
  final String sidingColor;
  final String trimColor;
  final String roofColor;
  final List<ArchSection> sections;

  const HouseArchitecture({
    this.presetStyle = 'a_frame_gable',
    this.defaultViewMode = '3d',
    this.cameraYaw = -26.0,
    this.cameraPitch = 20.0,
    this.cameraZoom = 1.0,
    this.sidingColor = '#162238',
    this.trimColor = '#475569',
    this.roofColor = '#0f172a',
    this.sections = const [],
  });

  List<ArchSection> get frontSections =>
      sections.where((s) => s.wall == 'front').toList();

  HouseArchitecture copyWith({
    String? presetStyle,
    String? defaultViewMode,
    double? cameraYaw,
    double? cameraPitch,
    double? cameraZoom,
    String? sidingColor,
    String? trimColor,
    String? roofColor,
    List<ArchSection>? sections,
  }) {
    return HouseArchitecture(
      presetStyle: presetStyle ?? this.presetStyle,
      defaultViewMode: defaultViewMode ?? this.defaultViewMode,
      cameraYaw: cameraYaw ?? this.cameraYaw,
      cameraPitch: cameraPitch ?? this.cameraPitch,
      cameraZoom: cameraZoom ?? this.cameraZoom,
      sidingColor: sidingColor ?? this.sidingColor,
      trimColor: trimColor ?? this.trimColor,
      roofColor: roofColor ?? this.roofColor,
      sections: sections ?? this.sections,
    );
  }

  factory HouseArchitecture.fromJson(Map<String, dynamic> json) {
    final parsedSections = <ArchSection>[];
    if (json['sections'] is List) {
      for (final item in json['sections']) {
        if (item is Map) {
          parsedSections.add(
            ArchSection.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    final style = (json['preset_style'] ?? 'a_frame_gable').toString();
    final fallback =
        kArchitecturePresets[style] ?? kArchitecturePresets['a_frame_gable']!;
    return HouseArchitecture(
      presetStyle: style,
      defaultViewMode: (json['default_view_mode'] ?? '3d').toString(),
      cameraYaw: (json['camera_yaw'] is num)
          ? (json['camera_yaw'] as num).toDouble().clamp(-180.0, 180.0)
          : fallback.cameraYaw,
      cameraPitch: (json['camera_pitch'] is num)
          ? (json['camera_pitch'] as num).toDouble().clamp(5.0, 65.0)
          : fallback.cameraPitch,
      cameraZoom: (json['camera_zoom'] is num)
          ? (json['camera_zoom'] as num).toDouble().clamp(0.60, 2.00)
          : fallback.cameraZoom,
      sidingColor: (json['siding_color'] ?? fallback.sidingColor).toString(),
      trimColor: (json['trim_color'] ?? fallback.trimColor).toString(),
      roofColor: (json['roof_color'] ?? fallback.roofColor).toString(),
      sections: parsedSections.isNotEmpty ? parsedSections : fallback.sections,
    );
  }

  Map<String, dynamic> toJson() => {
        'preset_style': presetStyle,
        'default_view_mode': defaultViewMode,
        'camera_yaw': double.parse(cameraYaw.toStringAsFixed(1)),
        'camera_pitch': double.parse(cameraPitch.toStringAsFixed(1)),
        'camera_zoom': double.parse(cameraZoom.toStringAsFixed(2)),
        'siding_color': sidingColor,
        'trim_color': trimColor,
        'roof_color': roofColor,
        'sections': sections.map((s) => s.toJson()).toList(),
      };

  static const Map<String, HouseArchitecture> presets = kArchitecturePresets;

  /// Returns the default `HouseArchitecture` for a given `houseId` and `order`:
  /// - `house-1` / order 1 (Left Neighbor): `craftsman_multi_section`
  /// - `house-2` / order 2 (My House - Middle, Front Only): `a_frame_gable`
  /// - `house-3` / order >= 3 (Right Neighbor): `two_story_estate`
  static HouseArchitecture defaultForHouse(String houseId, int order) {
    final cleanId = houseId.trim().toLowerCase();
    if (cleanId == 'house-2') {
      return kArchitecturePresets['a_frame_gable']!;
    }
    if (cleanId == 'house-1') {
      return kArchitecturePresets['craftsman_multi_section']!;
    }
    if (cleanId == 'house-3') {
      return kArchitecturePresets['two_story_estate']!;
    }
    if (order == 1) {
      return kArchitecturePresets['craftsman_multi_section']!;
    }
    if (order == 2) {
      return kArchitecturePresets['a_frame_gable']!;
    }
    return kArchitecturePresets['two_story_estate']!;
  }
}

/// 5 built-in architectural house templates for 1-tap selection & full customization.
/// Front sections are ordered Bottom-to-Top Counter-Clockwise (1st Story LTR -> 2nd Story RTL).
const Map<String, HouseArchitecture> kArchitecturePresets = {
  // 1. House 2 (Middle — MY HOUSE, Front Only): Bottom-to-Top CCW (Lower Garage Eave LTR -> Lower Porch Peak LTR -> Upper 2nd-Story Gable RTL)
  'a_frame_gable': HouseArchitecture(
    presetStyle: 'a_frame_gable',
    defaultViewMode: '3d',
    cameraYaw: -26.0,
    cameraPitch: 20.0,
    cameraZoom: 1.0,
    sidingColor: '#1a2438',
    trimColor: '#e2e8f0',
    roofColor: '#0f172a',
    sections: [
      ArchSection(
        id: 'sec-lower-garage-eave',
        label: 'Lower Left 2-Car Garage Flat Eave',
        shape: 'flat_eave',
        wall: 'front',
        story: 1,
        xStart: 0.05,
        xEnd: 0.58,
        eaveHeight: 0.36,
        peakHeight: 0.36,
        peakOffset: 0.50,
        depthOffset: 0.16,
        hasGarage: true,
        hasDoor: false,
        windowStyle: 'modern_grid',
      ),
      ArchSection(
        id: 'sec-lower-porch-gable',
        label: 'Lower Right Covered Porch Triangle Peak',
        shape: 'triangle_gable',
        wall: 'front',
        story: 1,
        xStart: 0.58,
        xEnd: 0.96,
        eaveHeight: 0.36,
        peakHeight: 0.53,
        peakOffset: 0.50,
        depthOffset: 0.22,
        hasGarage: false,
        hasDoor: true,
        windowStyle: 'double_hung',
      ),
      ArchSection(
        id: 'sec-main-gable',
        label: 'Upper 2nd-Story Full-Width Triangle Peak (4 Windows)',
        shape: 'triangle_gable',
        wall: 'front',
        story: 2,
        xStart: 0.05,
        xEnd: 0.95,
        eaveHeight: 0.58,
        peakHeight: 0.93,
        peakOffset: 0.50,
        depthOffset: 0.04,
        hasGarage: false,
        hasDoor: false,
        windowStyle: 'picture',
      ),
    ],
  ),

  // 2. House 1 (Left Neighbor): Bottom-to-Top CCW (Lower Left Porch LTR -> Lower Right Garage LTR -> Upper Right Flat Eave RTL -> Upper Left Steep Gable RTL + Sides/Back CCW)
  'craftsman_multi_section': HouseArchitecture(
    presetStyle: 'craftsman_multi_section',
    defaultViewMode: '3d',
    cameraYaw: -26.0,
    cameraPitch: 20.0,
    cameraZoom: 1.0,
    sidingColor: '#1e293b',
    trimColor: '#cbd5e1',
    roofColor: '#0f172a',
    sections: [
      ArchSection(
        id: 'sec-entry-gable',
        label: 'Lower Left Entry Porch Eave',
        shape: 'flat_eave',
        wall: 'front',
        story: 1,
        xStart: 0.02,
        xEnd: 0.28,
        eaveHeight: 0.38,
        peakHeight: 0.38,
        peakOffset: 0.50,
        depthOffset: 0.14,
        hasDoor: true,
        hasGarage: false,
        windowStyle: 'none',
      ),
      ArchSection(
        id: 'sec-garage-square',
        label: 'Lower Right 2-Car Garage Flat Eave',
        shape: 'flat_eave',
        wall: 'front',
        story: 1,
        xStart: 0.28,
        xEnd: 0.92,
        eaveHeight: 0.38,
        peakHeight: 0.38,
        peakOffset: 0.50,
        depthOffset: 0.18,
        hasGarage: true,
        hasDoor: false,
        windowStyle: 'modern_grid',
      ),
      ArchSection(
        id: 'sec-upper-right-eave',
        label: 'Upper Right Flat Eave (1 Window)',
        shape: 'flat_eave',
        wall: 'front',
        story: 2,
        xStart: 0.58,
        xEnd: 0.96,
        eaveHeight: 0.60,
        peakHeight: 0.60,
        peakOffset: 0.50,
        depthOffset: 0.0,
        hasGarage: false,
        hasDoor: false,
        windowStyle: 'double_hung',
      ),
      ArchSection(
        id: 'sec-upper-dormer',
        label: 'Upper Left Steep Gable (3 Windows)',
        shape: 'steep_gable',
        wall: 'front',
        story: 2,
        xStart: 0.04,
        xEnd: 0.58,
        eaveHeight: 0.60,
        peakHeight: 0.95,
        peakOffset: 0.50,
        depthOffset: 0.04,
        hasGarage: false,
        hasDoor: false,
        windowStyle: 'modern_grid',
      ),
      ArchSection(
        id: 'sec-right-eave',
        label: 'Right Side Eave',
        shape: 'flat_eave',
        wall: 'right',
        story: 2,
        xStart: 0.0,
        xEnd: 1.0,
        eaveHeight: 0.58,
        peakHeight: 0.58,
      ),
      ArchSection(
        id: 'sec-back-eave',
        label: 'Rear Roofline Eave',
        shape: 'hip_roof',
        wall: 'back',
        story: 2,
        xStart: 0.0,
        xEnd: 1.0,
        eaveHeight: 0.56,
        peakHeight: 0.74,
      ),
      ArchSection(
        id: 'sec-left-eave',
        label: 'Left Side Eave',
        shape: 'flat_eave',
        wall: 'left',
        story: 2,
        xStart: 0.0,
        xEnd: 1.0,
        eaveHeight: 0.58,
        peakHeight: 0.58,
      ),
    ],
  ),

  // 3. House 3 (Right Neighbor): Bottom-to-Top CCW (Lower Full-Width Porch & Garage LTR -> Upper Right 3-Window Hip Fascia RTL -> Upper Left Recessed Dormer Nook RTL + Sides/Back CCW)
  'two_story_estate': HouseArchitecture(
    presetStyle: 'two_story_estate',
    defaultViewMode: '3d',
    cameraYaw: -26.0,
    cameraPitch: 20.0,
    cameraZoom: 1.0,
    sidingColor: '#172033',
    trimColor: '#cbd5e1',
    roofColor: '#0d1322',
    sections: [
      ArchSection(
        id: 'sec-right-garage-gable',
        label: 'Lower Full-Width Porch & Garage Flat Eave',
        shape: 'flat_eave',
        wall: 'front',
        story: 1,
        xStart: 0.04,
        xEnd: 0.98,
        eaveHeight: 0.38,
        peakHeight: 0.38,
        peakOffset: 0.50,
        depthOffset: 0.18,
        hasGarage: true,
        hasDoor: true,
        windowStyle: 'modern_grid',
      ),
      ArchSection(
        id: 'sec-center-flat-fascia',
        label: 'Upper Right 3-Window Hip Fascia',
        shape: 'flat_eave',
        wall: 'front',
        story: 2,
        xStart: 0.24,
        xEnd: 0.96,
        eaveHeight: 0.68,
        peakHeight: 0.72,
        peakOffset: 0.50,
        depthOffset: 0.06,
        hasGarage: false,
        hasDoor: false,
        windowStyle: 'modern_grid',
      ),
      ArchSection(
        id: 'sec-left-tower-gable',
        label: 'Upper Left Recessed Dormer Nook',
        shape: 'dormer_peak',
        wall: 'front',
        story: 2,
        xStart: 0.06,
        xEnd: 0.26,
        eaveHeight: 0.56,
        peakHeight: 0.66,
        peakOffset: 0.50,
        depthOffset: -0.06,
        hasGarage: false,
        hasDoor: false,
        windowStyle: 'arched',
      ),
      ArchSection(
        id: 'sec-right-wing',
        label: 'Right Side Wing Eave',
        shape: 'flat_eave',
        wall: 'right',
        story: 2,
        xStart: 0.0,
        xEnd: 1.0,
        eaveHeight: 0.58,
        peakHeight: 0.58,
      ),
      ArchSection(
        id: 'sec-back-wing',
        label: 'Back Wing Flat Eave',
        shape: 'flat_eave',
        wall: 'back',
        story: 2,
        xStart: 0.0,
        xEnd: 1.0,
        eaveHeight: 0.54,
        peakHeight: 0.54,
      ),
      ArchSection(
        id: 'sec-left-wing',
        label: 'Left Side Upper & Lower Eaves',
        shape: 'flat_eave',
        wall: 'left',
        story: 2,
        xStart: 0.0,
        xEnd: 1.0,
        eaveHeight: 0.58,
        peakHeight: 0.58,
      ),
    ],
  ),

  // 4. Modern Stepped Cubes + Mono-Slope
  'modern_stepped': HouseArchitecture(
    presetStyle: 'modern_stepped',
    defaultViewMode: '3d',
    cameraYaw: -24.0,
    cameraPitch: 19.0,
    cameraZoom: 1.0,
    sidingColor: '#131d31',
    trimColor: '#38bdf8',
    roofColor: '#090e1a',
    sections: [
      ArchSection(
        id: 'sec-mod-garage',
        label: 'Stepped Cube Garage (Flat)',
        shape: 'flat_eave',
        wall: 'front',
        story: 1,
        xStart: 0.04,
        xEnd: 0.46,
        eaveHeight: 0.46,
        peakHeight: 0.46,
        depthOffset: 0.18,
        hasGarage: true,
        windowStyle: 'none',
      ),
      ArchSection(
        id: 'sec-mod-cantilever',
        label: '2nd-Story Angled Mono-Slope',
        shape: 'shed_slope',
        wall: 'front',
        story: 2,
        xStart: 0.36,
        xEnd: 0.95,
        eaveHeight: 0.62,
        peakHeight: 0.92,
        peakOffset: 0.82,
        depthOffset: 0.10,
        hasDoor: true,
        windowStyle: 'picture',
      ),
      ArchSection(
        id: 'sec-mod-left',
        label: 'Left Cube Fascia',
        shape: 'flat_eave',
        wall: 'left',
        story: 1,
        xStart: 0.08,
        xEnd: 0.92,
        eaveHeight: 0.46,
        peakHeight: 0.46,
      ),
      ArchSection(
        id: 'sec-mod-right',
        label: 'Right Upper Fascia',
        shape: 'flat_eave',
        wall: 'right',
        story: 2,
        xStart: 0.08,
        xEnd: 0.92,
        eaveHeight: 0.72,
        peakHeight: 0.72,
      ),
    ],
  ),

  // 5. Colonial Twin Dormers + Porch
  'colonial_dormer': HouseArchitecture(
    presetStyle: 'colonial_dormer',
    defaultViewMode: '3d',
    cameraYaw: -26.0,
    cameraPitch: 21.0,
    cameraZoom: 1.0,
    sidingColor: '#1a263e',
    trimColor: '#e2e8f0',
    roofColor: '#0f172a',
    sections: [
      ArchSection(
        id: 'sec-col-porch',
        label: 'Full-Width Front Porch Eave',
        shape: 'flat_eave',
        wall: 'front',
        story: 1,
        xStart: 0.05,
        xEnd: 0.95,
        eaveHeight: 0.50,
        peakHeight: 0.50,
        depthOffset: 0.14,
        hasDoor: true,
        windowStyle: 'double',
      ),
      ArchSection(
        id: 'sec-col-dormer-l',
        label: 'Left Upper Dormer Triangle',
        shape: 'dormer_peak',
        wall: 'front',
        story: 2,
        xStart: 0.12,
        xEnd: 0.46,
        eaveHeight: 0.68,
        peakHeight: 0.93,
        peakOffset: 0.50,
        depthOffset: -0.04,
        windowStyle: 'standard',
      ),
      ArchSection(
        id: 'sec-col-dormer-r',
        label: 'Right Upper Dormer Triangle',
        shape: 'dormer_peak',
        wall: 'front',
        story: 2,
        xStart: 0.54,
        xEnd: 0.88,
        eaveHeight: 0.68,
        peakHeight: 0.93,
        peakOffset: 0.50,
        depthOffset: -0.04,
        windowStyle: 'standard',
      ),
      ArchSection(
        id: 'sec-col-left',
        label: 'Left Gable End',
        shape: 'triangle_gable',
        wall: 'left',
        story: 1,
        xStart: 0.08,
        xEnd: 0.92,
        eaveHeight: 0.52,
        peakHeight: 0.88,
      ),
      ArchSection(
        id: 'sec-col-right',
        label: 'Right Gable End',
        shape: 'triangle_gable',
        wall: 'right',
        story: 1,
        xStart: 0.08,
        xEnd: 0.92,
        eaveHeight: 0.52,
        peakHeight: 0.88,
      ),
    ],
  ),
};

const List<({String id, String title, String subtitle, String icon})>
    kArchitecturePresetMeta = [
  (
    id: 'a_frame_gable',
    title: '🔺 House #2 (My House): 2nd-Story Gable + Garage + Porch Peak',
    subtitle: '4-window upper triangle peak + 2-car garage eave + porch peak (Front Only)',
    icon: '🔺',
  ),
  (
    id: 'craftsman_multi_section',
    title: '🏘️ House #1 (Left): Steep Gable + Upper Eave + Garage',
    subtitle: '3-window upper steep gable + right eave + lower porch & 2-car garage',
    icon: '🏘️',
  ),
  (
    id: 'two_story_estate',
    title: '🏰 House #3 (Right): Dormer Nook + 3-Window Fascia + Porch',
    subtitle: 'Upper-left recessed dormer + 3-window hip fascia + full-width porch & garage',
    icon: '🏰',
  ),
  (
    id: 'modern_stepped',
    title: '📐 Modern Stepped',
    subtitle: 'Stepped flat cube garage + cantilevered mono-slope',
    icon: '📐',
  ),
  (
    id: 'colonial_dormer',
    title: '🏛️ Colonial Dormers',
    subtitle: 'Front porch eave + twin 2nd-story triangle dormers',
    icon: '🏛️',
  ),
];

/// Maps a contiguous slice of a controller's segments onto a specific `ArchSection`.
class SectionSpan {
  final String sectionId;
  final String wall;
  final int segments;
  final String direction;

  const SectionSpan({
    required this.sectionId,
    this.wall = 'front',
    required this.segments,
    this.direction = 'ltr',
  });

  bool get isReverseDirection =>
      direction == 'rtl' || direction == 'reverse';

  SectionSpan copyWith({
    String? sectionId,
    String? wall,
    int? segments,
    String? direction,
  }) {
    return SectionSpan(
      sectionId: sectionId ?? this.sectionId,
      wall: wall ?? this.wall,
      segments: segments ?? this.segments,
      direction: direction ?? this.direction,
    );
  }

  factory SectionSpan.fromJson(Map<String, dynamic> json) {
    return SectionSpan(
      sectionId: (json['section_id'] ?? '').toString(),
      wall: (json['wall'] ?? 'front').toString().trim().toLowerCase(),
      segments: (json['segments'] is num)
          ? (json['segments'] as num).toInt().clamp(0, 200)
          : 6,
      direction: (json['direction'] ?? 'ltr').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'section_id': sectionId,
        'wall': wall,
        'segments': segments,
        'direction': direction,
      };
}

/// Optional custom 2D/3D LED node position for freehand light placement.
class CustomLightNode {
  final double x;
  final double y;
  final double z;
  final String wall;
  final String label;

  const CustomLightNode({
    required this.x,
    required this.y,
    this.z = 0.0,
    this.wall = 'front',
    this.label = '',
  });

  CustomLightNode copyWith({
    double? x,
    double? y,
    double? z,
    String? wall,
    String? label,
  }) {
    return CustomLightNode(
      x: x ?? this.x,
      y: y ?? this.y,
      z: z ?? this.z,
      wall: wall ?? this.wall,
      label: label ?? this.label,
    );
  }

  factory CustomLightNode.fromJson(Map<String, dynamic> json) {
    return CustomLightNode(
      x: (json['x'] is num) ? (json['x'] as num).toDouble().clamp(0.0, 1.0) : 0.5,
      y: (json['y'] is num) ? (json['y'] as num).toDouble().clamp(0.0, 1.0) : 0.5,
      z: (json['z'] is num) ? (json['z'] as num).toDouble().clamp(-0.5, 0.5) : 0.0,
      wall: (json['wall'] ?? 'front').toString(),
      label: (json['label'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'x': double.parse(x.toStringAsFixed(3)),
        'y': double.parse(y.toStringAsFixed(3)),
        'z': double.parse(z.toStringAsFixed(3)),
        'wall': wall,
        'label': label,
      };
}

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
  final List<Map<String, dynamic>> wallZones;
  final List<SectionSpan> sectionSpans;
  final List<CustomLightNode> customNodes;

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
    this.wallZones = const [],
    this.sectionSpans = const [],
    this.customNodes = const [],
  });

  List<String> getSegmentWalls({String defaultSecondWall = 'front'}) {
    final walls = <String>[];
    const valid = {'front', 'left', 'right', 'back'};
    if (sectionSpans.isNotEmpty) {
      for (final span in sectionSpans) {
        final w = valid.contains(span.wall) ? span.wall : 'front';
        for (int i = 0; i < span.segments; i++) {
          walls.add(w);
        }
      }
    }
    if (walls.isEmpty) {
      for (final z in wallZones) {
        String w = (z['wall'] ?? 'front').toString().trim().toLowerCase();
        if (!valid.contains(w)) w = 'front';
        final cnt = (z['segments'] is num) ? (z['segments'] as num).toInt() : 0;
        for (int i = 0; i < cnt; i++) {
          walls.add(w);
        }
      }
    }
    if (walls.isEmpty && defaultSecondWall != 'front' && segmentCount >= 4) {
      final half = (segmentCount / 2).ceil();
      for (int i = 0; i < half; i++) {
        walls.add('front');
      }
      for (int i = half; i < segmentCount; i++) {
        walls.add(defaultSecondWall);
      }
    }
    while (walls.length < segmentCount) {
      walls.add(walls.isNotEmpty ? walls.last : 'front');
    }
    return walls.sublist(0, segmentCount);
  }

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
    List<Map<String, dynamic>>? wallZones,
    List<SectionSpan>? sectionSpans,
    List<CustomLightNode>? customNodes,
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
      wallZones: wallZones ?? this.wallZones,
      sectionSpans: sectionSpans ?? this.sectionSpans,
      customNodes: customNodes ?? this.customNodes,
    );
  }

  factory ControllerConfig.fromJson(Map<String, dynamic> json) {
    final parsedZones = <Map<String, dynamic>>[];
    if (json['wall_zones'] is List) {
      for (final z in json['wall_zones']) {
        if (z is Map) {
          parsedZones.add(Map<String, dynamic>.from(z));
        }
      }
    }
    final parsedSpans = <SectionSpan>[];
    if (json['section_spans'] is List) {
      for (final s in json['section_spans']) {
        if (s is Map) {
          parsedSpans.add(SectionSpan.fromJson(Map<String, dynamic>.from(s)));
        }
      }
    }
    final parsedNodes = <CustomLightNode>[];
    if (json['custom_nodes'] is List) {
      for (final n in json['custom_nodes']) {
        if (n is Map) {
          parsedNodes.add(
            CustomLightNode.fromJson(Map<String, dynamic>.from(n)),
          );
        }
      }
    }
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
      wallZones: parsedZones,
      sectionSpans: parsedSpans,
      customNodes: parsedNodes,
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
        'wall_zones': wallZones,
        'section_spans': sectionSpans.map((s) => s.toJson()).toList(),
        'custom_nodes': customNodes.map((n) => n.toJson()).toList(),
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
  final HouseArchitecture? _architecture;

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
    HouseArchitecture? architecture,
  }) : _architecture = architecture;

  /// Resolved 3D/2D architecture for this house.
  /// Uses explicit `_architecture` when set; otherwise selects the matching
  /// architectural blueprint (`craftsman_multi_section` for Neighbor 1 / `house-1`,
  /// `a_frame_gable` for My House / `house-2`, and `two_story_estate` for Neighbor 2 / `house-3`).
  HouseArchitecture get architecture {
    if (_architecture != null && _architecture.sections.isNotEmpty) {
      return _architecture;
    }
    final lowerName = name.toLowerCase();
    if (lowerName.contains('my house')) {
      return HouseArchitecture.defaultForHouse('house-2', 2);
    }
    if (lowerName.contains('neighbor 1')) {
      return HouseArchitecture.defaultForHouse('house-1', 1);
    }
    if (lowerName.contains('neighbor 2')) {
      return HouseArchitecture.defaultForHouse('house-3', 3);
    }
    return HouseArchitecture.defaultForHouse(id, order);
  }

  /// Resolves the ordered `SectionSpan` list for a controller on this house,
  /// mapping its segments onto `architecture.sections` even when `ctrl.sectionSpans`
  /// hasn't been manually customized yet.
  List<SectionSpan> effectiveControllerSpans(ControllerConfig ctrl) {
    final arch = architecture;
    final validSectionIds = {for (final s in arch.sections) s.id: s};
    if (ctrl.sectionSpans.isNotEmpty) {
      final valid = ctrl.sectionSpans
          .where((sp) => sp.segments > 0 && validSectionIds.containsKey(sp.sectionId))
          .toList();
      if (valid.isNotEmpty) return valid;
    }

    final n = ctrl.segmentCount;
    final ctrlIdx = controllers.indexWhere((c) => c.id == ctrl.id);

    String resolveDir(String recipeDir) {
      if (!ctrl.reversed) return recipeDir;
      return (recipeDir == 'rtl' || recipeDir == 'reverse') ? 'ltr' : 'rtl';
    }

    List<SectionSpan> buildProportionalSpans(
      List<({String id, String wall, int base, String dir})> recipe,
    ) {
      final filtered = recipe
          .where((r) => validSectionIds.containsKey(r.id))
          .toList();
      if (filtered.isEmpty) return const [];
      final baseSum = filtered.fold<int>(0, (acc, r) => acc + r.base);
      if (baseSum == n) {
        return filtered
            .map((r) => SectionSpan(
                  sectionId: r.id,
                  wall: r.wall,
                  segments: r.base,
                  direction: resolveDir(r.dir),
                ))
            .toList();
      }
      final spans = <SectionSpan>[];
      int remaining = n;
      for (int i = 0; i < filtered.length; i++) {
        final item = filtered[i];
        final cnt = (i == filtered.length - 1)
            ? remaining
            : ((n * item.base) / baseSum).round().clamp(1, remaining);
        remaining -= cnt;
        if (cnt > 0) {
          spans.add(
            SectionSpan(
              sectionId: item.id,
              wall: item.wall,
              segments: cnt,
              direction: resolveDir(item.dir),
            ),
          );
        }
      }
      return spans;
    }

    // Photo-accurate Bottom-to-Top Counter-Clockwise (1F LTR -> 2F RTL) default spans for the 3 real houses:
    if (arch.presetStyle == 'a_frame_gable' ||
        validSectionIds.containsKey('sec-main-gable')) {
      final recipeSpans = buildProportionalSpans(const [
        (id: 'sec-lower-garage-eave', wall: 'front', base: 2, dir: 'ltr'),
        (id: 'sec-lower-porch-gable', wall: 'front', base: 2, dir: 'ltr'),
        (id: 'sec-main-gable', wall: 'front', base: 5, dir: 'rtl'),
      ]);
      if (recipeSpans.isNotEmpty) return recipeSpans;
    }

    if (arch.presetStyle == 'craftsman_multi_section' &&
        validSectionIds.containsKey('sec-upper-dormer')) {
      if (ctrl.id == 'h1-ctrl-2' ||
          ctrl.id == 'house-1-ctrl-2' ||
          ctrlIdx >= 1) {
        final recipeSpans = buildProportionalSpans(const [
          (id: 'sec-right-eave', wall: 'right', base: 4, dir: 'ltr'),
          (id: 'sec-back-eave', wall: 'back', base: 4, dir: 'rtl'),
          (id: 'sec-left-eave', wall: 'left', base: 4, dir: 'rtl'),
        ]);
        if (recipeSpans.isNotEmpty) return recipeSpans;
      } else {
        final recipeSpans = buildProportionalSpans(const [
          (id: 'sec-entry-gable', wall: 'front', base: 2, dir: 'ltr'),
          (id: 'sec-garage-square', wall: 'front', base: 4, dir: 'ltr'),
          (id: 'sec-upper-right-eave', wall: 'front', base: 2, dir: 'rtl'),
          (id: 'sec-upper-dormer', wall: 'front', base: 4, dir: 'rtl'),
        ]);
        if (recipeSpans.isNotEmpty) return recipeSpans;
      }
    }

    if (arch.presetStyle == 'two_story_estate' &&
        validSectionIds.containsKey('sec-left-tower-gable')) {
      if (ctrl.id == 'h3-ctrl-2' ||
          ctrl.id == 'house-3-ctrl-2' ||
          ctrlIdx >= 1) {
        final recipeSpans = buildProportionalSpans(const [
          (id: 'sec-right-wing', wall: 'right', base: 5, dir: 'ltr'),
          (id: 'sec-back-wing', wall: 'back', base: 5, dir: 'rtl'),
          (id: 'sec-left-wing', wall: 'left', base: 5, dir: 'rtl'),
        ]);
        if (recipeSpans.isNotEmpty) return recipeSpans;
      } else {
        final recipeSpans = buildProportionalSpans(const [
          (id: 'sec-right-garage-gable', wall: 'front', base: 7, dir: 'ltr'),
          (id: 'sec-center-flat-fascia', wall: 'front', base: 6, dir: 'rtl'),
          (id: 'sec-left-tower-gable', wall: 'front', base: 2, dir: 'rtl'),
        ]);
        if (recipeSpans.isNotEmpty) return recipeSpans;
      }
    }

    final rawFrontSecs = arch.sections.where((s) => s.wall == 'front').toList();
    final lowerFront = rawFrontSecs.where((s) => s.story == 1).toList()
      ..sort((a, b) => a.xStart.compareTo(b.xStart));
    final upperFront = rawFrontSecs.where((s) => s.story >= 2).toList()
      ..sort((a, b) => b.xStart.compareTo(a.xStart));
    final frontSecs = [...lowerFront, ...upperFront];
    final allSecs = arch.sections.isNotEmpty
        ? arch.sections
        : HouseArchitecture.defaultForHouse(id, order).sections;

    // Single controller or My House -> map onto front architectural sections Bottom-to-Top CCW
    if (isMyHouse || controllers.length <= 1) {
      final targets = frontSecs.isNotEmpty ? frontSecs : [allSecs.first];
      if (targets.length == 1) {
        final onlySec = targets.first;
        return [
          SectionSpan(
            sectionId: onlySec.id,
            wall: onlySec.wall,
            segments: n,
            direction: resolveDir(onlySec.story >= 2 ? 'rtl' : 'ltr'),
          ),
        ];
      }
      final spans = <SectionSpan>[];
      int remaining = n;
      for (int i = 0; i < targets.length; i++) {
        final sec = targets[i];
        final cnt = (i == targets.length - 1)
            ? remaining
            : (n / targets.length).round().clamp(1, remaining);
        remaining -= cnt;
        if (cnt > 0) {
          spans.add(
            SectionSpan(
              sectionId: sec.id,
              wall: sec.wall,
              segments: cnt,
              direction: resolveDir(sec.story >= 2 ? 'rtl' : 'ltr'),
            ),
          );
        }
      }
      return spans;
    }

    // Multi-controller house fallback: Ctrl 1 = Front Bottom-to-Top CCW, Ctrl 2 = Sides & Back CCW
    if (ctrlIdx <= 0) {
      final targets = frontSecs.isNotEmpty ? frontSecs : [allSecs.first];
      final spans = <SectionSpan>[];
      int remaining = n;
      for (int i = 0; i < targets.length; i++) {
        final sec = targets[i];
        final cnt = (i == targets.length - 1)
            ? remaining
            : (n / targets.length).round().clamp(1, remaining);
        remaining -= cnt;
        if (cnt > 0) {
          spans.add(
            SectionSpan(
              sectionId: sec.id,
              wall: sec.wall,
              segments: cnt,
              direction: resolveDir(sec.story >= 2 ? 'rtl' : 'ltr'),
            ),
          );
        }
      }
      return spans;
    } else {
      final sideAndBack = arch.sections
          .where((s) => s.wall != 'front')
          .toList();
      final targets = sideAndBack.isNotEmpty
          ? sideAndBack
          : (frontSecs.isNotEmpty ? frontSecs : [allSecs.last]);
      final spans = <SectionSpan>[];
      int remaining = n;
      for (int i = 0; i < targets.length; i++) {
        final sec = targets[i];
        final cnt = (i == targets.length - 1)
            ? remaining
            : (n / targets.length).round().clamp(1, remaining);
        remaining -= cnt;
        if (cnt > 0) {
          final defDir = (sec.wall == 'back' || sec.wall == 'left') ? 'rtl' : 'ltr';
          spans.add(
            SectionSpan(
              sectionId: sec.id,
              wall: sec.wall,
              segments: cnt,
              direction: resolveDir(defDir),
            ),
          );
        }
      }
      return spans;
    }
  }

  /// Computes the ordered architectural metadata (`wall`, `sectionId`, `story`, `archX` in `0.0..1.0`)
  /// for every segment on this house so Upper (`story == 2`) and Lower (`story == 1`) rooflines
  /// can be horizontally X-locked during multi-house chases.
  List<({String wall, String sectionId, int story, double archX})>
      get allSegmentArchPositions {
    final arch = architecture;
    final secMap = {for (final s in arch.sections) s.id: s};
    final activeCtrls = controllers.where((c) => c.enabled).toList();
    final ctrls = activeCtrls.isNotEmpty
        ? activeCtrls
        : [
            ControllerConfig(
              id: '$id-ctrl-1',
              name: 'Main Controller',
              segmentCount: totalSegments,
            ),
          ];
    final out = <({String wall, String sectionId, int story, double archX})>[];
    for (final ctrl in ctrls) {
      final spans = effectiveControllerSpans(ctrl);
      int countForCtrl = 0;
      for (final sp in spans) {
        final sec = secMap[sp.sectionId];
        final wall = sec?.wall ?? sp.wall;
        final story = sec?.story ?? 1;
        final x0 = (sec?.xStart ?? 0.05).clamp(0.0, 1.0);
        final x1 = (sec?.xEnd ?? 0.95).clamp(0.0, 1.0);
        final n = sp.segments;
        for (int k = 0; k < n && countForCtrl < ctrl.segmentCount; k++) {
          double u = n <= 1 ? 0.5 : (k + 0.5) / n;
          if (sp.isReverseDirection != ctrl.reversed) {
            u = 1.0 - u;
          }
          double archX;
          if (wall == 'front') {
            archX = (x0 + u * (x1 - x0)).clamp(0.0, 1.0);
          } else if (wall == 'left') {
            archX = (0.04 * (1.0 - u)).clamp(0.0, 1.0);
          } else if (wall == 'right') {
            archX = (0.96 + 0.04 * u).clamp(0.0, 1.0);
          } else {
            archX = (1.0 - u).clamp(0.0, 1.0);
          }
          out.add((
            wall: wall,
            sectionId: sp.sectionId,
            story: story,
            archX: archX,
          ));
          countForCtrl++;
        }
      }
      while (countForCtrl < ctrl.segmentCount) {
        final fallbackU = (countForCtrl + 0.5) / ctrl.segmentCount;
        out.add((
          wall: 'front',
          sectionId: arch.sections.isNotEmpty ? arch.sections.first.id : 'sec-front',
          story: 1,
          archX: fallbackU.clamp(0.0, 1.0),
        ));
        countForCtrl++;
      }
    }
    return out;
  }

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
      controllers.any((c) => c.ip == '192.168.1.83' || c.ip == '192.168.1.83');

  /// Returns the ordered wall assignment ('front', 'left', 'right', 'back') for every segment on this house.
  List<String> get allSegmentWalls {
    final activeCtrls = controllers.where((c) => c.enabled).toList();
    if (activeCtrls.isEmpty) {
      return List<String>.filled(9, 'front');
    }
    final hasExplicitSpansOrZones = activeCtrls.any(
      (c) => c.sectionSpans.isNotEmpty || c.wallZones.isNotEmpty,
    );
    if (hasExplicitSpansOrZones) {
      final out = <String>[];
      for (int ci = 0; ci < activeCtrls.length; ci++) {
        final defWall = (!isMyHouse && activeCtrls.length > 1)
            ? (ci == 0 ? 'left' : 'right')
            : 'front';
        out.addAll(activeCtrls[ci].getSegmentWalls(defaultSecondWall: defWall));
      }
      return out;
    }
    // Derive from effectiveControllerSpans so architectural sections drive wall counts
    final out = <String>[];
    const valid = {'front', 'left', 'right', 'back'};
    for (final ctrl in activeCtrls) {
      final spans = effectiveControllerSpans(ctrl);
      int countForCtrl = 0;
      for (final sp in spans) {
        final w = valid.contains(sp.wall) ? sp.wall : 'front';
        for (int i = 0; i < sp.segments && countForCtrl < ctrl.segmentCount; i++) {
          out.add(w);
          countForCtrl++;
        }
      }
      while (countForCtrl < ctrl.segmentCount) {
        out.add('front');
        countForCtrl++;
      }
    }
    return out;
  }

  Map<String, int> get wallSegmentCounts {
    final counts = <String, int>{'front': 0, 'left': 0, 'right': 0, 'back': 0};
    for (final w in allSegmentWalls) {
      counts[w] = (counts[w] ?? 0) + 1;
    }
    return counts;
  }

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
    HouseArchitecture? architecture,
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
      architecture: architecture ?? _architecture,
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
    HouseArchitecture? parsedArch;
    if (json['architecture'] is Map) {
      parsedArch = HouseArchitecture.fromJson(
        Map<String, dynamic>.from(json['architecture'] as Map),
      );
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
      architecture: parsedArch,
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
        'architecture': architecture.toJson(),
      };
}

class AnimationConfig {
  final bool running;
  final bool blackoutOnStop;
  final String effect;
  final double speed;
  final String direction;
  final String mappingMode;
  final String zoneMode;
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
    this.zoneMode = 'all_segments',
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
    String? zoneMode,
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
      zoneMode: zoneMode ?? this.zoneMode,
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
      zoneMode: (json['zone_mode'] ?? 'all_segments').toString(),
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
        'zone_mode': zoneMode,
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
    return SystemConfig(
      houses: [
        HouseConfig(
          id: 'house-1',
          name: 'Neighbor 1 (Left House)',
          order: 1,
          enabled: true,
          timeWeight: 1.0,
          connectionType: 'govee_cloud',
          notes:
              '2 Govee controllers wired Bottom-to-Top Counter-Clockwise (1F LTR -> 2F RTL + Sides/Back CCW, 24 segments)',
          architecture: kArchitecturePresets['craftsman_multi_section'],
          controllers: const [
            ControllerConfig(
              id: 'h1-ctrl-1',
              name: 'Neighbor 1 - Front Roofline (Bottom-to-Top CCW)',
              mac: 'AA:BB:CC:DD:EE:02',
              sku: 'H705A',
              segmentCount: 12,
              sectionSpans: [
                SectionSpan(
                  sectionId: 'sec-entry-gable',
                  wall: 'front',
                  segments: 2,
                  direction: 'ltr',
                ),
                SectionSpan(
                  sectionId: 'sec-garage-square',
                  wall: 'front',
                  segments: 4,
                  direction: 'ltr',
                ),
                SectionSpan(
                  sectionId: 'sec-upper-right-eave',
                  wall: 'front',
                  segments: 2,
                  direction: 'rtl',
                ),
                SectionSpan(
                  sectionId: 'sec-upper-dormer',
                  wall: 'front',
                  segments: 4,
                  direction: 'rtl',
                ),
              ],
            ),
            ControllerConfig(
              id: 'h1-ctrl-2',
              name: 'Neighbor 1 - Sides & Back (CCW Loop)',
              mac: 'AA:BB:CC:DD:EE:03',
              sku: 'H705A',
              segmentCount: 12,
              sectionSpans: [
                SectionSpan(
                  sectionId: 'sec-right-eave',
                  wall: 'right',
                  segments: 4,
                  direction: 'ltr',
                ),
                SectionSpan(
                  sectionId: 'sec-back-eave',
                  wall: 'back',
                  segments: 4,
                  direction: 'rtl',
                ),
                SectionSpan(
                  sectionId: 'sec-left-eave',
                  wall: 'left',
                  segments: 4,
                  direction: 'rtl',
                ),
              ],
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
              'My Govee Outdoor Lights H705E on 192.168.1.83 (9 segments, Front Only Bottom-to-Top CCW: 2 garage eave LTR + 2 porch peak LTR + 5 upper gable RTL)',
          architecture: kArchitecturePresets['a_frame_gable'],
          controllers: const [
            ControllerConfig(
              id: 'h2-ctrl-1',
              name: 'Govee Outdoor Lights 2 (H705E)',
              ip: '192.168.1.83',
              mac: 'AA:BB:CC:DD:EE:FF:00:02',
              sku: 'H705E',
              segmentCount: 9,
              sectionSpans: [
                SectionSpan(
                  sectionId: 'sec-lower-garage-eave',
                  wall: 'front',
                  segments: 2,
                  direction: 'ltr',
                ),
                SectionSpan(
                  sectionId: 'sec-lower-porch-gable',
                  wall: 'front',
                  segments: 2,
                  direction: 'ltr',
                ),
                SectionSpan(
                  sectionId: 'sec-main-gable',
                  wall: 'front',
                  segments: 5,
                  direction: 'rtl',
                ),
              ],
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
          notes:
              '2 Govee H706A controllers wired Bottom-to-Top Counter-Clockwise (1F Porch/Garage LTR -> 2F Hip Fascia & Dormer RTL + Sides/Back CCW, 30 segments)',
          architecture: kArchitecturePresets['two_story_estate'],
          controllers: const [
            ControllerConfig(
              id: 'h3-ctrl-1',
              name: 'Neighbor 2 - Front Roofline (Bottom-to-Top CCW)',
              mac: 'AA:BB:CC:DD:EE:04',
              sku: 'H706A',
              segmentCount: 15,
              sectionSpans: [
                SectionSpan(
                  sectionId: 'sec-right-garage-gable',
                  wall: 'front',
                  segments: 7,
                  direction: 'ltr',
                ),
                SectionSpan(
                  sectionId: 'sec-center-flat-fascia',
                  wall: 'front',
                  segments: 6,
                  direction: 'rtl',
                ),
                SectionSpan(
                  sectionId: 'sec-left-tower-gable',
                  wall: 'front',
                  segments: 2,
                  direction: 'rtl',
                ),
              ],
            ),
            ControllerConfig(
              id: 'h3-ctrl-2',
              name: 'Neighbor 2 - Sides & Back (CCW Loop)',
              mac: 'AA:BB:CC:DD:EE:05',
              sku: 'H706A',
              segmentCount: 15,
              sectionSpans: [
                SectionSpan(
                  sectionId: 'sec-right-wing',
                  wall: 'right',
                  segments: 5,
                  direction: 'ltr',
                ),
                SectionSpan(
                  sectionId: 'sec-back-wing',
                  wall: 'back',
                  segments: 5,
                  direction: 'rtl',
                ),
                SectionSpan(
                  sectionId: 'sec-left-wing',
                  wall: 'left',
                  segments: 5,
                  direction: 'rtl',
                ),
              ],
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
  final String subcategory;
  final String sceneSource;
  final String holidayTag;
  final bool isMultiHouse;
  final String badge;
  final String description;
  final AnimationConfig animation;
  final bool isCustomized;

  const PresetScene({
    required this.id,
    required this.name,
    required this.category,
    this.subcategory = 'AI & Custom',
    this.sceneSource = 'ai_custom',
    this.holidayTag = '',
    this.isMultiHouse = false,
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
      subcategory: subcategory,
      sceneSource: sceneSource,
      holidayTag: holidayTag,
      isMultiHouse: isMultiHouse,
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
    final rawId = (json['id'] ?? '').toString();
    final rawSrc = (json['scene_source'] ?? '').toString().trim().toLowerCase();
    final inferredSrc = rawSrc.isNotEmpty
        ? rawSrc
        : (rawId.startsWith('mh_')
            ? 'multi_house'
            : (rawId.startsWith('govee_official_')
                ? 'official'
                : (rawId.startsWith('diy_') ? 'diy' : 'ai_custom')));
    final rawSub = (json['subcategory'] ?? '').toString().trim();
    final inferredSub = rawSub.isNotEmpty
        ? rawSub
        : (inferredSrc == 'multi_house'
            ? 'Multi-House'
            : (inferredSrc == 'official'
                ? 'Official Govee'
                : (inferredSrc == 'diy' ? 'My Govee DIY' : 'AI & Custom')));
    final isMh = json['is_multi_house'] == true ||
        inferredSrc == 'multi_house' ||
        rawId.startsWith('mh_');
    return PresetScene(
      id: rawId,
      name: (json['name'] ?? 'Scene').toString(),
      category: (json['category'] ?? 'Cyber & Party').toString(),
      subcategory: inferredSub,
      sceneSource: inferredSrc,
      holidayTag: (json['holiday_tag'] ?? json['category'] ?? '').toString(),
      isMultiHouse: isMh,
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
    id: "mh_halloween_phantom_relay",
    name: "Multi-House: Phantom Poltergeist Relay (1\u21922\u21923)",
    category: "Halloween",
    subcategory: "Multi-House",
    sceneSource: "multi_house",
    holidayTag: "Halloween",
    isMultiHouse: true,
    badge: "Multi-House \u2022 Halloween",
    description: "Designed for Multi-House Sync: Ghostly ultraviolet phantom leaps from Neighbor 1 -> My House -> Neighbor 2 while trailing eerie toxic green mist.",
    animation: AnimationConfig(
      effect: "halloween_spooky",
      speed: 0.24,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#9333ea",
      secondaryColor: "#22c55e",
      accentColor: "#ff6b00",
      backgroundColor: "#090314",
      backgroundDim: 0.1,
      tailLength: 0.26,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "mh_halloween_headless_gallop",
    name: "Multi-House: Headless Horseman Street Gallop",
    category: "Halloween",
    subcategory: "Multi-House",
    sceneSource: "multi_house",
    holidayTag: "Halloween",
    isMultiHouse: true,
    badge: "Multi-House \u2022 Halloween",
    description: "Designed for Multi-House Sync: Fiery pumpkin-orange steed charges down the street from House 1 through My House to House 3 leaving blood-crimson sparks.",
    animation: AnimationConfig(
      effect: "comet_meteor",
      speed: 0.28,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff5500",
      secondaryColor: "#dc2626",
      accentColor: "#fde047",
      backgroundColor: "#120303",
      backgroundDim: 0.08,
      tailLength: 0.24,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "mh_halloween_coven_shockwave",
    name: "Multi-House: Middle-House Witch Coven Blast",
    category: "Halloween",
    subcategory: "Multi-House",
    sceneSource: "multi_house",
    holidayTag: "Halloween",
    isMultiHouse: true,
    badge: "Multi-House \u2022 Center-Out",
    description: "Designed for Multi-House Sync: Ignites at YOUR middle house with a blinding emerald-purple cauldron flash, then explodes outward to both neighbors.",
    animation: AnimationConfig(
      effect: "center_out_shockwave",
      speed: 0.25,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#10b981",
      secondaryColor: "#9333ea",
      accentColor: "#ff6b00",
      backgroundColor: "#05100a",
      backgroundDim: 0.1,
      tailLength: 0.28,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "mh_halloween_thunder_chain",
    name: "Multi-House: Rooftop Chain-Lightning Jump",
    category: "Halloween",
    subcategory: "Multi-House",
    sceneSource: "multi_house",
    holidayTag: "Halloween",
    isMultiHouse: true,
    badge: "Multi-House \u2022 Storm",
    description: "Designed for Multi-House Sync: Brooding violet storm clouds across all houses as a white-hot chain lightning bolt jumps rooftop to rooftop.",
    animation: AnimationConfig(
      effect: "lightning_storm",
      speed: 0.32,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#38bdf8",
      secondaryColor: "#7e22ce",
      accentColor: "#facc15",
      backgroundColor: "#070412",
      backgroundDim: 0.1,
      tailLength: 0.22,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "mh_halloween_vampire_bat_swarm",
    name: "Multi-House: Dracula's Bat Swarm Bounce (\u2194)",
    category: "Halloween",
    subcategory: "Multi-House",
    sceneSource: "multi_house",
    holidayTag: "Halloween",
    isMultiHouse: true,
    badge: "Multi-House \u2022 Bounce",
    description: "Designed for Multi-House Sync: Blood-red and midnight-purple bat colony swooping back and forth between all active houses.",
    animation: AnimationConfig(
      effect: "multi_house_chase",
      speed: 0.26,
      direction: "pingpong",
      mappingMode: "house_normalized",
      primaryColor: "#dc2626",
      secondaryColor: "#6b21a8",
      accentColor: "#f43f5e",
      backgroundColor: "#110205",
      backgroundDim: 0.08,
      tailLength: 0.25,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "mh_halloween_candy_corn_conveyor",
    name: "Multi-House: 3-House Candy Corn Rotation",
    category: "Halloween",
    subcategory: "Multi-House",
    sceneSource: "multi_house",
    holidayTag: "Halloween",
    isMultiHouse: true,
    badge: "Multi-House \u2022 3-Color",
    description: "Designed for Multi-House Sync: House 1 glows Pumpkin Orange, My House glows Golden Yellow, and House 3 glows Marshmallow White\u2014rotating every beat!",
    animation: AnimationConfig(
      effect: "govee_rainbow2",
      speed: 0.22,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff7b00",
      secondaryColor: "#facc15",
      accentColor: "#ffffff",
      backgroundColor: "#120700",
      backgroundDim: 0.09,
      tailLength: 0.3,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "mh_halloween_zombie_breach",
    name: "Multi-House: Biohazard Quarantine Siren Sweep",
    category: "Halloween",
    subcategory: "Multi-House",
    sceneSource: "multi_house",
    holidayTag: "Halloween",
    isMultiHouse: true,
    badge: "Multi-House \u2022 Siren",
    description: "Designed for Multi-House Sync: Toxic radioactive green sweeps from Neighbor 1 to Neighbor 2 while emergency crimson beacons flash.",
    animation: AnimationConfig(
      effect: "cyber_snake",
      speed: 0.3,
      direction: "pingpong",
      mappingMode: "house_normalized",
      primaryColor: "#84cc16",
      secondaryColor: "#ef4444",
      accentColor: "#eab308",
      backgroundColor: "#060e02",
      backgroundDim: 0.09,
      tailLength: 0.24,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "mh_halloween_sanderson_spell",
    name: "Multi-House: Three Witches Trio (1 Witch Per House)",
    category: "Halloween",
    subcategory: "Multi-House",
    sceneSource: "multi_house",
    holidayTag: "Halloween",
    isMultiHouse: true,
    badge: "Multi-House \u2022 Trio",
    description: "Designed for Multi-House Sync: Winifred Emerald on House 1, Sarah Violet on My House, and Mary Crimson on House 3 rotating across the street.",
    animation: AnimationConfig(
      effect: "govee_rainbow1",
      speed: 0.21,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#10b981",
      secondaryColor: "#8b5cf6",
      accentColor: "#ef4444",
      backgroundColor: "#080312",
      backgroundDim: 0.1,
      tailLength: 0.3,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "mh_xmas_santa_rooftop_hop",
    name: "Multi-House: Santa's Sleigh Rooftop Hop (1\u21922\u21923)",
    category: "Christmas",
    subcategory: "Multi-House",
    sceneSource: "multi_house",
    holidayTag: "Christmas",
    isMultiHouse: true,
    badge: "Multi-House \u2022 Christmas",
    description: "Designed for Multi-House Sync: Rudolph's glowing red nose and golden sleigh land on House 1, leap to My House, then fly to House 3!",
    animation: AnimationConfig(
      effect: "christmas_magic",
      speed: 0.24,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ef4444",
      secondaryColor: "#fbbf24",
      accentColor: "#10b981",
      backgroundColor: "#041008",
      backgroundDim: 0.1,
      tailLength: 0.26,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "mh_xmas_candy_cane_street",
    name: "Multi-House: 3-House Peppermint Candy Cane Relay",
    category: "Christmas",
    subcategory: "Multi-House",
    sceneSource: "multi_house",
    holidayTag: "Christmas",
    isMultiHouse: true,
    badge: "Multi-House \u2022 Candy Cane",
    description: "Designed for Multi-House Sync: Peppermint Red, Pure Snow White, and Holly Green jumping house-to-house down the block.",
    animation: AnimationConfig(
      effect: "multi_house_chase",
      speed: 0.25,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff1744",
      secondaryColor: "#ffffff",
      accentColor: "#00e676",
      backgroundColor: "#100306",
      backgroundDim: 0.08,
      tailLength: 0.25,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "mh_xmas_bethlehem_beacon",
    name: "Multi-House: Star of Bethlehem Middle-House Radiance",
    category: "Christmas",
    subcategory: "Multi-House",
    sceneSource: "multi_house",
    holidayTag: "Christmas",
    isMultiHouse: true,
    badge: "Multi-House \u2022 Center-Out",
    description: "Designed for Multi-House Sync: Brilliant golden-white star ignites on your middle house and cascades royal blue & gold waves to both neighbors.",
    animation: AnimationConfig(
      effect: "center_out_shockwave",
      speed: 0.2,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fde047",
      secondaryColor: "#38bdf8",
      accentColor: "#ffffff",
      backgroundColor: "#040816",
      backgroundDim: 0.1,
      tailLength: 0.3,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "mh_xmas_grinch_chase",
    name: "Multi-House: Grinch Stealing the Street Lights",
    category: "Christmas",
    subcategory: "Multi-House",
    sceneSource: "multi_house",
    holidayTag: "Christmas",
    isMultiHouse: true,
    badge: "Multi-House \u2022 Story",
    description: "Designed for Multi-House Sync: Sneaky Grinch lime-green creeps from house to house, turning each roofline from Holiday Red into Grinch Green!",
    animation: AnimationConfig(
      effect: "color_wipe",
      speed: 0.23,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#84cc16",
      secondaryColor: "#ef4444",
      accentColor: "#facc15",
      backgroundColor: "#051004",
      backgroundDim: 0.09,
      tailLength: 0.28,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "mh_xmas_polar_express_train",
    name: "Multi-House: Polar Express Locomotive Crossing",
    category: "Christmas",
    subcategory: "Multi-House",
    sceneSource: "multi_house",
    holidayTag: "Christmas",
    isMultiHouse: true,
    badge: "Multi-House \u2022 Train",
    description: "Designed for Multi-House Sync: Golden steam-engine headlamp followed by glowing passenger-car windows chugging across all 3 houses.",
    animation: AnimationConfig(
      effect: "comet_meteor",
      speed: 0.24,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#f59e0b",
      secondaryColor: "#fde047",
      accentColor: "#38bdf8",
      backgroundColor: "#040914",
      backgroundDim: 0.09,
      tailLength: 0.3,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "mh_xmas_dueling_carol_bells",
    name: "Multi-House: Carol of the Bells Rooftop Ping-Pong",
    category: "Christmas",
    subcategory: "Multi-House",
    sceneSource: "multi_house",
    holidayTag: "Christmas",
    isMultiHouse: true,
    badge: "Multi-House \u2022 Bounce",
    description: "Designed for Multi-House Sync: High-contrast Gold, Ruby Red, and Emerald Green bell chimes bouncing back and forth across the street.",
    animation: AnimationConfig(
      effect: "theater_chase",
      speed: 0.28,
      direction: "pingpong",
      mappingMode: "house_normalized",
      primaryColor: "#fbbf24",
      secondaryColor: "#dc2626",
      accentColor: "#10b981",
      backgroundColor: "#0c0602",
      backgroundDim: 0.1,
      tailLength: 0.24,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "mh_xmas_jack_frost_blizzard",
    name: "Multi-House: Arctic Nor'easter Street Sweep",
    category: "Christmas",
    subcategory: "Multi-House",
    sceneSource: "multi_house",
    holidayTag: "Christmas",
    isMultiHouse: true,
    badge: "Multi-House \u2022 Blizzard",
    description: "Designed for Multi-House Sync: Icy cyan and diamond-white blizzard gust blowing across all three rooflines in sequence.",
    animation: AnimationConfig(
      effect: "govee_rainbow1",
      speed: 0.26,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#38bdf8",
      secondaryColor: "#ffffff",
      accentColor: "#2563eb",
      backgroundColor: "#030b18",
      backgroundDim: 0.1,
      tailLength: 0.28,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "mh_xmas_three_kings_procession",
    name: "Multi-House: Three Kings Royal Procession",
    category: "Christmas",
    subcategory: "Multi-House",
    sceneSource: "multi_house",
    holidayTag: "Christmas",
    isMultiHouse: true,
    badge: "Multi-House \u2022 Royal",
    description: "Designed for Multi-House Sync: Sovereign Gold on House 1, Frankincense Crimson on My House, and Royal Purple on House 3 marching in unison.",
    animation: AnimationConfig(
      effect: "govee_rainbow2",
      speed: 0.2,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fbbf24",
      secondaryColor: "#dc2626",
      accentColor: "#7e22ce",
      backgroundColor: "#0a0412",
      backgroundDim: 0.09,
      tailLength: 0.28,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "mh_diwali_diya_chain",
    name: "Multi-House: Chain of 1,000 Diyas (1\u21922\u21923)",
    category: "Diwali",
    subcategory: "Multi-House",
    sceneSource: "multi_house",
    holidayTag: "Diwali",
    isMultiHouse: true,
    badge: "Multi-House \u2022 Diwali",
    description: "Designed for Multi-House Sync: Sacred golden oil-lamp flame passed from house to house, lighting the street in saffron and gold.",
    animation: AnimationConfig(
      effect: "diwali_festival",
      speed: 0.22,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#f59e0b",
      secondaryColor: "#fde047",
      accentColor: "#ef4444",
      backgroundColor: "#120802",
      backgroundDim: 0.1,
      tailLength: 0.28,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "mh_diwali_rangoli_triad",
    name: "Multi-House: 3-House Royal Rangoli Triad",
    category: "Diwali",
    subcategory: "Multi-House",
    sceneSource: "multi_house",
    holidayTag: "Diwali",
    isMultiHouse: true,
    badge: "Multi-House \u2022 Rangoli",
    description: "Designed for Multi-House Sync: Peacock Cyan, Lotus Magenta, and Marigold Gold rotating house-by-house in festive symmetry.",
    animation: AnimationConfig(
      effect: "govee_rainbow2",
      speed: 0.24,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ec4899",
      secondaryColor: "#f97316",
      accentColor: "#06b6d4",
      backgroundColor: "#10040c",
      backgroundDim: 0.1,
      tailLength: 0.26,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "mh_diwali_aarti_center_wave",
    name: "Multi-House: Sacred Aarti Wave from My House",
    category: "Diwali",
    subcategory: "Multi-House",
    sceneSource: "multi_house",
    holidayTag: "Diwali",
    isMultiHouse: true,
    badge: "Multi-House \u2022 Center-Out",
    description: "Designed for Multi-House Sync: Warm golden-crimson temple flame radiating outward from your middle house to both neighbors.",
    animation: AnimationConfig(
      effect: "center_out_shockwave",
      speed: 0.21,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ea580c",
      secondaryColor: "#facc15",
      accentColor: "#dc2626",
      backgroundColor: "#140602",
      backgroundDim: 0.1,
      tailLength: 0.28,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "mh_diwali_sky_lantern_flight",
    name: "Multi-House: Floating Sky Lanterns Across Street",
    category: "Diwali",
    subcategory: "Multi-House",
    sceneSource: "multi_house",
    holidayTag: "Diwali",
    isMultiHouse: true,
    badge: "Multi-House \u2022 Lanterns",
    description: "Designed for Multi-House Sync: Glowing amber, magenta, and rose-gold lanterns drifting smoothly from rooftop to rooftop.",
    animation: AnimationConfig(
      effect: "govee_rainbow1",
      speed: 0.2,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fbbf24",
      secondaryColor: "#f43f5e",
      accentColor: "#f97316",
      backgroundColor: "#110504",
      backgroundDim: 0.1,
      tailLength: 0.3,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "mh_nye_times_square_ball_drop",
    name: "Multi-House: New Year's Eve Ball Drop Relay",
    category: "Celebrations",
    subcategory: "Multi-House",
    sceneSource: "multi_house",
    holidayTag: "New Year's Eve",
    isMultiHouse: true,
    badge: "Multi-House \u2022 NYE",
    description: "Designed for Multi-House Sync: Electric crystal cyan, champagne gold, and confetti magenta racing between houses for New Year's Eve!",
    animation: AnimationConfig(
      effect: "multi_house_chase",
      speed: 0.3,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fbbf24",
      secondaryColor: "#00f5d4",
      accentColor: "#ec4899",
      backgroundColor: "#060814",
      backgroundDim: 0.1,
      tailLength: 0.26,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "mh_nye_champagne_toast_ripple",
    name: "Multi-House: Midnight Champagne Supernova (My House)",
    category: "Celebrations",
    subcategory: "Multi-House",
    sceneSource: "multi_house",
    holidayTag: "New Year's Eve",
    isMultiHouse: true,
    badge: "Multi-House \u2022 NYE",
    description: "Designed for Multi-House Sync: Effervescent champagne gold and silver bubbles bursting from your middle house outward to the whole street.",
    animation: AnimationConfig(
      effect: "center_out_shockwave",
      speed: 0.26,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fde047",
      secondaryColor: "#ffffff",
      accentColor: "#f59e0b",
      backgroundColor: "#0c0902",
      backgroundDim: 0.1,
      tailLength: 0.28,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "mh_nye_grand_finale_skyrocket",
    name: "Multi-House: NYE 3-House Fireworks Finale Relay",
    category: "Celebrations",
    subcategory: "Multi-House",
    sceneSource: "multi_house",
    holidayTag: "New Year's Eve",
    isMultiHouse: true,
    badge: "Multi-House \u2022 NYE",
    description: "Designed for Multi-House Sync: Sequential skyrocket launches\u2014House 1 bursts Gold, My House bursts Cyan, House 3 bursts Magenta!",
    animation: AnimationConfig(
      effect: "sparkle_twinkle",
      speed: 0.34,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fbbf24",
      secondaryColor: "#38bdf8",
      accentColor: "#f43f5e",
      backgroundColor: "#050712",
      backgroundDim: 0.1,
      tailLength: 0.24,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "mh_nye_neon_2027_party_wave",
    name: "Multi-House: New Year's Midnight Club Bounce (\u2194)",
    category: "Celebrations",
    subcategory: "Multi-House",
    sceneSource: "multi_house",
    holidayTag: "New Year's Eve",
    isMultiHouse: true,
    badge: "Multi-House \u2022 NYE",
    description: "Designed for Multi-House Sync: High-energy neon magenta, laser cyan, and electric gold bouncing between all active houses.",
    animation: AnimationConfig(
      effect: "cyber_snake",
      speed: 0.32,
      direction: "pingpong",
      mappingMode: "house_normalized",
      primaryColor: "#ff007f",
      secondaryColor: "#00f5d4",
      accentColor: "#facc15",
      backgroundColor: "#060414",
      backgroundDim: 0.09,
      tailLength: 0.25,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "mh_celeb_stadium_wave",
    name: "Multi-House: Seahawks Stadium Crowd Wave (1\u21922\u21923)",
    category: "Celebrations",
    subcategory: "Multi-House",
    sceneSource: "multi_house",
    holidayTag: "Celebrations",
    isMultiHouse: true,
    badge: "Multi-House \u2022 Game Day",
    description: "Designed for Multi-House Sync: Action Green and College Navy stadium wave rolling down the street from house to house!",
    animation: AnimationConfig(
      effect: "multi_house_chase",
      speed: 0.27,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#69be28",
      secondaryColor: "#002244",
      accentColor: "#ffffff",
      backgroundColor: "#020b18",
      backgroundDim: 0.1,
      tailLength: 0.26,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "mh_celeb_usa_freedom_relay",
    name: "Multi-House: Red, White & Blue 3-House Relay",
    category: "Celebrations",
    subcategory: "Multi-House",
    sceneSource: "multi_house",
    holidayTag: "Celebrations",
    isMultiHouse: true,
    badge: "Multi-House \u2022 Patriotic",
    description: "Designed for Multi-House Sync: House 1 Patriot Red, My House Pure White, and House 3 Navy Blue marching across the street!",
    animation: AnimationConfig(
      effect: "govee_rainbow2",
      speed: 0.23,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ef4444",
      secondaryColor: "#ffffff",
      accentColor: "#2563eb",
      backgroundColor: "#040816",
      backgroundDim: 0.09,
      tailLength: 0.28,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "mh_cyber_portal_wormhole",
    name: "Multi-House: Inter-House Quantum Portal Jump",
    category: "Cyber & Party",
    subcategory: "Multi-House",
    sceneSource: "multi_house",
    holidayTag: "Cyber & Party",
    isMultiHouse: true,
    badge: "Multi-House \u2022 Portal",
    description: "Designed for Multi-House Sync: Neon cyan wormhole opens on House 1, teleports through My House, and exits on House 3 in magenta!",
    animation: AnimationConfig(
      effect: "comet_meteor",
      speed: 0.3,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#00f5d4",
      secondaryColor: "#a855f7",
      accentColor: "#ff007f",
      backgroundColor: "#050714",
      backgroundDim: 0.08,
      tailLength: 0.25,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "mh_cyber_dual_serpent_clash",
    name: "Multi-House: Neighbor-vs-Neighbor Clash at My House",
    category: "Center-Out (My House)",
    subcategory: "Multi-House",
    sceneSource: "multi_house",
    holidayTag: "Center-Out (My House)",
    isMultiHouse: true,
    badge: "Multi-House \u2022 Clash",
    description: "Designed for Multi-House Sync: Neighbor 1 fires Cyan and Neighbor 2 fires Magenta, colliding in a blinding Gold explosion on YOUR middle house!",
    animation: AnimationConfig(
      effect: "center_out_shockwave",
      speed: 0.26,
      direction: "pingpong",
      mappingMode: "house_normalized",
      primaryColor: "#00f5d4",
      secondaryColor: "#ff007f",
      accentColor: "#fde047",
      backgroundColor: "#060514",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 1,
    ),
  ),
  PresetScene(
    id: "diy_halloween_chasing",
    name: "Halloween Chasing (My Govee DIY)",
    category: "Halloween",
    subcategory: "My Govee DIY",
    sceneSource: "diy",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "DIY \u2022 Shared",
    description: "Your custom Govee Home App DIY scene 'Halloween chasing' (synced on both your H705E and Neighbor 2's H805D/H705E).",
    animation: AnimationConfig(
      effect: "multi_house_chase",
      speed: 0.3,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff6b00",
      secondaryColor: "#9333ea",
      accentColor: "#22c55e",
      backgroundColor: "#0a0312",
      backgroundDim: 0.08,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "diy_spooky_halloween_ai",
    name: "Spooky Halloween AI (My Govee DIY)",
    category: "Halloween",
    subcategory: "My Govee DIY",
    sceneSource: "diy",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "DIY \u2022 H705E",
    description: "Your custom Govee Home App DIY scene 'Spooky Halloween AI' (#25004667).",
    animation: AnimationConfig(
      effect: "halloween_spooky",
      speed: 0.28,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#9333ea",
      secondaryColor: "#22c55e",
      accentColor: "#ff6b00",
      backgroundColor: "#080310",
      backgroundDim: 0.09,
      tailLength: 0.28,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "diy_orange_and_purple",
    name: "Orange & Purple (My Govee DIY)",
    category: "Halloween",
    subcategory: "My Govee DIY",
    sceneSource: "diy",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "DIY \u2022 H705E",
    description: "Your custom Govee Home App DIY scene 'orange and purple' (#24907990).",
    animation: AnimationConfig(
      effect: "govee_rainbow2",
      speed: 0.25,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff6b00",
      secondaryColor: "#9333ea",
      accentColor: "#ff6b00",
      backgroundColor: "#090312",
      backgroundDim: 0.08,
      tailLength: 0.25,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "diy_red_white_running",
    name: "Red White Running (My Govee DIY)",
    category: "Christmas",
    subcategory: "My Govee DIY",
    sceneSource: "diy",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "DIY \u2022 H705E",
    description: "Your custom Govee Home App DIY scene 'red white running' (#25240693).",
    animation: AnimationConfig(
      effect: "multi_house_chase",
      speed: 0.3,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff1744",
      secondaryColor: "#ffffff",
      accentColor: "#ff5252",
      backgroundColor: "#120306",
      backgroundDim: 0.08,
      tailLength: 0.25,
      pulseCount: 3,
    ),
  ),
  PresetScene(
    id: "govee_official_meteor_14161",
    name: "Govee: Meteor",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #14161",
    description: "Authentic Govee hardware dynamic scene 'Meteor' (sceneId 14161, paramId 22809).",
    animation: AnimationConfig(
      effect: "comet_meteor",
      speed: 0.2,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff6b00",
      secondaryColor: "#9333ea",
      accentColor: "#22c55e",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_karst_cave_10747",
    name: "Govee: Karst Cave",
    category: "Halloween",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "Official #10747",
    description: "Authentic Govee hardware dynamic scene 'Karst Cave' (sceneId 10747, paramId 17952).",
    animation: AnimationConfig(
      effect: "halloween_spooky",
      speed: 0.23,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff6b00",
      secondaryColor: "#9333ea",
      accentColor: "#22c55e",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_cornfield_10749",
    name: "Govee: Cornfield",
    category: "Diwali",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Diwali",
    isMultiHouse: false,
    badge: "Official #10749",
    description: "Authentic Govee hardware dynamic scene 'Cornfield' (sceneId 10749, paramId 17954).",
    animation: AnimationConfig(
      effect: "diwali_festival",
      speed: 0.26,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#f59e0b",
      secondaryColor: "#fbbf24",
      accentColor: "#ef4444",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_halloween_c_10766",
    name: "Govee: Halloween C",
    category: "Halloween",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "Official #10766",
    description: "Authentic Govee hardware dynamic scene 'Halloween C' (sceneId 10766, paramId 17971).",
    animation: AnimationConfig(
      effect: "halloween_spooky",
      speed: 0.29,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff6b00",
      secondaryColor: "#9333ea",
      accentColor: "#22c55e",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_halloween_d_10767",
    name: "Govee: Halloween D",
    category: "Halloween",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "Official #10767",
    description: "Authentic Govee hardware dynamic scene 'Halloween D' (sceneId 10767, paramId 17972).",
    animation: AnimationConfig(
      effect: "halloween_spooky",
      speed: 0.32,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff6b00",
      secondaryColor: "#9333ea",
      accentColor: "#22c55e",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_firefly_10752",
    name: "Govee: Firefly",
    category: "Diwali",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Diwali",
    isMultiHouse: false,
    badge: "Official #10752",
    description: "Authentic Govee hardware dynamic scene 'Firefly' (sceneId 10752, paramId 17957).",
    animation: AnimationConfig(
      effect: "fire_sparkle",
      speed: 0.35,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#f59e0b",
      secondaryColor: "#fbbf24",
      accentColor: "#ef4444",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_fire_10753",
    name: "Govee: Fire",
    category: "Diwali",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Diwali",
    isMultiHouse: false,
    badge: "Official #10753",
    description: "Authentic Govee hardware dynamic scene 'Fire' (sceneId 10753, paramId 17958).",
    animation: AnimationConfig(
      effect: "fire_sparkle",
      speed: 0.2,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#f59e0b",
      secondaryColor: "#fbbf24",
      accentColor: "#ef4444",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_cherry_blossoms_10754",
    name: "Govee: Cherry blossoms",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #10754",
    description: "Authentic Govee hardware dynamic scene 'Cherry blossoms' (sceneId 10754, paramId 17959).",
    animation: AnimationConfig(
      effect: "fire_sparkle",
      speed: 0.23,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff1744",
      secondaryColor: "#ffffff",
      accentColor: "#00e676",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_spring_10755",
    name: "Govee: Spring",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #10755",
    description: "Authentic Govee hardware dynamic scene 'Spring' (sceneId 10755, paramId 17960).",
    animation: AnimationConfig(
      effect: "breathing_pulse",
      speed: 0.26,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#facc15",
      secondaryColor: "#f97316",
      accentColor: "#84cc16",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_summer_10756",
    name: "Govee: Summer",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #10756",
    description: "Authentic Govee hardware dynamic scene 'Summer' (sceneId 10756, paramId 17961).",
    animation: AnimationConfig(
      effect: "halloween_spooky",
      speed: 0.29,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ec4899",
      secondaryColor: "#fbbf24",
      accentColor: "#06b6d4",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_fall_10757",
    name: "Govee: Fall",
    category: "Diwali",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Diwali",
    isMultiHouse: false,
    badge: "Official #10757",
    description: "Authentic Govee hardware dynamic scene 'Fall' (sceneId 10757, paramId 17962).",
    animation: AnimationConfig(
      effect: "diwali_festival",
      speed: 0.32,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#f59e0b",
      secondaryColor: "#fbbf24",
      accentColor: "#ef4444",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_winter_10758",
    name: "Govee: Winter",
    category: "Christmas",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "Official #10758",
    description: "Authentic Govee hardware dynamic scene 'Winter' (sceneId 10758, paramId 17963).",
    animation: AnimationConfig(
      effect: "christmas_magic",
      speed: 0.35,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ef4444",
      secondaryColor: "#10b981",
      accentColor: "#ffffff",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_downpour_10759",
    name: "Govee: Downpour",
    category: "Christmas",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "Official #10759",
    description: "Authentic Govee hardware dynamic scene 'Downpour' (sceneId 10759, paramId 17964).",
    animation: AnimationConfig(
      effect: "christmas_magic",
      speed: 0.2,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ef4444",
      secondaryColor: "#10b981",
      accentColor: "#ffffff",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_thunderstorm_14158",
    name: "Govee: Thunderstorm",
    category: "Halloween",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "Official #14158",
    description: "Authentic Govee hardware dynamic scene 'Thunderstorm' (sceneId 14158, paramId 22806).",
    animation: AnimationConfig(
      effect: "lightning_storm",
      speed: 0.23,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff6b00",
      secondaryColor: "#9333ea",
      accentColor: "#22c55e",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_milky_way_14159",
    name: "Govee: Milky Way",
    category: "Center-Out (My House)",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Center-Out (My House)",
    isMultiHouse: false,
    badge: "Official #14159",
    description: "Authentic Govee hardware dynamic scene 'Milky Way' (sceneId 14159, paramId 22807).",
    animation: AnimationConfig(
      effect: "center_out_shockwave",
      speed: 0.26,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#00f5d4",
      secondaryColor: "#8b5cf6",
      accentColor: "#38bdf8",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_earth_14160",
    name: "Govee: Earth",
    category: "Center-Out (My House)",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Center-Out (My House)",
    isMultiHouse: false,
    badge: "Official #14160",
    description: "Authentic Govee hardware dynamic scene 'Earth' (sceneId 14160, paramId 22808).",
    animation: AnimationConfig(
      effect: "center_out_shockwave",
      speed: 0.29,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#00f5d4",
      secondaryColor: "#8b5cf6",
      accentColor: "#38bdf8",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_lake_14162",
    name: "Govee: Lake",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #14162",
    description: "Authentic Govee hardware dynamic scene 'Lake' (sceneId 14162, paramId 22810).",
    animation: AnimationConfig(
      effect: "theater_chase",
      speed: 0.35,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff1744",
      secondaryColor: "#ffffff",
      accentColor: "#00e676",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_spring_wind_14163",
    name: "Govee: Spring Wind",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #14163",
    description: "Authentic Govee hardware dynamic scene 'Spring Wind' (sceneId 14163, paramId 22811).",
    animation: AnimationConfig(
      effect: "sparkle_twinkle",
      speed: 0.2,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#facc15",
      secondaryColor: "#f97316",
      accentColor: "#84cc16",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_sky_15268",
    name: "Govee: Sky",
    category: "Center-Out (My House)",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Center-Out (My House)",
    isMultiHouse: false,
    badge: "Official #15268",
    description: "Authentic Govee hardware dynamic scene 'Sky' (sceneId 15268, paramId 24085).",
    animation: AnimationConfig(
      effect: "center_out_shockwave",
      speed: 0.23,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#00f5d4",
      secondaryColor: "#8b5cf6",
      accentColor: "#38bdf8",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_sailboat_15269",
    name: "Govee: Sailboat",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #15269",
    description: "Authentic Govee hardware dynamic scene 'Sailboat' (sceneId 15269, paramId 24086).",
    animation: AnimationConfig(
      effect: "breathing_pulse",
      speed: 0.26,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff6b00",
      secondaryColor: "#9333ea",
      accentColor: "#22c55e",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_sunrise_10737",
    name: "Govee: Sunrise",
    category: "Diwali",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Diwali",
    isMultiHouse: false,
    badge: "Official #10737",
    description: "Authentic Govee hardware dynamic scene 'Sunrise' (sceneId 10737, paramId 17942).",
    animation: AnimationConfig(
      effect: "diwali_festival",
      speed: 0.29,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#f59e0b",
      secondaryColor: "#fbbf24",
      accentColor: "#ef4444",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_sunset_10738",
    name: "Govee: Sunset",
    category: "Diwali",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Diwali",
    isMultiHouse: false,
    badge: "Official #10738",
    description: "Authentic Govee hardware dynamic scene 'Sunset' (sceneId 10738, paramId 17943).",
    animation: AnimationConfig(
      effect: "diwali_festival",
      speed: 0.32,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#f59e0b",
      secondaryColor: "#fbbf24",
      accentColor: "#ef4444",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_sunset_glow_10739",
    name: "Govee: Sunset Glow",
    category: "Diwali",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Diwali",
    isMultiHouse: false,
    badge: "Official #10739",
    description: "Authentic Govee hardware dynamic scene 'Sunset Glow' (sceneId 10739, paramId 17944).",
    animation: AnimationConfig(
      effect: "diwali_festival",
      speed: 0.35,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#f59e0b",
      secondaryColor: "#fbbf24",
      accentColor: "#ef4444",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_nebula_10740",
    name: "Govee: Nebula",
    category: "Center-Out (My House)",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Center-Out (My House)",
    isMultiHouse: false,
    badge: "Official #10740",
    description: "Authentic Govee hardware dynamic scene 'Nebula' (sceneId 10740, paramId 17945).",
    animation: AnimationConfig(
      effect: "center_out_shockwave",
      speed: 0.2,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#00f5d4",
      secondaryColor: "#8b5cf6",
      accentColor: "#38bdf8",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_moonlight_10741",
    name: "Govee: Moonlight",
    category: "Center-Out (My House)",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Center-Out (My House)",
    isMultiHouse: false,
    badge: "Official #10741",
    description: "Authentic Govee hardware dynamic scene 'Moonlight' (sceneId 10741, paramId 17946).",
    animation: AnimationConfig(
      effect: "center_out_shockwave",
      speed: 0.23,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#00f5d4",
      secondaryColor: "#8b5cf6",
      accentColor: "#38bdf8",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_star_10742",
    name: "Govee: Star",
    category: "Center-Out (My House)",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Center-Out (My House)",
    isMultiHouse: false,
    badge: "Official #10742",
    description: "Authentic Govee hardware dynamic scene 'Star' (sceneId 10742, paramId 17947).",
    animation: AnimationConfig(
      effect: "center_out_shockwave",
      speed: 0.26,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#00f5d4",
      secondaryColor: "#8b5cf6",
      accentColor: "#38bdf8",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_universe_10743",
    name: "Govee: Universe",
    category: "Center-Out (My House)",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Center-Out (My House)",
    isMultiHouse: false,
    badge: "Official #10743",
    description: "Authentic Govee hardware dynamic scene 'Universe' (sceneId 10743, paramId 17948).",
    animation: AnimationConfig(
      effect: "center_out_shockwave",
      speed: 0.29,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#00f5d4",
      secondaryColor: "#8b5cf6",
      accentColor: "#38bdf8",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_rainbow_10744",
    name: "Govee: Rainbow",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #10744",
    description: "Authentic Govee hardware dynamic scene 'Rainbow' (sceneId 10744, paramId 17949).",
    animation: AnimationConfig(
      effect: "govee_rainbow1",
      speed: 0.32,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff0055",
      secondaryColor: "#00f5d4",
      accentColor: "#facc15",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_forest_10745",
    name: "Govee: Forest",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #10745",
    description: "Authentic Govee hardware dynamic scene 'Forest' (sceneId 10745, paramId 17950).",
    animation: AnimationConfig(
      effect: "theater_chase",
      speed: 0.35,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ec4899",
      secondaryColor: "#fbbf24",
      accentColor: "#06b6d4",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_aurora_10746",
    name: "Govee: Aurora",
    category: "Center-Out (My House)",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Center-Out (My House)",
    isMultiHouse: false,
    badge: "Official #10746",
    description: "Authentic Govee hardware dynamic scene 'Aurora' (sceneId 10746, paramId 17951).",
    animation: AnimationConfig(
      effect: "center_out_shockwave",
      speed: 0.2,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#00f5d4",
      secondaryColor: "#8b5cf6",
      accentColor: "#38bdf8",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_wave_10748",
    name: "Govee: Wave",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #10748",
    description: "Authentic Govee hardware dynamic scene 'Wave' (sceneId 10748, paramId 17953).",
    animation: AnimationConfig(
      effect: "breathing_pulse",
      speed: 0.26,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#00f5d4",
      secondaryColor: "#7b2cbf",
      accentColor: "#ff007f",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_rustling_leaves_10750",
    name: "Govee: Rustling leaves",
    category: "Diwali",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Diwali",
    isMultiHouse: false,
    badge: "Official #10750",
    description: "Authentic Govee hardware dynamic scene 'Rustling leaves' (sceneId 10750, paramId 17955).",
    animation: AnimationConfig(
      effect: "diwali_festival",
      speed: 0.32,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#f59e0b",
      secondaryColor: "#fbbf24",
      accentColor: "#ef4444",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_flower_field_10751",
    name: "Govee: Flower Field",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #10751",
    description: "Authentic Govee hardware dynamic scene 'Flower Field' (sceneId 10751, paramId 17956).",
    animation: AnimationConfig(
      effect: "govee_rainbow2",
      speed: 0.35,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#10b981",
      secondaryColor: "#06b6d4",
      accentColor: "#3b82f6",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_christmas_10760",
    name: "Govee: Christmas",
    category: "Christmas",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "Official #10760",
    description: "Authentic Govee hardware dynamic scene 'Christmas' (sceneId 10760, paramId 17965).",
    animation: AnimationConfig(
      effect: "christmas_magic",
      speed: 0.2,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ef4444",
      secondaryColor: "#10b981",
      accentColor: "#ffffff",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_christmas_tree_10761",
    name: "Govee: Christmas Tree",
    category: "Christmas",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "Official #10761",
    description: "Authentic Govee hardware dynamic scene 'Christmas Tree' (sceneId 10761, paramId 17966).",
    animation: AnimationConfig(
      effect: "christmas_magic",
      speed: 0.23,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ef4444",
      secondaryColor: "#10b981",
      accentColor: "#ffffff",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_christmas_gift_10762",
    name: "Govee: Christmas Gift",
    category: "Christmas",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "Official #10762",
    description: "Authentic Govee hardware dynamic scene 'Christmas Gift' (sceneId 10762, paramId 17967).",
    animation: AnimationConfig(
      effect: "christmas_magic",
      speed: 0.26,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ef4444",
      secondaryColor: "#10b981",
      accentColor: "#ffffff",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_sled_10763",
    name: "Govee: Sled",
    category: "Christmas",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "Official #10763",
    description: "Authentic Govee hardware dynamic scene 'Sled' (sceneId 10763, paramId 17968).",
    animation: AnimationConfig(
      effect: "christmas_magic",
      speed: 0.29,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ef4444",
      secondaryColor: "#10b981",
      accentColor: "#ffffff",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_halloween_10764",
    name: "Govee: Halloween",
    category: "Halloween",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "Official #10764",
    description: "Authentic Govee hardware dynamic scene 'Halloween' (sceneId 10764, paramId 17969).",
    animation: AnimationConfig(
      effect: "halloween_spooky",
      speed: 0.32,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff6b00",
      secondaryColor: "#9333ea",
      accentColor: "#22c55e",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_halloween_b_10765",
    name: "Govee: Halloween B",
    category: "Halloween",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "Official #10765",
    description: "Authentic Govee hardware dynamic scene 'Halloween B' (sceneId 10765, paramId 17970).",
    animation: AnimationConfig(
      effect: "halloween_spooky",
      speed: 0.35,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff6b00",
      secondaryColor: "#9333ea",
      accentColor: "#22c55e",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_easter_10768",
    name: "Govee: Easter",
    category: "Celebrations",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Celebrations",
    isMultiHouse: false,
    badge: "Official #10768",
    description: "Authentic Govee hardware dynamic scene 'Easter' (sceneId 10768, paramId 17973).",
    animation: AnimationConfig(
      effect: "sparkle_twinkle",
      speed: 0.26,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fbbf24",
      secondaryColor: "#ef4444",
      accentColor: "#3b82f6",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_mother_s_day_10769",
    name: "Govee: Mother's Day",
    category: "Celebrations",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Celebrations",
    isMultiHouse: false,
    badge: "Official #10769",
    description: "Authentic Govee hardware dynamic scene 'Mother's Day' (sceneId 10769, paramId 17974).",
    animation: AnimationConfig(
      effect: "sparkle_twinkle",
      speed: 0.29,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fbbf24",
      secondaryColor: "#ef4444",
      accentColor: "#3b82f6",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_mother_s_day_b_10770",
    name: "Govee: Mother's Day B",
    category: "Celebrations",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Celebrations",
    isMultiHouse: false,
    badge: "Official #10770",
    description: "Authentic Govee hardware dynamic scene 'Mother's Day B' (sceneId 10770, paramId 17975).",
    animation: AnimationConfig(
      effect: "sparkle_twinkle",
      speed: 0.32,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fbbf24",
      secondaryColor: "#ef4444",
      accentColor: "#3b82f6",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_father_s_day_10771",
    name: "Govee: Father's Day",
    category: "Celebrations",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Celebrations",
    isMultiHouse: false,
    badge: "Official #10771",
    description: "Authentic Govee hardware dynamic scene 'Father's Day' (sceneId 10771, paramId 17976).",
    animation: AnimationConfig(
      effect: "sparkle_twinkle",
      speed: 0.35,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fbbf24",
      secondaryColor: "#ef4444",
      accentColor: "#3b82f6",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_father_s_dayb_10772",
    name: "Govee: Father's DayB",
    category: "Celebrations",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Celebrations",
    isMultiHouse: false,
    badge: "Official #10772",
    description: "Authentic Govee hardware dynamic scene 'Father's DayB' (sceneId 10772, paramId 17977).",
    animation: AnimationConfig(
      effect: "sparkle_twinkle",
      speed: 0.2,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fbbf24",
      secondaryColor: "#ef4444",
      accentColor: "#3b82f6",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_birthday_10773",
    name: "Govee: Birthday",
    category: "Celebrations",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Celebrations",
    isMultiHouse: false,
    badge: "Official #10773",
    description: "Authentic Govee hardware dynamic scene 'Birthday' (sceneId 10773, paramId 17978).",
    animation: AnimationConfig(
      effect: "sparkle_twinkle",
      speed: 0.23,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fbbf24",
      secondaryColor: "#ef4444",
      accentColor: "#3b82f6",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_new_years_10774",
    name: "Govee: New Years",
    category: "Celebrations",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Celebrations",
    isMultiHouse: false,
    badge: "Official #10774",
    description: "Authentic Govee hardware dynamic scene 'New Years' (sceneId 10774, paramId 17979).",
    animation: AnimationConfig(
      effect: "sparkle_twinkle",
      speed: 0.26,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fbbf24",
      secondaryColor: "#ef4444",
      accentColor: "#3b82f6",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_thanksgiving_10775",
    name: "Govee: Thanksgiving",
    category: "Celebrations",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Celebrations",
    isMultiHouse: false,
    badge: "Official #10775",
    description: "Authentic Govee hardware dynamic scene 'Thanksgiving' (sceneId 10775, paramId 17980).",
    animation: AnimationConfig(
      effect: "sparkle_twinkle",
      speed: 0.29,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fbbf24",
      secondaryColor: "#ef4444",
      accentColor: "#3b82f6",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_carnival_10776",
    name: "Govee: Carnival",
    category: "Celebrations",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Celebrations",
    isMultiHouse: false,
    badge: "Official #10776",
    description: "Authentic Govee hardware dynamic scene 'Carnival' (sceneId 10776, paramId 17981).",
    animation: AnimationConfig(
      effect: "sparkle_twinkle",
      speed: 0.32,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fbbf24",
      secondaryColor: "#ef4444",
      accentColor: "#3b82f6",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_valentine_s_day_10777",
    name: "Govee: Valentine's Day",
    category: "Celebrations",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Celebrations",
    isMultiHouse: false,
    badge: "Official #10777",
    description: "Authentic Govee hardware dynamic scene 'Valentine's Day' (sceneId 10777, paramId 17982).",
    animation: AnimationConfig(
      effect: "sparkle_twinkle",
      speed: 0.35,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fbbf24",
      secondaryColor: "#ef4444",
      accentColor: "#3b82f6",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_dance_party_10778",
    name: "Govee: Dance Party",
    category: "Celebrations",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Celebrations",
    isMultiHouse: false,
    badge: "Official #10778",
    description: "Authentic Govee hardware dynamic scene 'Dance Party' (sceneId 10778, paramId 17983).",
    animation: AnimationConfig(
      effect: "sparkle_twinkle",
      speed: 0.2,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fbbf24",
      secondaryColor: "#ef4444",
      accentColor: "#3b82f6",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_party_10779",
    name: "Govee: Party",
    category: "Celebrations",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Celebrations",
    isMultiHouse: false,
    badge: "Official #10779",
    description: "Authentic Govee hardware dynamic scene 'Party' (sceneId 10779, paramId 17984).",
    animation: AnimationConfig(
      effect: "sparkle_twinkle",
      speed: 0.23,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fbbf24",
      secondaryColor: "#ef4444",
      accentColor: "#3b82f6",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_dine_together_10780",
    name: "Govee: Dine Together",
    category: "Celebrations",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Celebrations",
    isMultiHouse: false,
    badge: "Official #10780",
    description: "Authentic Govee hardware dynamic scene 'Dine Together' (sceneId 10780, paramId 17985).",
    animation: AnimationConfig(
      effect: "sparkle_twinkle",
      speed: 0.26,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fbbf24",
      secondaryColor: "#ef4444",
      accentColor: "#3b82f6",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_fireworks_10781",
    name: "Govee: Fireworks",
    category: "Diwali",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Diwali",
    isMultiHouse: false,
    badge: "Official #10781",
    description: "Authentic Govee hardware dynamic scene 'Fireworks' (sceneId 10781, paramId 17986).",
    animation: AnimationConfig(
      effect: "diwali_festival",
      speed: 0.29,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#f59e0b",
      secondaryColor: "#fbbf24",
      accentColor: "#ef4444",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_candlelight_10782",
    name: "Govee: Candlelight",
    category: "Diwali",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Diwali",
    isMultiHouse: false,
    badge: "Official #10782",
    description: "Authentic Govee hardware dynamic scene 'Candlelight' (sceneId 10782, paramId 17987).",
    animation: AnimationConfig(
      effect: "diwali_festival",
      speed: 0.32,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#f59e0b",
      secondaryColor: "#fbbf24",
      accentColor: "#ef4444",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_saint_patrick_s_day_10783",
    name: "Govee: Saint Patrick's Day",
    category: "Celebrations",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Celebrations",
    isMultiHouse: false,
    badge: "Official #10783",
    description: "Authentic Govee hardware dynamic scene 'Saint Patrick's Day' (sceneId 10783, paramId 17988).",
    animation: AnimationConfig(
      effect: "sparkle_twinkle",
      speed: 0.35,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fbbf24",
      secondaryColor: "#ef4444",
      accentColor: "#3b82f6",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_hanukkah_10784",
    name: "Govee: Hanukkah",
    category: "Celebrations",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Celebrations",
    isMultiHouse: false,
    badge: "Official #10784",
    description: "Authentic Govee hardware dynamic scene 'Hanukkah' (sceneId 10784, paramId 17989).",
    animation: AnimationConfig(
      effect: "sparkle_twinkle",
      speed: 0.2,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fbbf24",
      secondaryColor: "#ef4444",
      accentColor: "#3b82f6",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_game_day_10785",
    name: "Govee: Game Day",
    category: "Celebrations",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Celebrations",
    isMultiHouse: false,
    badge: "Official #10785",
    description: "Authentic Govee hardware dynamic scene 'Game Day' (sceneId 10785, paramId 17990).",
    animation: AnimationConfig(
      effect: "sparkle_twinkle",
      speed: 0.23,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fbbf24",
      secondaryColor: "#ef4444",
      accentColor: "#3b82f6",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_baby_shower_10786",
    name: "Govee: Baby Shower",
    category: "Celebrations",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Celebrations",
    isMultiHouse: false,
    badge: "Official #10786",
    description: "Authentic Govee hardware dynamic scene 'Baby Shower' (sceneId 10786, paramId 17991).",
    animation: AnimationConfig(
      effect: "sparkle_twinkle",
      speed: 0.26,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fbbf24",
      secondaryColor: "#ef4444",
      accentColor: "#3b82f6",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_winter_wonderland_10787",
    name: "Govee: Winter Wonderland",
    category: "Christmas",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "Official #10787",
    description: "Authentic Govee hardware dynamic scene 'Winter Wonderland' (sceneId 10787, paramId 17992).",
    animation: AnimationConfig(
      effect: "christmas_magic",
      speed: 0.29,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ef4444",
      secondaryColor: "#10b981",
      accentColor: "#ffffff",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_leprechaun_10788",
    name: "Govee: Leprechaun",
    category: "Celebrations",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Celebrations",
    isMultiHouse: false,
    badge: "Official #10788",
    description: "Authentic Govee hardware dynamic scene 'Leprechaun' (sceneId 10788, paramId 17993).",
    animation: AnimationConfig(
      effect: "sparkle_twinkle",
      speed: 0.32,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fbbf24",
      secondaryColor: "#ef4444",
      accentColor: "#3b82f6",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_christmas_bell_14164",
    name: "Govee: Christmas Bell",
    category: "Christmas",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "Official #14164",
    description: "Authentic Govee hardware dynamic scene 'Christmas Bell' (sceneId 14164, paramId 22812).",
    animation: AnimationConfig(
      effect: "christmas_magic",
      speed: 0.35,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ef4444",
      secondaryColor: "#10b981",
      accentColor: "#ffffff",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_candy_cane_14165",
    name: "Govee: Candy Cane",
    category: "Christmas",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "Official #14165",
    description: "Authentic Govee hardware dynamic scene 'Candy Cane' (sceneId 14165, paramId 22813).",
    animation: AnimationConfig(
      effect: "christmas_magic",
      speed: 0.2,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ef4444",
      secondaryColor: "#10b981",
      accentColor: "#ffffff",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_christmas_eve_14166",
    name: "Govee: Christmas Eve",
    category: "Christmas",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "Official #14166",
    description: "Authentic Govee hardware dynamic scene 'Christmas Eve' (sceneId 14166, paramId 22814).",
    animation: AnimationConfig(
      effect: "christmas_magic",
      speed: 0.23,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ef4444",
      secondaryColor: "#10b981",
      accentColor: "#ffffff",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_christmas_wreath_14167",
    name: "Govee: Christmas Wreath",
    category: "Christmas",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "Official #14167",
    description: "Authentic Govee hardware dynamic scene 'Christmas Wreath' (sceneId 14167, paramId 22815).",
    animation: AnimationConfig(
      effect: "christmas_magic",
      speed: 0.26,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ef4444",
      secondaryColor: "#10b981",
      accentColor: "#ffffff",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_easter_egg_14168",
    name: "Govee: Easter Egg",
    category: "Celebrations",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Celebrations",
    isMultiHouse: false,
    badge: "Official #14168",
    description: "Authentic Govee hardware dynamic scene 'Easter Egg' (sceneId 14168, paramId 22816).",
    animation: AnimationConfig(
      effect: "sparkle_twinkle",
      speed: 0.29,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fbbf24",
      secondaryColor: "#ef4444",
      accentColor: "#3b82f6",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_children_s_day_14169",
    name: "Govee: Children's Day",
    category: "Celebrations",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Celebrations",
    isMultiHouse: false,
    badge: "Official #14169",
    description: "Authentic Govee hardware dynamic scene 'Children's Day' (sceneId 14169, paramId 22817).",
    animation: AnimationConfig(
      effect: "sparkle_twinkle",
      speed: 0.32,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fbbf24",
      secondaryColor: "#ef4444",
      accentColor: "#3b82f6",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_beer_festival_14170",
    name: "Govee: Beer Festival",
    category: "Celebrations",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Celebrations",
    isMultiHouse: false,
    badge: "Official #14170",
    description: "Authentic Govee hardware dynamic scene 'Beer Festival' (sceneId 14170, paramId 22818).",
    animation: AnimationConfig(
      effect: "sparkle_twinkle",
      speed: 0.35,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fbbf24",
      secondaryColor: "#ef4444",
      accentColor: "#3b82f6",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_music_show_14171",
    name: "Govee: Music Show",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #14171",
    description: "Authentic Govee hardware dynamic scene 'Music Show' (sceneId 14171, paramId 22819).",
    animation: AnimationConfig(
      effect: "govee_rainbow1",
      speed: 0.2,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#00f5d4",
      secondaryColor: "#7b2cbf",
      accentColor: "#ff007f",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_amusement_14172",
    name: "Govee: Amusement",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #14172",
    description: "Authentic Govee hardware dynamic scene 'Amusement' (sceneId 14172, paramId 22820).",
    animation: AnimationConfig(
      effect: "govee_rainbow2",
      speed: 0.23,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#38bdf8",
      secondaryColor: "#818cf8",
      accentColor: "#f472b6",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_confetti_14173",
    name: "Govee: Confetti",
    category: "Celebrations",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Celebrations",
    isMultiHouse: false,
    badge: "Official #14173",
    description: "Authentic Govee hardware dynamic scene 'Confetti' (sceneId 14173, paramId 22821).",
    animation: AnimationConfig(
      effect: "sparkle_twinkle",
      speed: 0.26,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fbbf24",
      secondaryColor: "#ef4444",
      accentColor: "#3b82f6",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_flower_parade_14174",
    name: "Govee: Flower Parade",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #14174",
    description: "Authentic Govee hardware dynamic scene 'Flower Parade' (sceneId 14174, paramId 22822).",
    animation: AnimationConfig(
      effect: "govee_rainbow2",
      speed: 0.29,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#10b981",
      secondaryColor: "#06b6d4",
      accentColor: "#3b82f6",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_halloween_14491",
    name: "Govee: Halloween II",
    category: "Halloween",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "Official #14491",
    description: "Authentic Govee hardware dynamic scene 'Halloween' (sceneId 14491, paramId 23302).",
    animation: AnimationConfig(
      effect: "halloween_spooky",
      speed: 0.32,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff6b00",
      secondaryColor: "#9333ea",
      accentColor: "#22c55e",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_delivering_gifts_14492",
    name: "Govee: Delivering Gifts",
    category: "Christmas",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "Official #14492",
    description: "Authentic Govee hardware dynamic scene 'Delivering Gifts' (sceneId 14492, paramId 23303).",
    animation: AnimationConfig(
      effect: "christmas_magic",
      speed: 0.35,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ef4444",
      secondaryColor: "#10b981",
      accentColor: "#ffffff",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_white_light_10789",
    name: "Govee: White Light",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #10789",
    description: "Authentic Govee hardware dynamic scene 'White Light' (sceneId 10789, paramId 17994).",
    animation: AnimationConfig(
      effect: "sparkle_twinkle",
      speed: 0.2,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#facc15",
      secondaryColor: "#f97316",
      accentColor: "#84cc16",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_bright_10791",
    name: "Govee: Bright",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #10791",
    description: "Authentic Govee hardware dynamic scene 'Bright' (sceneId 10791, paramId 17996).",
    animation: AnimationConfig(
      effect: "breathing_pulse",
      speed: 0.26,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff6b00",
      secondaryColor: "#9333ea",
      accentColor: "#22c55e",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_morning_10792",
    name: "Govee: Morning",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #10792",
    description: "Authentic Govee hardware dynamic scene 'Morning' (sceneId 10792, paramId 17997).",
    animation: AnimationConfig(
      effect: "halloween_spooky",
      speed: 0.29,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ef4444",
      secondaryColor: "#10b981",
      accentColor: "#fbbf24",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_afternoon_10793",
    name: "Govee: Afternoon",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #10793",
    description: "Authentic Govee hardware dynamic scene 'Afternoon' (sceneId 10793, paramId 17998).",
    animation: AnimationConfig(
      effect: "christmas_magic",
      speed: 0.32,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#00f5d4",
      secondaryColor: "#7b2cbf",
      accentColor: "#ff007f",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_twilight_10794",
    name: "Govee: Twilight",
    category: "Halloween",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "Official #10794",
    description: "Authentic Govee hardware dynamic scene 'Twilight' (sceneId 10794, paramId 17999).",
    animation: AnimationConfig(
      effect: "halloween_spooky",
      speed: 0.35,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff6b00",
      secondaryColor: "#9333ea",
      accentColor: "#22c55e",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_night_10795",
    name: "Govee: Night",
    category: "Halloween",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "Official #10795",
    description: "Authentic Govee hardware dynamic scene 'Night' (sceneId 10795, paramId 18000).",
    animation: AnimationConfig(
      effect: "halloween_spooky",
      speed: 0.2,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff6b00",
      secondaryColor: "#9333ea",
      accentColor: "#22c55e",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_leisure_10796",
    name: "Govee: Leisure",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #10796",
    description: "Authentic Govee hardware dynamic scene 'Leisure' (sceneId 10796, paramId 18001).",
    animation: AnimationConfig(
      effect: "govee_rainbow2",
      speed: 0.23,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#10b981",
      secondaryColor: "#06b6d4",
      accentColor: "#3b82f6",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_refreshing_10797",
    name: "Govee: Refreshing",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #10797",
    description: "Authentic Govee hardware dynamic scene 'Refreshing' (sceneId 10797, paramId 18002).",
    animation: AnimationConfig(
      effect: "multi_house_chase",
      speed: 0.26,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#d946ef",
      secondaryColor: "#8b5cf6",
      accentColor: "#00f5d4",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_candy_10798",
    name: "Govee: Candy",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #10798",
    description: "Authentic Govee hardware dynamic scene 'Candy' (sceneId 10798, paramId 18003).",
    animation: AnimationConfig(
      effect: "rainbow_wave",
      speed: 0.29,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff1744",
      secondaryColor: "#ffffff",
      accentColor: "#00e676",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_spin_10799",
    name: "Govee: Spin",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #10799",
    description: "Authentic Govee hardware dynamic scene 'Spin' (sceneId 10799, paramId 18004).",
    animation: AnimationConfig(
      effect: "comet_meteor",
      speed: 0.32,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#facc15",
      secondaryColor: "#f97316",
      accentColor: "#84cc16",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_dancing_10800",
    name: "Govee: Dancing",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #10800",
    description: "Authentic Govee hardware dynamic scene 'Dancing' (sceneId 10800, paramId 18005).",
    animation: AnimationConfig(
      effect: "theater_chase",
      speed: 0.35,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ec4899",
      secondaryColor: "#fbbf24",
      accentColor: "#06b6d4",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_sports_10801",
    name: "Govee: Sports",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #10801",
    description: "Authentic Govee hardware dynamic scene 'Sports' (sceneId 10801, paramId 18006).",
    animation: AnimationConfig(
      effect: "sparkle_twinkle",
      speed: 0.2,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff6b00",
      secondaryColor: "#9333ea",
      accentColor: "#22c55e",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_swing_10802",
    name: "Govee: Swing",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #10802",
    description: "Authentic Govee hardware dynamic scene 'Swing' (sceneId 10802, paramId 18007).",
    animation: AnimationConfig(
      effect: "fire_sparkle",
      speed: 0.23,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ef4444",
      secondaryColor: "#10b981",
      accentColor: "#fbbf24",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_colorful_10803",
    name: "Govee: Colorful",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #10803",
    description: "Authentic Govee hardware dynamic scene 'Colorful' (sceneId 10803, paramId 18008).",
    animation: AnimationConfig(
      effect: "govee_rainbow2",
      speed: 0.26,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#00f5d4",
      secondaryColor: "#7b2cbf",
      accentColor: "#ff007f",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_flow_10804",
    name: "Govee: Flow",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #10804",
    description: "Authentic Govee hardware dynamic scene 'Flow' (sceneId 10804, paramId 18009).",
    animation: AnimationConfig(
      effect: "govee_rainbow2",
      speed: 0.29,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#38bdf8",
      secondaryColor: "#818cf8",
      accentColor: "#f472b6",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_fluctuate_10805",
    name: "Govee: Fluctuate",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #10805",
    description: "Authentic Govee hardware dynamic scene 'Fluctuate' (sceneId 10805, paramId 18010).",
    animation: AnimationConfig(
      effect: "christmas_magic",
      speed: 0.32,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#f59e0b",
      secondaryColor: "#ef4444",
      accentColor: "#fde047",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_stacking_10806",
    name: "Govee: Stacking",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #10806",
    description: "Authentic Govee hardware dynamic scene 'Stacking' (sceneId 10806, paramId 18011).",
    animation: AnimationConfig(
      effect: "govee_rainbow2",
      speed: 0.35,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#10b981",
      secondaryColor: "#06b6d4",
      accentColor: "#3b82f6",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_beer_14493",
    name: "Govee: Beer",
    category: "Celebrations",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Celebrations",
    isMultiHouse: false,
    badge: "Official #14493",
    description: "Authentic Govee hardware dynamic scene 'Beer' (sceneId 14493, paramId 23304).",
    animation: AnimationConfig(
      effect: "sparkle_twinkle",
      speed: 0.2,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fbbf24",
      secondaryColor: "#ef4444",
      accentColor: "#3b82f6",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_gradient_10807",
    name: "Govee: Gradient",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #10807",
    description: "Authentic Govee hardware dynamic scene 'Gradient' (sceneId 10807, paramId 18012).",
    animation: AnimationConfig(
      effect: "govee_rainbow2",
      speed: 0.23,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff1744",
      secondaryColor: "#ffffff",
      accentColor: "#00e676",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_romantic_10808",
    name: "Govee: Romantic",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #10808",
    description: "Authentic Govee hardware dynamic scene 'Romantic' (sceneId 10808, paramId 18013).",
    animation: AnimationConfig(
      effect: "multi_house_chase",
      speed: 0.26,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#facc15",
      secondaryColor: "#f97316",
      accentColor: "#84cc16",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_quiet_10809",
    name: "Govee: Quiet",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #10809",
    description: "Authentic Govee hardware dynamic scene 'Quiet' (sceneId 10809, paramId 18014).",
    animation: AnimationConfig(
      effect: "rainbow_wave",
      speed: 0.29,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ec4899",
      secondaryColor: "#fbbf24",
      accentColor: "#06b6d4",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_happy_10810",
    name: "Govee: Happy",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #10810",
    description: "Authentic Govee hardware dynamic scene 'Happy' (sceneId 10810, paramId 18015).",
    animation: AnimationConfig(
      effect: "comet_meteor",
      speed: 0.32,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff6b00",
      secondaryColor: "#9333ea",
      accentColor: "#22c55e",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_profound_10811",
    name: "Govee: Profound",
    category: "Halloween",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "Official #10811",
    description: "Authentic Govee hardware dynamic scene 'Profound' (sceneId 10811, paramId 18016).",
    animation: AnimationConfig(
      effect: "halloween_spooky",
      speed: 0.35,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff6b00",
      secondaryColor: "#9333ea",
      accentColor: "#22c55e",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_enthusiastic_10812",
    name: "Govee: Enthusiastic",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #10812",
    description: "Authentic Govee hardware dynamic scene 'Enthusiastic' (sceneId 10812, paramId 18017).",
    animation: AnimationConfig(
      effect: "sparkle_twinkle",
      speed: 0.2,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#00f5d4",
      secondaryColor: "#7b2cbf",
      accentColor: "#ff007f",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_mysterious_10813",
    name: "Govee: Mysterious",
    category: "Halloween",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "Official #10813",
    description: "Authentic Govee hardware dynamic scene 'Mysterious' (sceneId 10813, paramId 18018).",
    animation: AnimationConfig(
      effect: "halloween_spooky",
      speed: 0.23,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff6b00",
      secondaryColor: "#9333ea",
      accentColor: "#22c55e",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_soothing_10814",
    name: "Govee: Soothing",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #10814",
    description: "Authentic Govee hardware dynamic scene 'Soothing' (sceneId 10814, paramId 18019).",
    animation: AnimationConfig(
      effect: "breathing_pulse",
      speed: 0.26,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#f59e0b",
      secondaryColor: "#ef4444",
      accentColor: "#fde047",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_dreamlike_10815",
    name: "Govee: Dreamlike",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #10815",
    description: "Authentic Govee hardware dynamic scene 'Dreamlike' (sceneId 10815, paramId 18020).",
    animation: AnimationConfig(
      effect: "halloween_spooky",
      speed: 0.29,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#10b981",
      secondaryColor: "#06b6d4",
      accentColor: "#3b82f6",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_warm_10816",
    name: "Govee: Warm",
    category: "Diwali",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Diwali",
    isMultiHouse: false,
    badge: "Official #10816",
    description: "Authentic Govee hardware dynamic scene 'Warm' (sceneId 10816, paramId 18021).",
    animation: AnimationConfig(
      effect: "diwali_festival",
      speed: 0.32,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#f59e0b",
      secondaryColor: "#fbbf24",
      accentColor: "#ef4444",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_leisurely_10817",
    name: "Govee: Leisurely",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #10817",
    description: "Authentic Govee hardware dynamic scene 'Leisurely' (sceneId 10817, paramId 18022).",
    animation: AnimationConfig(
      effect: "diwali_festival",
      speed: 0.35,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff1744",
      secondaryColor: "#ffffff",
      accentColor: "#00e676",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_dreamland_10818",
    name: "Govee: Dreamland",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #10818",
    description: "Authentic Govee hardware dynamic scene 'Dreamland' (sceneId 10818, paramId 18023).",
    animation: AnimationConfig(
      effect: "govee_rainbow1",
      speed: 0.2,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#facc15",
      secondaryColor: "#f97316",
      accentColor: "#84cc16",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_active_10819",
    name: "Govee: Active",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #10819",
    description: "Authentic Govee hardware dynamic scene 'Active' (sceneId 10819, paramId 18024).",
    animation: AnimationConfig(
      effect: "govee_rainbow2",
      speed: 0.23,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ec4899",
      secondaryColor: "#fbbf24",
      accentColor: "#06b6d4",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_hooray_14175",
    name: "Govee: Hooray",
    category: "Celebrations",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Celebrations",
    isMultiHouse: false,
    badge: "Official #14175",
    description: "Authentic Govee hardware dynamic scene 'Hooray' (sceneId 14175, paramId 22823).",
    animation: AnimationConfig(
      effect: "sparkle_twinkle",
      speed: 0.26,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fbbf24",
      secondaryColor: "#ef4444",
      accentColor: "#3b82f6",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_flash_23504",
    name: "Govee: Flash",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #23504",
    description: "Authentic Govee hardware dynamic scene 'Flash' (sceneId 23504, paramId 34012).",
    animation: AnimationConfig(
      effect: "lightning_storm",
      speed: 0.29,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ef4444",
      secondaryColor: "#10b981",
      accentColor: "#fbbf24",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_gary_23505",
    name: "Govee: Gary",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #23505",
    description: "Authentic Govee hardware dynamic scene 'Gary' (sceneId 23505, paramId 34013).",
    animation: AnimationConfig(
      effect: "comet_meteor",
      speed: 0.32,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#00f5d4",
      secondaryColor: "#7b2cbf",
      accentColor: "#ff007f",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_judy_23506",
    name: "Govee: Judy",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #23506",
    description: "Authentic Govee hardware dynamic scene 'Judy' (sceneId 23506, paramId 34014).",
    animation: AnimationConfig(
      effect: "theater_chase",
      speed: 0.35,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#38bdf8",
      secondaryColor: "#818cf8",
      accentColor: "#f472b6",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_nick_23507",
    name: "Govee: Nick",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #23507",
    description: "Authentic Govee hardware dynamic scene 'Nick' (sceneId 23507, paramId 34015).",
    animation: AnimationConfig(
      effect: "sparkle_twinkle",
      speed: 0.2,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#f59e0b",
      secondaryColor: "#ef4444",
      accentColor: "#fde047",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_zdp_duo_23508",
    name: "Govee: ZDP Duo",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #23508",
    description: "Authentic Govee hardware dynamic scene 'ZDP Duo' (sceneId 23508, paramId 34016).",
    animation: AnimationConfig(
      effect: "fire_sparkle",
      speed: 0.23,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#10b981",
      secondaryColor: "#06b6d4",
      accentColor: "#3b82f6",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_zdp_trio_23509",
    name: "Govee: ZDP Trio",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #23509",
    description: "Authentic Govee hardware dynamic scene 'ZDP Trio' (sceneId 23509, paramId 34017).",
    animation: AnimationConfig(
      effect: "breathing_pulse",
      speed: 0.26,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#d946ef",
      secondaryColor: "#8b5cf6",
      accentColor: "#00f5d4",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "govee_official_a_m_33896",
    name: "Govee: A&M",
    category: "Cyber & Party",
    subcategory: "Official Govee",
    sceneSource: "official",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "Official #33896",
    description: "Authentic Govee hardware dynamic scene 'A&M' (sceneId 33896, paramId 46134).",
    animation: AnimationConfig(
      effect: "halloween_spooky",
      speed: 0.29,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff1744",
      secondaryColor: "#ffffff",
      accentColor: "#00e676",
      backgroundColor: "#060814",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "halloween_haunted_chase",
    name: "Haunted Street Phantom Chase",
    category: "Halloween",
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "AI \u2022 Spooky",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "AI \u2022 Storm",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "AI \u2022 Gothic",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "AI \u2022 Classic",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Halloween",
    isMultiHouse: true,
    badge: "AI \u2022 Center-Out",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Halloween",
    isMultiHouse: true,
    badge: "AI \u2022 Dual Snake",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "AI \u2022 High Voltage",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "AI \u2022 Fast Bounce",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "AI \u2022 Twisted",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "AI \u2022 Inferno",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Halloween",
    isMultiHouse: true,
    badge: "AI \u2022 3 Carriages",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "AI \u2022 Takeover",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "AI \u2022 Venomous",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "AI \u2022 Lockstep",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Halloween",
    isMultiHouse: true,
    badge: "AI \u2022 Family Fun",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "AI \u2022 Mystic",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "AI \u2022 Rainbow 1 Style",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "AI \u2022 Rainbow 2 Style",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "AI \u2022 Rainbow 1 Style",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "AI \u2022 Rainbow 2 Style",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "AI \u2022 Rainbow 1 Style",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "AI \u2022 Rainbow 2 Style",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "AI \u2022 Rainbow 1 Style",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "AI \u2022 Rainbow 2 Style",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "AI \u2022 Rainbow 1 Style",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "AI \u2022 Rainbow 2 Style",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "AI \u2022 Rainbow 1 Style",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "AI \u2022 Rainbow 2 Style",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "AI \u2022 Holiday Magic",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Christmas",
    isMultiHouse: true,
    badge: "AI \u2022 Festive",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "AI \u2022 Snowfall",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "AI \u2022 Royal",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "AI \u2022 Reindeer Run",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Christmas",
    isMultiHouse: true,
    badge: "AI \u2022 Center-Out",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Christmas",
    isMultiHouse: true,
    badge: "AI \u2022 Dual Snake",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Christmas",
    isMultiHouse: true,
    badge: "AI \u2022 3 Coaches",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "AI \u2022 Sweet",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "AI \u2022 Snow Squall",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "AI \u2022 Fireside",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "AI \u2022 Progressive",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Christmas",
    isMultiHouse: true,
    badge: "AI \u2022 Center Star",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "AI \u2022 Enchanted",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "AI \u2022 Lockstep",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "AI \u2022 Rainbow 1 Style",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "AI \u2022 Rainbow 2 Style",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "AI \u2022 Rainbow 1 Style",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "AI \u2022 Rainbow 2 Style",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "AI \u2022 Rainbow 1 Style",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "AI \u2022 Rainbow 2 Style",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "AI \u2022 Rainbow 1 Style",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "AI \u2022 Rainbow 2 Style",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "AI \u2022 Rainbow 1 Style",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "AI \u2022 Rainbow 2 Style",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "AI \u2022 Rainbow 1 Style",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "AI \u2022 Rainbow 2 Style",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Christmas",
    isMultiHouse: true,
    badge: "AI \u2022 Epic Clash",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Diwali",
    isMultiHouse: false,
    badge: "AI \u2022 Shubh Deepavali",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Diwali",
    isMultiHouse: true,
    badge: "AI \u2022 Rangoli",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Diwali",
    isMultiHouse: false,
    badge: "AI \u2022 Phuljhari",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Diwali",
    isMultiHouse: false,
    badge: "AI \u2022 Aarti",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Center-Out (My House)",
    isMultiHouse: true,
    badge: "AI \u2022 Middle -> Out",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Center-Out (My House)",
    isMultiHouse: true,
    badge: "AI \u2022 Symmetrical",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Center-Out (My House)",
    isMultiHouse: true,
    badge: "AI \u2022 Dual Clash",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Cyber & Party",
    isMultiHouse: true,
    badge: "AI \u2022 Signature",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "AI \u2022 Ping-Pong",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "AI \u2022 Spectrum",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "AI \u2022 Ambient",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Celebrations",
    isMultiHouse: true,
    badge: "AI \u2022 Game Day",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Celebrations",
    isMultiHouse: false,
    badge: "AI \u2022 Fireworks",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Celebrations",
    isMultiHouse: false,
    badge: "AI \u2022 Marquee",
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
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Celebrations",
    isMultiHouse: false,
    badge: "AI \u2022 Warm Hearth",
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
  PresetScene(
    id: "ai_halloween_upside_down_rift",
    name: "Stranger Upside-Down Rift",
    category: "Halloween",
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "AI \u2022 Sci-Fi Horror",
    description: "Dimensional crimson lightning and deep shadow-portal indigo tearing across House 1 -> 2 -> 3.",
    animation: AnimationConfig(
      effect: "lightning_storm",
      speed: 0.36,
      direction: "pingpong",
      mappingMode: "house_normalized",
      primaryColor: "#ef4444",
      secondaryColor: "#6366f1",
      accentColor: "#38bdf8",
      backgroundColor: "#09020a",
      backgroundDim: 0.1,
      tailLength: 0.28,
      pulseCount: 3,
    ),
  ),
  PresetScene(
    id: "ai_halloween_proton_stream",
    name: "Ghostbusters Proton Stream",
    category: "Halloween",
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Halloween",
    isMultiHouse: true,
    badge: "AI \u2022 Plasma",
    description: "Crossed high-energy proton-pack orange-red beams with electric blue and Slimer green containment arcs.",
    animation: AnimationConfig(
      effect: "cyber_snake",
      speed: 0.38,
      direction: "pingpong",
      mappingMode: "house_normalized",
      primaryColor: "#ff4500",
      secondaryColor: "#00f5d4",
      accentColor: "#84cc16",
      backgroundColor: "#050814",
      backgroundDim: 0.08,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "ai_halloween_salem_blood_moon",
    name: "Salem Coven Blood Eclipse",
    category: "Halloween",
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Halloween",
    isMultiHouse: true,
    badge: "AI \u2022 Coven",
    description: "Deep eclipse crimson, witchcraft violet, and candlelit gold shockwaves radiating from the middle house.",
    animation: AnimationConfig(
      effect: "center_out_shockwave",
      speed: 0.24,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#dc2626",
      secondaryColor: "#7e22ce",
      accentColor: "#fbbf24",
      backgroundColor: "#110308",
      backgroundDim: 0.1,
      tailLength: 0.3,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "ai_halloween_cyber_jack",
    name: "Cyberpunk Jack-O'-Lantern 2099",
    category: "Halloween",
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "AI \u2022 Neon",
    description: "Hyper-saturated neon orange, ultraviolet magenta, and acid green Govee Rainbow 2 blocks.",
    animation: AnimationConfig(
      effect: "govee_rainbow2",
      speed: 0.32,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff6b00",
      secondaryColor: "#f43f5e",
      accentColor: "#39ff14",
      backgroundColor: "#080312",
      backgroundDim: 0.09,
      tailLength: 0.25,
      pulseCount: 3,
    ),
  ),
  PresetScene(
    id: "ai_halloween_banshee_mist",
    name: "Banshee Graveyard Fog",
    category: "Halloween",
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Halloween",
    isMultiHouse: false,
    badge: "AI \u2022 Haunt",
    description: "Silky spectral cyan, ghostly lavender, and pale moonlight breathing wave across all three rooflines.",
    animation: AnimationConfig(
      effect: "govee_rainbow1",
      speed: 0.19,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#2dd4bf",
      secondaryColor: "#a855f7",
      accentColor: "#e2e8f0",
      backgroundColor: "#040d12",
      backgroundDim: 0.1,
      tailLength: 0.32,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "ai_xmas_griswold_overload",
    name: "Griswold 25,000-Bulb Overload",
    category: "Christmas",
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "AI \u2022 Classic",
    description: "Dazzling high-density C9 warm white, ruby red, emerald green, and royal gold theater sparkle.",
    animation: AnimationConfig(
      effect: "sparkle_twinkle",
      speed: 0.35,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#fef08a",
      secondaryColor: "#ef4444",
      accentColor: "#10b981",
      backgroundColor: "#0d0804",
      backgroundDim: 0.12,
      tailLength: 0.24,
      pulseCount: 3,
    ),
  ),
  PresetScene(
    id: "ai_xmas_krampus_vs_santa",
    name: "Krampus vs. Santa Showdown",
    category: "Christmas",
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Christmas",
    isMultiHouse: true,
    badge: "AI \u2022 Duel",
    description: "Opposing icy North Pole cyan-white and fiery underworld crimson-gold serpents clashing at your middle house.",
    animation: AnimationConfig(
      effect: "cyber_snake",
      speed: 0.34,
      direction: "pingpong",
      mappingMode: "house_normalized",
      primaryColor: "#ef4444",
      secondaryColor: "#38bdf8",
      accentColor: "#fbbf24",
      backgroundColor: "#070b16",
      backgroundDim: 0.09,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "ai_xmas_elsa_ice_palace",
    name: "Frozen Ice Palace Crystal",
    category: "Christmas",
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Christmas",
    isMultiHouse: true,
    badge: "AI \u2022 Glacial",
    description: "Diamond-white, arctic cyan, and sapphire-violet crystal waves radiating outward from your house.",
    animation: AnimationConfig(
      effect: "center_out_shockwave",
      speed: 0.25,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#38bdf8",
      secondaryColor: "#e0f2fe",
      accentColor: "#818cf8",
      backgroundColor: "#030b18",
      backgroundDim: 0.1,
      tailLength: 0.28,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "ai_xmas_hot_cocoa_hearth",
    name: "Cinnamon & Fireside Cocoa",
    category: "Christmas",
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "AI \u2022 Cozy",
    description: "Warm marshmallow cream, cinnamon amber, and crackling hearth crimson embers.",
    animation: AnimationConfig(
      effect: "fire_sparkle",
      speed: 0.22,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#f97316",
      secondaryColor: "#fde68a",
      accentColor: "#dc2626",
      backgroundColor: "#120602",
      backgroundDim: 0.1,
      tailLength: 0.26,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "ai_xmas_nutcracker_finale",
    name: "Nutcracker Sugar-Plum Finale",
    category: "Christmas",
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Christmas",
    isMultiHouse: false,
    badge: "AI \u2022 Ballet",
    description: "Regal velvet crimson, imperial gold, and sugar-plum violet stepped Govee Rainbow 2 blocks.",
    animation: AnimationConfig(
      effect: "govee_rainbow2",
      speed: 0.28,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#dc2626",
      secondaryColor: "#fbbf24",
      accentColor: "#a855f7",
      backgroundColor: "#0c0410",
      backgroundDim: 0.09,
      tailLength: 0.25,
      pulseCount: 3,
    ),
  ),
  PresetScene(
    id: "ai_diwali_lotus_mandala",
    name: "Golden Lotus Mandala",
    category: "Diwali",
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Diwali",
    isMultiHouse: false,
    badge: "AI \u2022 Mandala",
    description: "Luminous lotus pink, saffron gold, and royal turquoise silk gradient flowing across all houses.",
    animation: AnimationConfig(
      effect: "govee_rainbow1",
      speed: 0.24,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ec4899",
      secondaryColor: "#fbbf24",
      accentColor: "#06b6d4",
      backgroundColor: "#12040c",
      backgroundDim: 0.1,
      tailLength: 0.28,
      pulseCount: 2,
    ),
  ),
  PresetScene(
    id: "ai_cyber_tokyo_drift",
    name: "Neo-Tokyo Midnight Drift",
    category: "Cyber & Party",
    subcategory: "AI & Custom",
    sceneSource: "ai_custom",
    holidayTag: "Cyber & Party",
    isMultiHouse: false,
    badge: "AI \u2022 Synthwave",
    description: "High-velocity synthwave laser magenta, electric cyan, and sunset orange comets.",
    animation: AnimationConfig(
      effect: "comet_meteor",
      speed: 0.42,
      direction: "forward",
      mappingMode: "house_normalized",
      primaryColor: "#ff007f",
      secondaryColor: "#00f5d4",
      accentColor: "#f97316",
      backgroundColor: "#050414",
      backgroundDim: 0.08,
      tailLength: 0.26,
      pulseCount: 3,
    ),
  ),
];
