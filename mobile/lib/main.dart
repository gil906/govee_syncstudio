import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/govee_models.dart';
import 'painters/three_house_painter.dart';
import 'services/govee_api_service.dart';
import 'shaders/govee_shader.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF040711),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const GoveeSyncApp());
}

class GoveeSyncApp extends StatefulWidget {
  final bool enableNetworkOnInit;

  const GoveeSyncApp({super.key, this.enableNetworkOnInit = true});

  @override
  State<GoveeSyncApp> createState() => _GoveeSyncAppState();
}

class _GoveeSyncAppState extends State<GoveeSyncApp> {
  late final GoveeApiService _api;

  @override
  void initState() {
    super.initState();
    _api = GoveeApiService();
    _api.initialize(enableNetwork: widget.enableNetworkOnInit);
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Govee Multi-House Sync Studio',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF040711),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00F5D4),
          secondary: Color(0xFF7B2CBF),
          tertiary: Color(0xFFFF007F),
          surface: Color(0xFF0B1325),
        ),
        useMaterial3: true,
        cardTheme: CardThemeData(
          color: const Color(0xFF0B1325).withValues(alpha: 0.92),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: const Color(0xFF334155).withValues(alpha: 0.55),
            ),
          ),
        ),
      ),
      home: GoveeStudioHomeScreen(api: _api),
    );
  }
}

class GoveeStudioHomeScreen extends StatefulWidget {
  final GoveeApiService api;

  const GoveeStudioHomeScreen({super.key, required this.api});

  @override
  State<GoveeStudioHomeScreen> createState() => _GoveeStudioHomeScreenState();
}

