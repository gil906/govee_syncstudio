import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govee_lights_sync/main.dart';
import 'package:govee_lights_sync/models/govee_models.dart';
import 'package:govee_lights_sync/painters/three_house_painter.dart';
import 'package:govee_lights_sync/shaders/govee_shader.dart';

void main() {
  test('Shader evaluates all 16 multi-house effects + fallback and all 71 presets animate', () {
    const effects = [
      'multi_house_chase',
      'halloween_spooky',
      'christmas_magic',
      'diwali_festival',
      'center_out_shockwave',
      'lightning_storm',
      'cyber_snake',
      'rainbow_wave',
      'comet_meteor',
      'breathing_pulse',
      'color_wipe',
      'theater_chase',
      'fire_sparkle',
      'sparkle_twinkle',
      'govee_rainbow1',
      'govee_rainbow2',
      'custom_fallback_wave',
    ];
    for (final effect in effects) {
      final anim = AnimationConfig(effect: effect, running: true);
      final cLeft = evaluateEffectAtPoint(
        x: 0.15,
        unwrappedPhase: 0.35,
        elapsedSec: 1.4,
        anim: anim,
      );
      final cMiddle = evaluateEffectAtPoint(
        x: 0.50,
        unwrappedPhase: 0.35,
        elapsedSec: 1.4,
        anim: anim,
      );
      final cRight = evaluateEffectAtPoint(
        x: 0.85,
        unwrappedPhase: 0.35,
        elapsedSec: 1.4,
        anim: anim,
      );
      expect(cLeft.a, closeTo(1.0, 0.01));
      expect(cMiddle.a, closeTo(1.0, 0.01));
      expect(cRight.a, closeTo(1.0, 0.01));
    }

    expect(kDefaultPresets.length, greaterThanOrEqualTo(100));
    for (final preset in kDefaultPresets) {
      final c0 = evaluateEffectAtPoint(
        x: 0.20,
        unwrappedPhase: 0.10,
        elapsedSec: 0.4,
        anim: preset.animation.copyWith(running: true),
      );
      final c1 = evaluateEffectAtPoint(
        x: 0.55,
        unwrappedPhase: 0.62,
        elapsedSec: 2.5,
        anim: preset.animation.copyWith(running: true),
      );
      expect(c0.a, closeTo(1.0, 0.01));
      expect(c1.a, closeTo(1.0, 0.01));
    }
  });

  test('ScheduleConfig auto-detects timezone & DST and serializes days_of_week', () {
    final info = ScheduleConfig.detectPhoneTimezoneInfo();
    expect(info.ianaTimezone.isNotEmpty, isTrue);
    expect(info.utcOffset.isNotEmpty, isTrue);

    final sched = ScheduleConfig.fromJson({
      'enabled': true,
      'start_time': '17:30',
      'stop_time': '23:00',
      'preset_id': 'cyber_chase',
      'timezone': 'America/Los_Angeles',
      'days_of_week': ['mon', 'wed', 'fri'],
      'turn_off_lights_on_stop': true,
      'tz_abbrev': 'PDT',
      'dst_active': true,
    });
    expect(sched.enabled, isTrue);
    expect(sched.daysOfWeek, ['mon', 'wed', 'fri']);
    expect(sched.turnOffLightsOnStop, isTrue);
    expect(sched.tzAbbrev, 'PDT');
    expect(sched.dstActive, isTrue);
  });

  test('Per-house speed tween multiplier maps to timeWeight and resets to Auto Default', () async {
    const h = HouseConfig(id: 'house-2', name: 'My House', timeWeight: 1.0);
    expect(h.speedMultiplier, closeTo(1.0, 0.001));
    expect(h.isAutoDefaultSpeed, isTrue);

    final fastHouse = h.copyWith(timeWeight: 0.5);
    expect(fastHouse.speedMultiplier, closeTo(2.0, 0.001));
    expect(fastHouse.isAutoDefaultSpeed, isFalse);

    final slowHouse = h.copyWith(timeWeight: 2.0);
    expect(slowHouse.speedMultiplier, closeTo(0.5, 0.001));
    expect(slowHouse.isAutoDefaultSpeed, isFalse);
  });

  testWidgets('Galaxy Z Fold 7 Cover Screen (<560px) and Unfolded (>=560px) layouts render with GoveeSyncLogoBadge',
      (WidgetTester tester) async {
    // 1. Test Folded Cover Screen (width = 412)
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const GoveeSyncApp(enableNetworkOnInit: false));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Z FOLD 7 COVER'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(GoveeSyncLogoBadge), findsWidgets);

    // 2. Test Unfolded Inner Display (width = 760, realistic Z Fold 7 inner width in dp)
    tester.view.physicalSize = const Size(760, 980);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Z FOLD 7 STUDIO'), findsOneWidget);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('Live 3-House Animated Scene Gallery'), findsWidgets);
    expect(find.byType(Isometric3DScenePreview), findsWidgets);
    expect(find.text('🏗️ Design House & Lights'), findsWidgets);
  });

  test('HouseArchitecture defaults: exact 3 real Craftsman houses from photos, controller spans & Street X-Lock sync', () {
    final h1Arch = HouseArchitecture.defaultForHouse('house-1', 1);
    expect(h1Arch.presetStyle, 'craftsman_multi_section');
    expect(h1Arch.defaultViewMode, '3d');
    expect(h1Arch.sections.length, 7);
    expect(
      h1Arch.frontSections.any((s) => s.id == 'sec-upper-dormer' && s.shape == 'steep_gable' && s.story == 2),
      isTrue,
    );
    expect(
      h1Arch.frontSections.any((s) => s.id == 'sec-upper-right-eave' && s.shape == 'flat_eave' && s.story == 2),
      isTrue,
    );
    expect(
      h1Arch.frontSections.any((s) => s.id == 'sec-entry-gable' && s.shape == 'flat_eave' && s.hasDoor),
      isTrue,
    );
    expect(
      h1Arch.frontSections.any((s) => s.id == 'sec-garage-square' && s.shape == 'flat_eave' && s.hasGarage),
      isTrue,
    );

    final h2Arch = HouseArchitecture.defaultForHouse('house-2', 2);
    expect(h2Arch.presetStyle, 'a_frame_gable');
    expect(h2Arch.sections.length, 3);
    expect(h2Arch.sections.every((s) => s.wall == 'front'), isTrue);
    expect(
      h2Arch.frontSections.any((s) => s.id == 'sec-main-gable' && s.shape == 'triangle_gable' && s.story == 2),
      isTrue,
    );
    expect(
      h2Arch.frontSections.any((s) => s.id == 'sec-lower-garage-eave' && s.shape == 'flat_eave' && s.hasGarage),
      isTrue,
    );
    expect(
      h2Arch.frontSections.any((s) => s.id == 'sec-lower-porch-gable' && s.shape == 'triangle_gable' && s.hasDoor),
      isTrue,
    );

    final h3Arch = HouseArchitecture.defaultForHouse('house-3', 3);
    expect(h3Arch.presetStyle, 'two_story_estate');
    expect(h3Arch.sections.length, 6);
    expect(
      h3Arch.frontSections.any((s) => s.id == 'sec-left-tower-gable' && s.shape == 'dormer_peak'),
      isTrue,
    );
    expect(
      h3Arch.frontSections.any((s) => s.id == 'sec-center-flat-fascia' && s.shape == 'flat_eave'),
      isTrue,
    );
    expect(
      h3Arch.frontSections.any((s) => s.id == 'sec-right-garage-gable' && s.shape == 'flat_eave' && s.hasGarage && s.hasDoor),
      isTrue,
    );

    // Verify defaultThreeHouses Bottom-to-Top Counter-Clockwise (1F LTR -> 2F RTL) controller spans
    final sys = SystemConfig.defaultThreeHouses();

    final h1 = sys.houses.firstWhere((h) => h.id == 'house-1');
    expect(
      h1.architecture.frontSections.map((s) => (s.id, s.story)).toList(),
      [
        ('sec-entry-gable', 1),
        ('sec-garage-square', 1),
        ('sec-upper-right-eave', 2),
        ('sec-upper-dormer', 2),
      ],
    );
    final h1Ctrl1Spans = h1.effectiveControllerSpans(h1.controllers[0]);
    expect(
      h1Ctrl1Spans.map((sp) => (sp.sectionId, sp.segments, sp.direction)).toList(),
      [
        ('sec-entry-gable', 2, 'ltr'),
        ('sec-garage-square', 4, 'ltr'),
        ('sec-upper-right-eave', 2, 'rtl'),
        ('sec-upper-dormer', 4, 'rtl'),
      ],
    );
    final h1Ctrl2Spans = h1.effectiveControllerSpans(h1.controllers[1]);
    expect(
      h1Ctrl2Spans.map((sp) => (sp.sectionId, sp.segments, sp.direction)).toList(),
      [
        ('sec-right-eave', 4, 'ltr'),
        ('sec-back-eave', 4, 'rtl'),
        ('sec-left-eave', 4, 'rtl'),
      ],
    );

    final h2 = sys.houses.firstWhere((h) => h.id == 'house-2');
    expect(
      h2.architecture.frontSections.map((s) => (s.id, s.story)).toList(),
      [
        ('sec-lower-garage-eave', 1),
        ('sec-lower-porch-gable', 1),
        ('sec-main-gable', 2),
      ],
    );
    final h2Spans = h2.effectiveControllerSpans(h2.controllers.first);
    expect(
      h2Spans.map((sp) => (sp.sectionId, sp.segments, sp.direction)).toList(),
      [
        ('sec-lower-garage-eave', 2, 'ltr'),
        ('sec-lower-porch-gable', 2, 'ltr'),
        ('sec-main-gable', 5, 'rtl'),
      ],
    );

    final h3 = sys.houses.firstWhere((h) => h.id == 'house-3');
    expect(
      h3.architecture.frontSections.map((s) => (s.id, s.story)).toList(),
      [
        ('sec-right-garage-gable', 1),
        ('sec-center-flat-fascia', 2),
        ('sec-left-tower-gable', 2),
      ],
    );
    final h3Ctrl1Spans = h3.effectiveControllerSpans(h3.controllers[0]);
    expect(
      h3Ctrl1Spans.map((sp) => (sp.sectionId, sp.segments, sp.direction)).toList(),
      [
        ('sec-right-garage-gable', 7, 'ltr'),
        ('sec-center-flat-fascia', 6, 'rtl'),
        ('sec-left-tower-gable', 2, 'rtl'),
      ],
    );
    final h3Ctrl2Spans = h3.effectiveControllerSpans(h3.controllers[1]);
    expect(
      h3Ctrl2Spans.map((sp) => (sp.sectionId, sp.segments, sp.direction)).toList(),
      [
        ('sec-right-wing', 5, 'ltr'),
        ('sec-back-wing', 5, 'rtl'),
        ('sec-left-wing', 5, 'rtl'),
      ],
    );

    // Verify high-density sub-puck multipliers (45 pucks on House 2, 72-90 on Neighbors 1 & 2)
    expect(physicalSubPucksPerSegment(h2.totalSegments) * h2.totalSegments, 45);
    expect(
      physicalSubPucksPerSegment(h3.totalSegments, wall: 'front') * h3.totalSegments,
      90,
    );

    // Verify Street X-Lock ('front_street_sync'), 'ccw_loop', and 'bottom_to_top' compute colors cleanly
    for (final zMode in ['front_street_sync', 'ccw_loop', 'bottom_to_top', 'all_segments']) {
      final modeColors = computeHouseSegmentColors(
        house: h2,
        segCount: h2.totalSegments,
        houseStartNorm: 0.33,
        houseSpanNorm: 0.34,
        globalSegCursor: 24,
        totalAllSegs: 63,
        unwrappedPhase: 0.25,
        elapsedSec: 1.0,
        animation: AnimationConfig(
          running: true,
          effect: 'multi_house_chase',
          zoneMode: zMode,
        ),
      );
      expect(modeColors.length, 9);
    }

    // Verify all 5 architectural presets exist and serialize cleanly
    expect(HouseArchitecture.presets.keys, containsAll([
      'a_frame_gable',
      'craftsman_multi_section',
      'two_story_estate',
      'modern_stepped',
      'colonial_dormer',
    ]));

    final roundTrip = HouseArchitecture.fromJson(h2Arch.toJson());
    expect(roundTrip.presetStyle, 'a_frame_gable');
    expect(roundTrip.sections.length, h2Arch.sections.length);
  });
}

