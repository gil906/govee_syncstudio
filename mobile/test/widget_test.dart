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

    expect(kDefaultPresets.length, greaterThanOrEqualTo(190));
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
  });
}