class _GoveeStudioHomeScreenState extends State<GoveeStudioHomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _masterClock;
  int _selectedNavIndex = 0; // 0: Studio/All, 1: Scenes, 2: Houses, 3: Pro & Access
  String _selectedCategory = 'All';

  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _newEmailController = TextEditingController();
  final TextEditingController _customUrlController = TextEditingController();

  static const List<Map<String, String>> _categories = [
    {'id': 'All', 'label': '✨ All Scenes'},
    {'id': 'Halloween', 'label': '🎃 Halloween'},
    {'id': 'Christmas', 'label': '🎄 Christmas'},
    {'id': 'Diwali', 'label': '🪔 Diwali'},
    {'id': 'Center-Out (My House)', 'label': '💥 Center-Out (My House)'},
    {'id': 'Cyber & Party', 'label': '⚡ Cyber & Party'},
    {'id': 'Celebrations', 'label': '🏈 Celebrations'},
  ];

  static const List<Map<String, String>> _effectsList = [
    {'id': 'multi_house_chase', 'label': 'Multi-House Chase (1 -> 2 -> 3)'},
    {'id': 'halloween_spooky', 'label': 'Halloween Phantom & Lightning'},
    {'id': 'christmas_magic', 'label': 'Christmas Candy Cane & Sleigh'},
    {'id': 'diwali_festival', 'label': 'Diwali Diya & Rangoli Cascade'},
    {'id': 'center_out_shockwave', 'label': 'Center-Out Shockwave (My House)'},
    {'id': 'lightning_storm', 'label': 'Rolling Thunder & Chain Lightning'},
    {'id': 'cyber_snake', 'label': 'Dual Neon Serpent Clash'},
    {'id': 'rainbow_wave', 'label': 'Seamless Rainbow Wave'},
    {'id': 'comet_meteor', 'label': 'Comet & Meteor Shower'},
    {'id': 'breathing_pulse', 'label': 'Harmonic Breathing Pulse'},
    {'id': 'color_wipe', 'label': '3-Stage Color Wipe'},
    {'id': 'theater_chase', 'label': 'Synchronized Theater Marquee'},
    {'id': 'fire_sparkle', 'label': 'Roaring Fire & Embers'},
    {'id': 'sparkle_twinkle', 'label': 'Aurora Starlight Sparkle'},
    {'id': 'govee_rainbow1', 'label': 'Govee Rainbow 1 (Seamless Gradient)'},
    {'id': 'govee_rainbow2', 'label': 'Govee Rainbow 2 (Stepped Color Blocks)'},
  ];

  @override
  void initState() {
    super.initState();
    _masterClock = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..repeat();
    _customUrlController.text = widget.api.baseUrl;
  }

  @override
  void dispose() {
    _masterClock.dispose();
    _tokenController.dispose();
    _newEmailController.dispose();
    _customUrlController.dispose();
    super.dispose();
  }

  List<PresetScene> get _filteredPresets {
    if (_selectedCategory == 'All') {
      return widget.api.presets;
    }
    return widget.api.presets
        .where((p) => p.category.toLowerCase() == _selectedCategory.toLowerCase())
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.api,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final bool isUnfoldedFoldable = constraints.maxWidth >= 560;
            return Scaffold(
              appBar: _buildTopAppBar(isUnfoldedFoldable),
              bottomNavigationBar:
                  isUnfoldedFoldable ? null : _buildCoverBottomNav(),
              body: SafeArea(
                child: Column(
                  children: [
                    if (widget.api.statusBanner != null) _buildStatusBanner(),
                    if (widget.api.needsSignIn) _buildAuthGateBanner(),
                    Expanded(
                      child: isUnfoldedFoldable
                          ? _buildUnfoldedDualPaneLayout(constraints.maxWidth)
                          : _buildFoldedCoverLayout(),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  PreferredSizeWidget _buildTopAppBar(bool isUnfoldedFoldable) {
    final running = widget.api.config.animation.running;
    final user = widget.api.authStatus.user;
    return AppBar(
      backgroundColor: const Color(0xFF060B18),
      elevation: 0,
      titleSpacing: 12,
      title: Row(
        children: [
          const GoveeSyncLogoBadge(size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Flexible(
                      child: Text(
                        'Govee Multi-House Sync',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: (isUnfoldedFoldable
                                  ? const Color(0xFF00F5D4)
                                  : const Color(0xFF38BDF8))
                              .withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: (isUnfoldedFoldable
                                    ? const Color(0xFF00F5D4)
                                    : const Color(0xFF38BDF8))
                                .withValues(alpha: 0.45),
                          ),
                        ),
                        child: Text(
                          isUnfoldedFoldable
                              ? 'Z FOLD 7 STUDIO'
                              : 'Z FOLD 7 COVER',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: isUnfoldedFoldable
                                ? const Color(0xFF00F5D4)
                                : const Color(0xFF38BDF8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  '${widget.api.baseUrl.replaceFirst("https://", "")} • ${running ? "LIVE ${widget.api.measuredFps.toStringAsFixed(0)} FPS" : "STOPPED / OFF"}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: running
                        ? const Color(0xFF00F5D4)
                        : const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (user != null)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ActionChip(
              avatar: const Icon(Icons.verified_user,
                  size: 15, color: Color(0xFF00F5D4)),
              label: Text(
                user.email.split('@').first,
                style: const TextStyle(fontSize: 11.5),
              ),
              backgroundColor: const Color(0xFF0F172A),
              onPressed: () => _showAuthModal(context),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilledButton.tonalIcon(
              onPressed: () => _showAuthModal(context),
              icon: const Icon(Icons.login, size: 16),
              label: const Text('Sign In', style: TextStyle(fontSize: 12)),
            ),
          ),
        IconButton(
          tooltip: 'Refresh Live State',
          onPressed: widget.api.refreshAll,
          icon: const Icon(Icons.sync, size: 20),
        ),
      ],
    );
  }

  Widget _buildStatusBanner() {
    final isErr = widget.api.statusIsError;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      color: isErr
          ? const Color(0xFF7F1D1D).withValues(alpha: 0.85)
          : const Color(0xFF064E3B).withValues(alpha: 0.75),
      child: Row(
        children: [
          Icon(
            isErr ? Icons.warning_amber_rounded : Icons.bolt,
            size: 16,
            color: isErr ? const Color(0xFFFCA5A5) : const Color(0xFF00F5D4),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.api.statusBanner ?? '',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          InkWell(
            onTap: () => widget.api.setBanner(null),
            child: const Icon(Icons.close, size: 16, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthGateBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1E1B4B).withValues(alpha: 0.9),
            const Color(0xFF0F172A).withValues(alpha: 0.95),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF00F5D4).withValues(alpha: 0.45),
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 8,
        children: [
          const Row(
            children: [
              GoveeSyncLogoBadge(size: 28),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Protected endpoint ($kDefaultBackendUrl) — Sign in with Google or GitHub ($kOwnerEmail)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00F5D4),
                  foregroundColor: const Color(0xFF040711),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: () => widget.api.launchOAuthSignIn('google'),
                icon: const Icon(Icons.account_circle, size: 16),
                label: const Text('Google',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: () => widget.api.launchOAuthSignIn('github'),
                icon: const Icon(Icons.code, size: 16),
                label: const Text('GitHub', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Paste Session Token',
                onPressed: () => _showAuthModal(context),
                icon: const Icon(Icons.key, size: 18, color: Color(0xFF00F5D4)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 1. FOLDED COVER SCREEN LAYOUT (width < 560)
  // ===========================================================================

  Widget _buildFoldedCoverLayout() {
    return Column(
      children: [
        // Pinned compact 3-house live roofline header card + thumb-friendly Play/Pause/Stop
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: _buildCompactPinnedVisualizerCard(),
        ),
        Expanded(
          child: IndexedStack(
            index: _selectedNavIndex,
            children: [
              // Tab 0: Studio (Sequence Order + Speed/Colors + 1-Tap Bursts)
              ListView(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                children: [
                  _buildStreetOrderSelectorCard(),
                  const SizedBox(height: 12),
                  _buildCelebrationBurstsCard(),
                  const SizedBox(height: 12),
                  _buildMasterShaderControlsCard(),
                ],
              ),
              // Tab 1: Live 3-House Animated Scene Gallery
              ListView(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                children: [
                  _buildScenesGallerySection(crossAxisCount: 1),
                ],
              ),
              // Tab 2: Houses, API Keys & Test Physical Light
              ListView(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                children: [
                  _buildHousesAndApiKeysSection(),
                ],
              ),
              // Tab 3: Pro Features & Authorized Users + Endpoint
              ListView(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                children: [
                  _buildProPlaylistAndScheduleCard(),
                  const SizedBox(height: 12),
                  _buildAuthorizedUsersCard(),
                  const SizedBox(height: 12),
                  _buildEndpointAndAuthCard(),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCoverBottomNav() {
    return NavigationBar(
      backgroundColor: const Color(0xFF060B18),
      indicatorColor: const Color(0xFF00F5D4).withValues(alpha: 0.20),
      selectedIndex: _selectedNavIndex,
      onDestinationSelected: (idx) => setState(() => _selectedNavIndex = idx),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.tune_outlined),
          selectedIcon: Icon(Icons.tune, color: Color(0xFF00F5D4)),
          label: 'Studio',
        ),
        NavigationDestination(
          icon: Icon(Icons.auto_awesome_mosaic_outlined),
          selectedIcon:
              Icon(Icons.auto_awesome_mosaic, color: Color(0xFF00F5D4)),
          label: 'Scenes',
        ),
        NavigationDestination(
          icon: Icon(Icons.home_work_outlined),
          selectedIcon: Icon(Icons.home_work, color: Color(0xFF00F5D4)),
          label: 'Houses',
        ),
        NavigationDestination(
          icon: Icon(Icons.admin_panel_settings_outlined),
          selectedIcon:
              Icon(Icons.admin_panel_settings, color: Color(0xFF00F5D4)),
          label: 'Pro & Access',
        ),
      ],
    );
  }

  // ===========================================================================
  // 2. UNFOLDED SAMSUNG GALAXY Z FOLD 7 SPACIOUS STUDIO LAYOUT (width >= 560)
  // ===========================================================================

  Widget _buildUnfoldedDualPaneLayout(double totalWidth) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NavigationRail(
          minWidth: 76,
          backgroundColor: const Color(0xFF060B18),
          selectedIndex: _selectedNavIndex,
          onDestinationSelected: (idx) =>
              setState(() => _selectedNavIndex = idx),
          labelType: NavigationRailLabelType.all,
          indicatorColor: const Color(0xFF00F5D4).withValues(alpha: 0.20),
          destinations: const [
            NavigationRailDestination(
              icon: Icon(Icons.dashboard_customize_outlined),
              selectedIcon:
                  Icon(Icons.dashboard_customize, color: Color(0xFF00F5D4)),
              label: Text('Studio &\nScenes', textAlign: TextAlign.center),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.auto_awesome_mosaic_outlined),
              selectedIcon:
                  Icon(Icons.auto_awesome_mosaic, color: Color(0xFF00F5D4)),
              label: Text('Scenes\nGallery', textAlign: TextAlign.center),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.home_work_outlined),
              selectedIcon: Icon(Icons.home_work, color: Color(0xFF00F5D4)),
              label: Text('Houses &\nOrder', textAlign: TextAlign.center),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.schedule_outlined),
              selectedIcon: Icon(Icons.schedule, color: Color(0xFF00F5D4)),
              label: Text('Schedule\n& Access', textAlign: TextAlign.center),
            ),
          ],
        ),
        const VerticalDivider(width: 1, color: Color(0xFF1E293B)),
        // FULL-WIDTH UNFOLDED WORKSPACE (640-780dp+ wide on Galaxy Z Fold 7)
        Expanded(
          child: IndexedStack(
            index: _selectedNavIndex,
            children: [
              // Destination 0: Studio & Scenes (2-Up Hero Row + 100%-Width Panoramic Scene Gallery)
              ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 6,
                        child: _buildDetailedVisualizerCard(
                          includeBurstsInline: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 5,
                        child: _buildUnfoldedHeroSceneTunerCard(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _buildScenesGallerySection(
                    crossAxisCount: 2,
                    unfoldedPanoramic: true,
                    showInlineTuner: false,
                  ),
                ],
              ),
              // Destination 1: Scenes Gallery (Full-Width Tuner Bar + Full-Width 2-Column Spacious Gallery)
              ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  _buildScenesGallerySection(
                    crossAxisCount: 2,
                    unfoldedPanoramic: true,
                    showInlineTuner: true,
                  ),
                ],
              ),
              // Destination 2: Houses & Order
              ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  _buildStreetOrderSelectorCard(),
                  const SizedBox(height: 14),
                  _buildHousesAndApiKeysSection(),
                ],
              ),
              // Destination 3: Schedule & Access
              ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  _buildProPlaylistAndScheduleCard(),
                  const SizedBox(height: 14),
                  _buildAuthorizedUsersCard(),
                  const SizedBox(height: 14),
                  _buildEndpointAndAuthCard(),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUnfoldedHeroSceneTunerCard() {
    final anim = widget.api.config.animation;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSelectedSceneInlineTuner(),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                          value: 'forward',
                          label: Text('1→2→3', style: TextStyle(fontSize: 11))),
                      ButtonSegment(
                          value: 'reverse',
                          label: Text('3→2→1', style: TextStyle(fontSize: 11))),
                      ButtonSegment(
                          value: 'pingpong',
                          label: Text('Bounce', style: TextStyle(fontSize: 11))),
                    ],
                    selected: {anim.direction},
                    onSelectionChanged: (sel) {
                      widget.api.patchAnimation({'direction': sel.first});
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Brightness: ${anim.intensity}%',
                  style: const TextStyle(fontSize: 11.5, color: Colors.white70),
                ),
                Expanded(
                  child: Slider(
                    value: anim.intensity.toDouble().clamp(5.0, 100.0),
                    min: 5,
                    max: 100,
                    divisions: 19,
                    activeColor: const Color(0xFF7B2CBF),
                    onChanged: (v) {
                      widget.api.patchAnimation({'intensity': v.round()});
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // LIVE 3-HOUSE VISUALIZER + TRANSPORT CONTROLS
  // ===========================================================================

  Widget _buildCompactPinnedVisualizerCard() {
    final anim = widget.api.config.animation;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            ThreeHouseScenePreview(
              clock: _masterClock,
              animation: anim,
              houses: widget.api.config.sortedHouses,
              liveHouseColors: widget.api.liveHouseColors,
              height: 82,
              compact: true,
            ),
            const SizedBox(height: 8),
            _buildThumbTransportButtons(compact: true),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailedVisualizerCard({bool includeBurstsInline = false}) {
    final anim = widget.api.config.animation;
    final houses = widget.api.config.sortedHouses;
    final enabledCount = houses.where((h) => h.enabled).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.auto_graph,
                          color: Color(0xFF00F5D4), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Live Multi-House Roofline Visualizer ($enabledCount/${houses.length} Active)',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: const Color(0xFF00F5D4).withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      widget.api.burstActive
                          ? '⚡ ${widget.api.burstLabel}'
                          : 'Effect: ${anim.effect}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF00F5D4),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ThreeHouseScenePreview(
              clock: _masterClock,
              animation: anim,
              houses: houses,
              liveHouseColors: widget.api.liveHouseColors,
              height: 142,
              compact: false,
            ),
            const SizedBox(height: 12),
            _buildThumbTransportButtons(compact: false),
            if (includeBurstsInline) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: kBurstProfiles.map((burst) {
                  return ActionChip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(burst.icon, size: 15, color: burst.color),
                    backgroundColor: const Color(0xFF060B18),
                    side: BorderSide(color: burst.color.withValues(alpha: 0.5)),
                    label: Text(
                      burst.label,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: () =>
                        widget.api.triggerCelebrationBurst(burst.id),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              _buildInlinePerHouseSpeedTweenStrip(houses),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInlinePerHouseSpeedTweenStrip(List<HouseConfig> houses) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF060B18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.speed_rounded,
                  color: Color(0xFF00F5D4), size: 16),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Per-House Speed Tween (By Light Count)',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF00F5D4),
                  ),
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: const Color(0xFFFBBF24),
                ),
                onPressed: () => widget.api.resetHouseSpeedToAutoDefault(),
                icon: const Icon(Icons.auto_fix_high, size: 14),
                label: const Text(
                  'Auto Default',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          for (final h in houses)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 118,
                    child: Text(
                      '#${h.order} ${h.name.split("(").first.trim()} (${h.totalSegments})',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            h.isMyHouse ? FontWeight.w800 : FontWeight.w600,
                        color: h.isMyHouse
                            ? const Color(0xFF00F5D4)
                            : Colors.white70,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6.5),
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 12),
                      ),
                      child: Slider(
                        value: h.speedMultiplier,
                        min: 0.30,
                        max: 3.00,
                        divisions: 54,
                        activeColor: h.isAutoDefaultSpeed
                            ? const Color(0xFF00F5D4)
                            : const Color(0xFFFBBF24),
                        onChanged: (v) =>
                            widget.api.setHouseSpeedMultiplier(h.id, v),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 68,
                    child: InkWell(
                      onTap: () => widget.api
                          .resetHouseSpeedToAutoDefault(houseId: h.id),
                      child: Text(
                        h.isAutoDefaultSpeed
                            ? '1.00x Auto'
                            : '${h.speedMultiplier.toStringAsFixed(2)}x',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: h.isAutoDefaultSpeed
                              ? const Color(0xFF00F5D4)
                              : const Color(0xFFFBBF24),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildThumbTransportButtons({required bool compact}) {
    final running = widget.api.config.animation.running;
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: running
                  ? const Color(0xFF059669)
                  : const Color(0xFF00F5D4),
              foregroundColor:
                  running ? Colors.white : const Color(0xFF040711),
              padding: EdgeInsets.symmetric(vertical: compact ? 10 : 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: widget.api.playAnimation,
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            label: Text(
              running ? 'Sync Active' : 'Start Sync',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFBBF24),
              side: BorderSide(
                color: const Color(0xFFFBBF24).withValues(alpha: 0.55),
              ),
              padding: EdgeInsets.symmetric(vertical: compact ? 10 : 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: widget.api.pauseAnimation,
            icon: const Icon(Icons.pause_rounded, size: 19),
            label: const Text(
              'Pause',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: compact ? 10 : 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: widget.api.stopAndTurnOff,
            icon: const Icon(Icons.power_settings_new_rounded, size: 19),
            label: Text(
              compact ? 'Stop & Off' : 'Stop & Turn Off',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // DYNAMIC 1..N STREET SEQUENCE REORDER + ENABLE/DISABLE HOUSES CARD
  // ===========================================================================

  String _slotPositionLabel(int slot, int total, HouseConfig house) {
    if (house.isMyHouse) {
      return '#${slot + 1} Middle (Me)';
    }
    if (slot == 0) return '#1 Left';
    if (slot == total - 1) return '#${slot + 1} Right';
    return '#${slot + 1} House';
  }

  Widget _buildStreetOrderSelectorCard() {
    final ordered = widget.api.config.sortedHouses;
    if (ordered.isEmpty) return const SizedBox.shrink();
    final enabledCount = ordered.where((h) => h.enabled).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.swap_horiz_rounded,
                    color: Color(0xFF00F5D4), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Street Sequence Order & Active Houses ($enabledCount/${ordered.length} On)',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => _showAddHouseDialog(context),
                  icon: const Icon(Icons.add_home_work_outlined, size: 15),
                  label: const Text(
                    '+ Add Neighbor House',
                    style:
                        TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF00F5D4),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () {
                    widget.api
                        .reorderHouses(['house-1', 'house-2', 'house-3']);
                  },
                  icon: const Icon(Icons.center_focus_strong, size: 15),
                  label: const Text(
                    'Reset #2',
                    style:
                        TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFFBBF24),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => widget.api.resetHouseSpeedToAutoDefault(),
                  icon: const Icon(Icons.auto_fix_high, size: 15),
                  label: const Text(
                    'Auto Default (By Light Count)',
                    style:
                        TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (int slot = 0; slot < ordered.length; slot++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: ordered[slot].isMyHouse
                        ? const Color(0xFF00F5D4).withValues(alpha: 0.08)
                        : const Color(0xFF060B18),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: ordered[slot].isMyHouse
                          ? const Color(0xFF00F5D4).withValues(alpha: 0.45)
                          : const Color(0xFF1E293B),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: ordered[slot].isMyHouse
                                  ? const Color(0xFF00F5D4)
                                  : const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _slotPositionLabel(
                                  slot, ordered.length, ordered[slot]),
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: ordered[slot].isMyHouse
                                    ? const Color(0xFF040711)
                                    : Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: ordered[slot].id,
                                isDense: true,
                                isExpanded: true,
                                items: ordered
                                    .map(
                                      (h) => DropdownMenuItem<String>(
                                        value: h.id,
                                        child: Text(
                                          '${h.name} (${h.totalSegments} segs)${h.enabled ? "" : " [OFF]"}',
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            color: h.enabled
                                                ? Colors.white
                                                : Colors.white54,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (chosenId) {
                                  if (chosenId == null ||
                                      chosenId == ordered[slot].id) {
                                    return;
                                  }
                                  final currentIds =
                                      ordered.map((h) => h.id).toList();
                                  final otherIdx = currentIds.indexOf(chosenId);
                                  if (otherIdx != -1) {
                                    final tmp = currentIds[slot];
                                    currentIds[slot] = currentIds[otherIdx];
                                    currentIds[otherIdx] = tmp;
                                    widget.api.reorderHouses(currentIds);
                                  }
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Tooltip(
                            message: ordered[slot].enabled
                                ? 'Disable house in sync'
                                : 'Enable house in sync',
                            child: Switch(
                              value: ordered[slot].enabled,
                              activeThumbColor: const Color(0xFF00F5D4),
                              onChanged: (val) => widget.api
                                  .toggleHouseEnabled(ordered[slot].id, val),
                            ),
                          ),
                          if (ordered.length > 1)
                            IconButton(
                              tooltip: 'Remove House',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.delete_outline,
                                  size: 18, color: Color(0xFFF87171)),
                              onPressed: () =>
                                  widget.api.deleteHouse(ordered[slot].id),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 2,
                        children: [
                          Text(
                            'House Speed: ${ordered[slot].speedMultiplier.toStringAsFixed(2)}x (${ordered[slot].isAutoDefaultSpeed ? "Auto-compensated for ${ordered[slot].totalSegments} segs" : "Custom Tween"})',
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF94A3B8)),
                          ),
                          InkWell(
                            onTap: () => widget.api.resetHouseSpeedToAutoDefault(
                                houseId: ordered[slot].id),
                            child: Text(
                              ordered[slot].isAutoDefaultSpeed
                                  ? '✓ Auto Default'
                                  : 'Reset Auto Default',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: ordered[slot].isAutoDefaultSpeed
                                    ? const Color(0xFF00F5D4)
                                    : const Color(0xFFFBBF24),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 7),
                          overlayShape:
                              const RoundSliderOverlayShape(overlayRadius: 14),
                        ),
                        child: Slider(
                          value: ordered[slot].speedMultiplier,
                          min: 0.30,
                          max: 3.00,
                          divisions: 54,
                          activeColor: ordered[slot].isAutoDefaultSpeed
                              ? const Color(0xFF00F5D4)
                              : const Color(0xFFFBBF24),
                          onChanged: (v) => widget.api
                              .setHouseSpeedMultiplier(ordered[slot].id, v),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // LIVE 3-HOUSE ANIMATED SCENE GALLERY
  // ===========================================================================

  Widget _buildScenesGallerySection({
    required int crossAxisCount,
    bool unfoldedPanoramic = false,
    bool showInlineTuner = true,
  }) {
    final scenes = _filteredPresets;
    final houses = widget.api.config.sortedHouses;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Live 3-House Animated Scene Gallery',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Every card renders how the animation flows across your active houses in real time',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00F5D4).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '${scenes.length} Scenes',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF00F5D4),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _categories.map((cat) {
                  final id = cat['id']!;
                  final selected = _selectedCategory == id;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      selected: selected,
                      selectedColor:
                          const Color(0xFF00F5D4).withValues(alpha: 0.22),
                      backgroundColor: const Color(0xFF060B18),
                      side: BorderSide(
                        color: selected
                            ? const Color(0xFF00F5D4)
                            : const Color(0xFF1E293B),
                      ),
                      label: Text(
                        cat['label']!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w600,
                          color: selected
                              ? const Color(0xFF00F5D4)
                              : const Color(0xFFCBD5E1),
                        ),
                      ),
                      onSelected: (_) =>
                          setState(() => _selectedCategory = id),
                    ),
                  );
                }).toList(),
              ),
            ),
            if (showInlineTuner) ...[
              const SizedBox(height: 10),
              _buildSelectedSceneInlineTuner(),
            ],
            const SizedBox(height: 12),
            if (unfoldedPanoramic)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: scenes.length,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 380,
                  mainAxisExtent: 238,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemBuilder: (context, idx) => _buildAnimatedSceneCard(
                  scenes[idx],
                  houses,
                  panoramicPreview: true,
                ),
              )
            else if (crossAxisCount <= 1)
              Column(
                children: scenes
                    .map((scene) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _buildAnimatedSceneCard(
                            scene,
                            houses,
                            panoramicPreview: false,
                          ),
                        ))
                    .toList(),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: scenes.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  mainAxisExtent: 212,
                ),
                itemBuilder: (context, idx) => _buildAnimatedSceneCard(
                  scenes[idx],
                  houses,
                  panoramicPreview: false,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedSceneCard(
    PresetScene scene,
    List<HouseConfig> houses, {
    bool panoramicPreview = false,
  }) {
    final isActive = widget.api.activePresetId == scene.id &&
        widget.api.config.animation.running;
    final primaryCol = hexToColor(scene.animation.primaryColor);
    final secondaryCol = hexToColor(scene.animation.secondaryColor);
    final accentCol = hexToColor(scene.animation.accentColor);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => widget.api.applyPreset(scene),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF0F243C)
              : const Color(0xFF060B18),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            width: isActive ? 1.8 : 1.0,
            color: isActive
                ? const Color(0xFF00F5D4)
                : const Color(0xFF1E293B),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Live Multi-House CustomPainter Preview right inside the Scene Card!
            ThreeHouseScenePreview(
              clock: _masterClock,
              animation: scene.animation.copyWith(running: true),
              houses: houses,
              height: panoramicPreview ? 104 : 82,
              compact: !panoramicPreview,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    scene.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _buildColorDot(primaryCol),
                const SizedBox(width: 3),
                _buildColorDot(secondaryCol),
                const SizedBox(width: 3),
                _buildColorDot(accentCol),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              scene.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF94A3B8),
                height: 1.25,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: primaryCol.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${scene.category} • ${scene.badge}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: primaryCol,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    isActive ? '● ACTIVE' : 'TAP TO SYNC',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: isActive
                          ? const Color(0xFF00F5D4)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _selectedColorChannel = 'primary_color';

  Widget _buildSelectedSceneInlineTuner() {
    final activeId = widget.api.activePresetId;
    PresetScene? activeScene;
    for (final p in widget.api.presets) {
      if (p.id == activeId) {
        activeScene = p;
        break;
      }
    }
    final anim = widget.api.config.animation;
    const swatches = [
      '#00f5d4',
      '#7b2cbf',
      '#ff007f',
      '#ef4444',
      '#10b981',
      '#fbbf24',
      '#38bdf8',
      '#f97316',
      '#9333ea',
      '#22c55e',
      '#ec4899',
      '#fde047',
      '#69be28',
      '#ffffff',
      '#060814',
    ];
    final currentHex = _selectedColorChannel == 'secondary_color'
        ? anim.secondaryColor
        : _selectedColorChannel == 'accent_color'
            ? anim.accentColor
            : _selectedColorChannel == 'background_color'
                ? anim.backgroundColor
                : anim.primaryColor;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF071324),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF00F5D4).withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded,
                  color: Color(0xFF00F5D4), size: 17),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Tune Selected Scene: ${activeScene?.name ?? "Active Scene"}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF00F5D4),
                  ),
                ),
              ),
              if (activeScene != null && activeScene.isCustomized)
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: const Color(0xFFFBBF24),
                  ),
                  onPressed: () =>
                      widget.api.resetPresetDefaults(activeScene!.id),
                  child: const Text(
                    'Reset Default',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                'Speed: ${anim.speed.toStringAsFixed(2)} Hz (${(1.0 / (anim.speed > 0 ? anim.speed : 0.25)).toStringAsFixed(1)}s cycle)',
                style: const TextStyle(fontSize: 11.5, color: Colors.white70),
              ),
              Wrap(
                spacing: 4,
                children: [
                  for (final sp in [
                    ('Slow', 0.14),
                    ('Norm', 0.25),
                    ('Fast', 0.45),
                    ('Hyper', 0.80),
                  ])
                    InkWell(
                      onTap: () => widget.api.patchAnimation({'speed': sp.$2}),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Text(
                          sp.$1,
                          style: const TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          Slider(
            value: anim.speed.clamp(0.05, 1.50),
            min: 0.05,
            max: 1.50,
            divisions: 29,
            activeColor: const Color(0xFF00F5D4),
            onChanged: (v) => widget.api.patchAnimation({'speed': v}),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final ch in [
                  ('primary_color', 'Lead Color 1', anim.primaryColor),
                  ('secondary_color', 'Mid Color 2', anim.secondaryColor),
                  ('accent_color', 'Tail Color 3', anim.accentColor),
                  ('background_color', 'Base Glow', anim.backgroundColor),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      selected: _selectedColorChannel == ch.$1,
                      selectedColor:
                          const Color(0xFF00F5D4).withValues(alpha: 0.2),
                      backgroundColor: const Color(0xFF060B18),
                      avatar: _buildColorDot(hexToColor(ch.$3)),
                      label: Text(
                        ch.$2,
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                      onSelected: (_) =>
                          setState(() => _selectedColorChannel = ch.$1),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: swatches.map((hex) {
              final col = hexToColor(hex);
              final isSel = currentHex.toLowerCase() == hex.toLowerCase();
              return GestureDetector(
                onTap: () =>
                    widget.api.patchAnimation({_selectedColorChannel: hex}),
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: col,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSel ? Colors.white : Colors.white24,
                      width: isSel ? 2.5 : 1.0,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildColorDot(Color c) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24, width: 0.8),
      ),
    );
  }

  // ===========================================================================
  // 1-TAP CELEBRATION BURSTS CARD
  // ===========================================================================

  Widget _buildCelebrationBurstsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.celebration, color: Color(0xFFFBBF24), size: 19),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '1-Tap Street Celebration Bursts (12s)',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kBurstProfiles.map((burst) {
                return ActionChip(
                  avatar: Icon(burst.icon, size: 16, color: burst.color),
                  backgroundColor: const Color(0xFF060B18),
                  side: BorderSide(color: burst.color.withValues(alpha: 0.5)),
                  label: Text(
                    burst.label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onPressed: () =>
                      widget.api.triggerCelebrationBurst(burst.id),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // MASTER SHADER & COLOR CONTROLS CARD
  // ===========================================================================

  Widget _buildMasterShaderControlsCard() {
    final anim = widget.api.config.animation;
    const paletteSwatches = [
      '#00f5d4',
      '#7b2cbf',
      '#ff007f',
      '#ef4444',
      '#10b981',
      '#fbbf24',
      '#38bdf8',
      '#f97316',
      '#69be28',
      '#ffffff',
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.tune, color: Color(0xFF00F5D4), size: 19),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Master Clock, Speed, Direction & Colors',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _effectsList.any((e) => e['id'] == anim.effect)
                  ? anim.effect
                  : 'multi_house_chase',
              decoration: const InputDecoration(
                labelText: 'Active Multi-House Effect Shader',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: _effectsList
                  .map(
                    (e) => DropdownMenuItem<String>(
                      value: e['id'],
                      child: Text(
                        e['label']!,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (val) {
                if (val != null) {
                  widget.api.patchAnimation({'effect': val});
                }
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                          value: 'forward',
                          label: Text('1→2→3', style: TextStyle(fontSize: 11))),
                      ButtonSegment(
                          value: 'reverse',
                          label: Text('3→2→1', style: TextStyle(fontSize: 11))),
                      ButtonSegment(
                          value: 'pingpong',
                          label: Text('Bounce', style: TextStyle(fontSize: 11))),
                    ],
                    selected: {anim.direction},
                    onSelectionChanged: (sel) {
                      widget.api.patchAnimation({'direction': sel.first});
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(
                  'Speed: ${anim.speed.toStringAsFixed(2)} cyc/s (${(1.0 / (anim.speed > 0 ? anim.speed : 0.25)).toStringAsFixed(1)}s)',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  'Brightness: ${anim.intensity}%',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
            Slider(
              value: anim.speed.clamp(0.05, 2.0),
              min: 0.05,
              max: 2.0,
              divisions: 39,
              activeColor: const Color(0xFF00F5D4),
              onChanged: (v) {
                widget.api.patchAnimation({'speed': v});
              },
            ),
            Slider(
              value: anim.intensity.toDouble().clamp(5.0, 100.0),
              min: 5,
              max: 100,
              divisions: 19,
              activeColor: const Color(0xFF7B2CBF),
              onChanged: (v) {
                widget.api.patchAnimation({'intensity': v.round()});
              },
            ),
            const SizedBox(height: 4),
            const Text(
              'Quick Primary Color Palette:',
              style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: paletteSwatches.map((hex) {
                final col = hexToColor(hex);
                final selected =
                    anim.primaryColor.toLowerCase() == hex.toLowerCase();
                return GestureDetector(
                  onTap: () =>
                      widget.api.patchAnimation({'primary_color': hex}),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: col,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? Colors.white : Colors.white24,
                        width: selected ? 2.5 : 1.0,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // PER-HOUSE CREDENTIALS, API KEYS & TEST PHYSICAL LIGHT SECTION
  // ===========================================================================

  Widget _buildHousesAndApiKeysSection() {
    final houses = widget.api.config.sortedHouses;
    final enabledCount = houses.where((h) => h.enabled).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.vpn_key_rounded,
                    color: Color(0xFF00F5D4), size: 19),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Houses, Govee API Keys & Physical Light Test ($enabledCount/${houses.length} Enabled)',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00F5D4),
                    foregroundColor: const Color(0xFF040711),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => _showAddHouseDialog(context),
                  icon: const Icon(Icons.add_home_work_rounded, size: 16),
                  label: const Text(
                    '+ Add House',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Enable or disable any house to run animations on 1, 2, 3, or 4+ houses, configure Govee Cloud OpenAPI keys, auto-discover Cloud controllers, or send a 1-tap physical test pulse.',
              style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 12),
            for (final house in houses)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _HouseEditorCard(
                  house: house,
                  api: widget.api,
                  canDelete: houses.length > 1,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showAddHouseDialog(BuildContext context) {
    final nextNum = widget.api.config.houses.length + 1;
    final nameCtrl =
        TextEditingController(text: 'Neighbor $nextNum (House #$nextNum)');
    final segCtrl = TextEditingController(text: '12');
    final keyCtrl = TextEditingController();
    String connType = 'govee_cloud';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF0B1325),
              title: const Row(
                children: [
                  GoveeSyncLogoBadge(size: 30),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Add Neighbor House',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'House Display Name',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: connType,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Connection Mode',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'govee_cloud',
                                child: Text('Govee Cloud API',
                                    style: TextStyle(fontSize: 12.5)),
                              ),
                              DropdownMenuItem(
                                value: 'local_lan',
                                child: Text('Local LAN UDP',
                                    style: TextStyle(fontSize: 12.5)),
                              ),
                              DropdownMenuItem(
                                value: 'neighbor_bridge',
                                child: Text('Neighbor Bridge',
                                    style: TextStyle(fontSize: 12.5)),
                              ),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setModalState(() => connType = v);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 96,
                          child: TextField(
                            controller: segCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Segments',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: keyCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Optional Govee Cloud API Key',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00F5D4),
                    foregroundColor: const Color(0xFF040711),
                  ),
                  onPressed: () {
                    final segs = int.tryParse(segCtrl.text.trim()) ?? 12;
                    widget.api.addHouse(
                      name: nameCtrl.text.trim(),
                      segmentCount: segs.clamp(1, 200),
                      connectionType: connType,
                      goveeApiKey: keyCtrl.text.trim(),
                    );
                    Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.add, size: 17),
                  label: const Text(
                    'Add House',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ===========================================================================
  // PRO FEATURES: PLAYLIST JUKEBOX & 24/7 AUTONOMOUS CONTAINER SCHEDULE
  // ===========================================================================

  Future<void> _pickScheduleTime(
      BuildContext context, String currentHhMm, String fieldKey) async {
    int hour = 17;
    int minute = 30;
    final parts = currentHhMm.split(':');
    if (parts.length == 2) {
      hour = int.tryParse(parts[0]) ?? hour;
      minute = int.tryParse(parts[1]) ?? minute;
    }
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hour.clamp(0, 23), minute: minute.clamp(0, 59)),
    );
    if (picked != null) {
      final formatted =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      widget.api.patchSchedule({fieldKey: formatted});
    }
  }

  Widget _buildProPlaylistAndScheduleCard() {
    final playlist = widget.api.config.playlist;
    final schedule = widget.api.config.schedule;
    final presets = widget.api.presets;
    const dayDefinitions = [
      ('mon', 'M'),
      ('tue', 'T'),
      ('wed', 'W'),
      ('thu', 'T'),
      ('fri', 'F'),
      ('sat', 'S'),
      ('sun', 'S'),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.schedule_send_rounded,
                    color: Color(0xFF00F5D4), size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Autonomous 24/7 Schedule & Playlist Jukebox',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Prominent Green Autonomous Container Daemon Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF065F46).withValues(alpha: 0.55),
                    const Color(0xFF064E3B).withValues(alpha: 0.35),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF10B981).withValues(alpha: 0.65),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.cloud_done_rounded,
                          color: Color(0xFF34D399), size: 17),
                      SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          '24/7 Autonomous Server Schedule — Runs in Container Without Phone/App',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF6EE7B7),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF040711).withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color:
                                const Color(0xFF00F5D4).withValues(alpha: 0.45),
                          ),
                        ),
                        child: Text(
                          '${schedule.timezone} • ${schedule.tzAbbrev} (${schedule.dstActive ? "DST Active" : "Standard Time"}, UTC${schedule.utcOffset})',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF00F5D4),
                          ),
                        ),
                      ),
                      if (schedule.currentLocalTime.isNotEmpty)
                        Text(
                          'Server Clock: ${schedule.currentLocalTime}',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white70),
                        ),
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: widget.api.autoDetectTimezoneAndDst,
                        icon: const Icon(Icons.my_location, size: 14),
                        label: const Text(
                          'Auto-Detect Timezone & DST',
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Enable Daily Autonomous Schedule',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                'Turns ON ${schedule.startTime} • Stops ${schedule.stopTime} (${schedule.timezone})',
                style: const TextStyle(fontSize: 11.5),
              ),
              value: schedule.enabled,
              activeThumbColor: const Color(0xFF00F5D4),
              onChanged: (val) =>
                  widget.api.patchSchedule({'enabled': val}),
            ),
            const SizedBox(height: 6),
            // Turn ON Time & Turn OFF Time Pickers
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                      side: BorderSide(
                        color: const Color(0xFF00F5D4).withValues(alpha: 0.45),
                      ),
                    ),
                    onPressed: () => _pickScheduleTime(
                        context, schedule.startTime, 'start_time'),
                    icon: const Icon(Icons.wb_twilight_rounded,
                        size: 17, color: Color(0xFF00F5D4)),
                    label: Text(
                      'Turn ON: ${schedule.startTime}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                      side: BorderSide(
                        color: const Color(0xFFFBBF24).withValues(alpha: 0.45),
                      ),
                    ),
                    onPressed: () => _pickScheduleTime(
                        context, schedule.stopTime, 'stop_time'),
                    icon: const Icon(Icons.bedtime_outlined,
                        size: 17, color: Color(0xFFFBBF24)),
                    label: Text(
                      'Turn OFF: ${schedule.stopTime}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Active Days of Week (M T W T F S S):',
              style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: dayDefinitions.map((day) {
                final code = day.$1;
                final label = day.$2;
                final isSelected = schedule.daysOfWeek.contains(code);
                return FilterChip(
                  visualDensity: VisualDensity.compact,
                  selected: isSelected,
                  selectedColor:
                      const Color(0xFF00F5D4).withValues(alpha: 0.24),
                  checkmarkColor: const Color(0xFF00F5D4),
                  label: Text(
                    '$label (${code.toUpperCase()})',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight:
                          isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected
                          ? const Color(0xFF00F5D4)
                          : Colors.white70,
                    ),
                  ),
                  onSelected: (sel) {
                    final nextDays = List<String>.from(schedule.daysOfWeek);
                    if (sel && !nextDays.contains(code)) {
                      nextDays.add(code);
                    } else if (!sel && nextDays.length > 1) {
                      nextDays.remove(code);
                    }
                    widget.api.patchSchedule({'days_of_week': nextDays});
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: presets.any((p) => p.id == schedule.presetId)
                  ? schedule.presetId
                  : (presets.isNotEmpty ? presets.first.id : 'cyber_chase'),
              decoration: const InputDecoration(
                labelText: 'Scheduled Scene Preset to Run at Turn-ON',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: presets
                  .map(
                    (p) => DropdownMenuItem<String>(
                      value: p.id,
                      child: Text(
                        '${p.name} (${p.category})',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (val) {
                if (val != null) {
                  widget.api.patchSchedule({'preset_id': val});
                }
              },
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Turn Off Physical Lights at Stop Time',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'Sends hardware power OFF (turn:0 + blackout) to all controllers at stop time',
                style: TextStyle(fontSize: 11),
              ),
              value: schedule.turnOffLightsOnStop,
              activeThumbColor: const Color(0xFF00F5D4),
              onChanged: (val) => widget.api
                  .patchSchedule({'turn_off_lights_on_stop': val}),
            ),
            const Divider(height: 22),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Automatic Playlist Jukebox Rotation',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                'Cycles through ${playlist.presetIds.length} holiday & party scenes every ${playlist.intervalSec}s',
                style: const TextStyle(fontSize: 11.5),
              ),
              value: playlist.enabled,
              activeThumbColor: const Color(0xFF00F5D4),
              onChanged: (val) =>
                  widget.api.patchPlaylist({'enabled': val}),
            ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [
                const Text('Rotate every:', style: TextStyle(fontSize: 12)),
                for (final sec in [30, 60, 180, 300])
                  ChoiceChip(
                    label:
                        Text('${sec}s', style: const TextStyle(fontSize: 11)),
                    selected: playlist.intervalSec == sec,
                    onSelected: (_) =>
                        widget.api.patchPlaylist({'interval_sec': sec}),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // AUTHORIZED EMAILS MANAGER (OWNER)
  // ===========================================================================

  Widget _buildAuthorizedUsersCard() {
    final emails = widget.api.authorizedEmails;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.shield_outlined,
                    color: Color(0xFF00F5D4), size: 19),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Authorized Users & Access Control',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Only $kOwnerEmail (Owner) and authorized emails below can sign in via Google or GitHub on $kDefaultBackendUrl.',
              style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newEmailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      hintText: 'neighbor@example.com',
                      labelText: 'Add Authorized Email',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00F5D4),
                    foregroundColor: const Color(0xFF040711),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 13),
                  ),
                  onPressed: () {
                    final em = _newEmailController.text.trim();
                    if (em.isNotEmpty) {
                      widget.api.addAuthorizedEmail(em);
                      _newEmailController.clear();
                    }
                  },
                  icon: const Icon(Icons.person_add_alt_1, size: 17),
                  label: const Text('Authorize',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: emails.map((email) {
                final isOwner = email.toLowerCase() == kOwnerEmail;
                return Chip(
                  avatar: Icon(
                    isOwner ? Icons.star_rounded : Icons.check_circle_outline,
                    size: 16,
                    color: isOwner
                        ? const Color(0xFFFBBF24)
                        : const Color(0xFF00F5D4),
                  ),
                  label: Text(
                    isOwner ? '$email (Owner)' : email,
                    style: const TextStyle(fontSize: 12),
                  ),
                  onDeleted: isOwner
                      ? null
                      : () => widget.api.removeAuthorizedEmail(email),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // ENDPOINT SWITCHER & OAUTH / SESSION TOKEN CARD
  // ===========================================================================

  Widget _buildEndpointAndAuthCard() {
    final isCloudDefault = widget.api.baseUrl == kDefaultBackendUrl;
    final isLan = widget.api.baseUrl == kLanBackendUrl;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.cloud_sync_outlined,
                    color: Color(0xFF00F5D4), size: 19),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Server Endpoint & OAuth Session',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  selected: isCloudDefault,
                  label: const Text('Cloud ($kDefaultBackendUrl)'),
                  onSelected: (_) {
                    _customUrlController.text = kDefaultBackendUrl;
                    widget.api.setBackendUrl(kDefaultBackendUrl);
                  },
                ),
                ChoiceChip(
                  selected: isLan,
                  label: const Text('LAN Direct ($kLanBackendUrl)'),
                  onSelected: (_) {
                    _customUrlController.text = kLanBackendUrl;
                    widget.api.setBackendUrl(kLanBackendUrl);
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Backend Endpoint URL',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () =>
                      widget.api.setBackendUrl(_customUrlController.text),
                  child: const Text('Connect'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => widget.api.launchOAuthSignIn('google'),
                    icon: const Icon(Icons.account_circle, size: 18),
                    label: const Text('Google Sign-In'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => widget.api.launchOAuthSignIn('github'),
                    icon: const Icon(Icons.code, size: 18),
                    label: const Text('GitHub Sign-In'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAuthModal(BuildContext context) {
    final user = widget.api.authStatus.user;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B1325),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Row(
                      children: [
                        GoveeSyncLogoBadge(size: 34),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Govee Sync Studio Authentication',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              if (user != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF060B18),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF00F5D4).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.verified_user,
                          color: Color(0xFF00F5D4), size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              '${user.email} (${user.isOwner ? "Owner" : "Authorized"})',
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          widget.api.logout();
                          Navigator.pop(ctx);
                        },
                        child: const Text('Sign Out',
                            style: TextStyle(color: Color(0xFFF87171))),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              const Text(
                'Sign in with an authorized account ($kOwnerEmail) via browser OAuth handoff (goveesync://auth) or paste a 30-day session token:',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00F5D4),
                        foregroundColor: const Color(0xFF040711),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        widget.api.launchOAuthSignIn('google');
                      },
                      icon: const Icon(Icons.account_circle),
                      label: const Text('Google OAuth',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        widget.api.launchOAuthSignIn('github');
                      },
                      icon: const Icon(Icons.code),
                      label: const Text('GitHub OAuth',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _tokenController,
                      decoration: const InputDecoration(
                        labelText: 'Or Paste Session Token',
                        hintText: 'eyJhbGciOi...',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Paste from Clipboard',
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text != null) {
                        _tokenController.text = data!.text!.trim();
                      }
                    },
                    icon: const Icon(Icons.content_paste),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      final tok = _tokenController.text.trim();
                      if (tok.isNotEmpty) {
                        widget.api.setAuthToken(tok);
                        Navigator.pop(ctx);
                      }
                    },
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HouseEditorCard extends StatefulWidget {
  final HouseConfig house;
  final GoveeApiService api;
  final bool canDelete;

  const _HouseEditorCard({
    required this.house,
    required this.api,
    this.canDelete = false,
  });

  @override
  State<_HouseEditorCard> createState() => _HouseEditorCardState();
}

class _HouseEditorCardState extends State<_HouseEditorCard> {
  late final TextEditingController _apiKeyCtrl;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _apiKeyCtrl = TextEditingController(text: widget.house.goveeApiKey);
  }

  @override
  void didUpdateWidget(covariant _HouseEditorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.house.goveeApiKey != widget.house.goveeApiKey &&
        _apiKeyCtrl.text != widget.house.goveeApiKey) {
      _apiKeyCtrl.text = widget.house.goveeApiKey;
    }
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final house = widget.house;
    final isMe = house.isMyHouse;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF060B18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isMe
              ? const Color(0xFF00F5D4).withValues(alpha: 0.55)
              : const Color(0xFF1E293B),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: isMe
                            ? const Color(0xFF00F5D4)
                            : const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '#${house.order}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: isMe ? const Color(0xFF040711) : Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        house.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: house.enabled ? Colors.white : Colors.white54,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${house.totalSegments} segs • ${house.connectionType}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF00F5D4),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Switch(
                    value: house.enabled,
                    activeThumbColor: const Color(0xFF00F5D4),
                    onChanged: (val) =>
                        widget.api.toggleHouseEnabled(house.id, val),
                  ),
                  if (widget.canDelete)
                    IconButton(
                      tooltip: 'Remove House',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.delete_outline,
                          size: 18, color: Color(0xFFF87171)),
                      onPressed: () => widget.api.deleteHouse(house.id),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0B1325),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: house.isAutoDefaultSpeed
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFFBBF24).withValues(alpha: 0.45),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      'Speed by House: ${house.speedMultiplier.toStringAsFixed(2)}x (${house.isAutoDefaultSpeed ? "Auto Default for ${house.totalSegments} lights" : "Custom Tween"})',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                      ),
                      onPressed: () => widget.api
                          .resetHouseSpeedToAutoDefault(houseId: house.id),
                      icon: const Icon(Icons.auto_fix_high, size: 14),
                      label: const Text(
                        'Auto Default (By Light Count)',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: house.speedMultiplier,
                  min: 0.30,
                  max: 3.00,
                  divisions: 54,
                  activeColor: house.isAutoDefaultSpeed
                      ? const Color(0xFF00F5D4)
                      : const Color(0xFFFBBF24),
                  label: '${house.speedMultiplier.toStringAsFixed(2)}x',
                  onChanged: (v) =>
                      widget.api.setHouseSpeedMultiplier(house.id, v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _apiKeyCtrl,
            obscureText: _obscureKey,
            decoration: InputDecoration(
              labelText: 'Govee Cloud API Key (${house.name})',
              hintText: 'Paste Govee OpenAPI Key…',
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureKey ? Icons.visibility : Icons.visibility_off,
                  size: 17,
                ),
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  final updatedHouses = widget.api.config.houses.map((h) {
                    if (h.id == house.id) {
                      return h.copyWith(goveeApiKey: _apiKeyCtrl.text.trim());
                    }
                    return h;
                  }).toList();
                  widget.api.saveHouses(updatedHouses);
                },
                icon: const Icon(Icons.save_outlined, size: 16),
                label: const Text('Save Key', style: TextStyle(fontSize: 12)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7B2CBF),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => widget.api.discoverHouseCloudDevices(
                  house.id,
                  _apiKeyCtrl.text.trim(),
                ),
                icon: const Icon(Icons.cloud_download_outlined, size: 16),
                label: const Text('Cloud Auto-Discover',
                    style: TextStyle(fontSize: 11.5)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final ctrl in house.controllers)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B1325),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lightbulb_outline,
                        size: 16, color: Color(0xFF00F5D4)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${ctrl.name} • ${ctrl.sku} (${ctrl.segmentCount} segs)${ctrl.ip.isNotEmpty ? " • ${ctrl.ip}" : ""}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => widget.api.testPhysicalLight(
                        ctrl.id,
                        color: widget.api.config.animation.primaryColor,
                      ),
                      icon: const Icon(Icons.flash_on, size: 15),
                      label: const Text(
                        'Test Physical Light',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

