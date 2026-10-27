import 'dart:math' as math;
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
  String _selectedSubcategory = 'all'; // 'all', 'official', 'ai_custom', 'diy'
  String _stageViewMode = '3d_all'; // Default 3D view ('3d_all', '3d:<houseId>', or '2d')

  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _newEmailController = TextEditingController();
  final TextEditingController _customUrlController = TextEditingController();

  static const List<Map<String, String>> _categories = [
    {'id': 'All', 'label': '✨ All Scenes'},
    {'id': 'Multi-House', 'label': '🏘️ Multi-House'},
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
    if (_selectedCategory == 'Multi-House') {
      final mhList = widget.api.presets
          .where((p) => p.isMultiHouse || p.sceneSource == 'multi_house')
          .toList();
      if (_selectedSubcategory == 'all') return mhList;
      return mhList.where((p) {
        final hTag = p.holidayTag.toLowerCase();
        final cat = p.category.toLowerCase();
        final sub = _selectedSubcategory.toLowerCase();
        return hTag == sub || cat == sub || p.name.toLowerCase().contains(sub);
      }).toList();
    }

    final byCat = _selectedCategory == 'All'
        ? widget.api.presets
        : widget.api.presets
            .where((p) =>
                p.category.toLowerCase() == _selectedCategory.toLowerCase())
            .toList();
    if (_selectedSubcategory == 'all') {
      return byCat;
    }
    if (_selectedSubcategory == 'multi_house') {
      return byCat
          .where((p) => p.isMultiHouse || p.sceneSource == 'multi_house')
          .toList();
    }
    return byCat
        .where((p) => p.sceneSource == _selectedSubcategory)
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
                    if (widget.api.cloudErrors.isNotEmpty)
                      _buildCloudErrorsBanner(),
                    if (widget.api.apkUpdateAvailable) _buildApkUpdateBanner(),
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
                      flex: 3,
                      child: Text(
                        'Govee Multi-House Sync',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15.0,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9.0,
                            fontWeight: FontWeight.w700,
                            color: isUnfoldedFoldable
                                ? const Color(0xFF00F5D4)
                                : const Color(0xFF38BDF8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7B2CBF).withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: const Color(0xFFA855F7).withValues(alpha: 0.45),
                          ),
                        ),
                        child: const Text(
                          'v$kAppVersionName (b$kAppVersionCode)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9.0,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFE9D5FF),
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

  Widget _buildCloudErrorsBanner() {
    final msg = widget.api.cloudErrors.entries
        .map((e) => '${e.key}: ${e.value}')
        .join(' • ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      color: const Color(0xFF78350F).withValues(alpha: 0.85),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, size: 15, color: Color(0xFFFCD34D)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Govee Cloud: $msg (auto-retrying every 15s)',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFFFEF3C7),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApkUpdateBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF3B0764).withValues(alpha: 0.85),
        border: Border(
          bottom: BorderSide(
            color: const Color(0xFFA855F7).withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.system_update, size: 18, color: Color(0xFF00F5D4)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'New App Update Available: v${widget.api.latestApkVersionName} (Build ${widget.api.latestApkVersionCode})',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              backgroundColor: const Color(0xFF00F5D4),
              foregroundColor: const Color(0xFF060B18),
            ),
            onPressed: () => widget.api.downloadApkVersion(
              version: widget.api.latestApkVersionName,
            ),
            icon: const Icon(Icons.download, size: 15),
            label: Text(
              'Update to v${widget.api.latestApkVersionName}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
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
              // Tab 3: Pro Features & Authorized Users + Endpoint + APK Version Center
              ListView(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                children: [
                  _buildProPlaylistAndScheduleCard(),
                  const SizedBox(height: 12),
                  _buildApkVersionAndArchiveCard(),
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
                  _buildApkVersionAndArchiveCard(),
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

  Widget _buildVisualizerModeBar(List<HouseConfig> houses, {bool compact = false}) {
    final enabledHouses = houses.where((h) => h.enabled).toList();
    final targetHouses = enabledHouses.isNotEmpty ? enabledHouses : houses;
    final modes = <(String, String, IconData)>[
      ('3d_all', '🧊 3D All (Default)', Icons.view_in_ar),
      for (int i = 0; i < targetHouses.length; i++)
        (
          '3d:${targetHouses[i].id}',
          '🧊 3D: ${targetHouses[i].isMyHouse ? "My House" : targetHouses[i].name.split("(").first.trim()}',
          Icons.threed_rotation,
        ),
      ('2d', '📐 2D Blueprint', Icons.architecture),
    ];

    final currentFocusHouseId = _stageViewMode.startsWith('3d:')
        ? _stageViewMode.substring(3)
        : null;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ...modes.map((m) {
            final isSel = _stageViewMode == m.$1;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(99),
                onTap: () => setState(() => _stageViewMode = m.$1),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 8 : 10,
                    vertical: compact ? 3 : 4,
                  ),
                  decoration: BoxDecoration(
                    color: isSel
                        ? const Color(0xFF00F5D4).withValues(alpha: 0.20)
                        : const Color(0xFF060B18),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: isSel
                          ? const Color(0xFF00F5D4)
                          : const Color(0xFF1E293B),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        m.$3,
                        size: compact ? 12 : 13.5,
                        color: isSel
                            ? const Color(0xFF00F5D4)
                            : const Color(0xFF94A3B8),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        m.$2,
                        style: TextStyle(
                          fontSize: compact ? 10 : 11,
                          fontWeight: FontWeight.w800,
                          color: isSel
                              ? const Color(0xFF00F5D4)
                              : const Color(0xFFCBD5E1),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(99),
              onTap: () => _openHouseLightDesigner(
                context,
                initialHouseId: currentFocusHouseId,
              ),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 9 : 11,
                  vertical: compact ? 3.5 : 4.5,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF7B2CBF),
                      Color(0xFFFF007F),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: const Color(0xFFFBBF24).withValues(alpha: 0.75),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.architecture_rounded,
                      size: compact ? 12 : 13.5,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '🏗️ Design House & Lights',
                      style: TextStyle(
                        fontSize: compact ? 10 : 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(99),
              onTap: _resetAllHousesToRealPhotoLayout,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 8 : 10,
                  vertical: compact ? 3.5 : 4.5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: const Color(0xFFFBBF24).withValues(alpha: 0.65),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.photo_camera_back_outlined,
                      size: compact ? 11.5 : 13,
                      color: const Color(0xFFFBBF24),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '📸 Reset to Real Photo Layout',
                      style: TextStyle(
                        fontSize: compact ? 9.8 : 10.8,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFFFDE68A),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _resetAllHousesToRealPhotoLayout() {
    final defaults = SystemConfig.defaultThreeHouses().houses;
    final defaultMap = {for (final d in defaults) d.id: d};
    final current = widget.api.config.houses;
    final updated = current.map((h) {
      final defH = defaultMap[h.id];
      final targetArch =
          defH?.architecture ?? HouseArchitecture.defaultForHouse(h.id, h.order);
      final tempHouse = h.copyWith(
        architecture: targetArch,
        controllers: h.controllers
            .map((c) => c.copyWith(sectionSpans: const []))
            .toList(),
      );
      final rebuiltCtrls = tempHouse.controllers.map((c) {
        final spans = tempHouse.effectiveControllerSpans(c);
        final wallTotals = <String, int>{};
        for (final sp in spans) {
          wallTotals[sp.wall] = (wallTotals[sp.wall] ?? 0) + sp.segments;
        }
        final zones = wallTotals.entries
            .where((e) => e.value > 0)
            .map((e) => <String, dynamic>{'wall': e.key, 'segments': e.value})
            .toList();
        return c.copyWith(sectionSpans: spans, wallZones: zones);
      }).toList();
      return tempHouse.copyWith(controllers: rebuiltCtrls);
    }).toList();
    widget.api.saveHouses(updated);
    widget.api.patchAnimation({'zone_mode': 'ccw_loop'});
    widget.api.setBanner(
      '📸 Restored exact 3-house Craftsman photo layout & ↺ Bottom → Top CCW alignment!',
    );
  }

  static const List<({String id, String label})> _kSyncAlignmentModes = [
    (id: 'ccw_loop', label: '↺ Bottom → Top CCW Loop'),
    (id: 'bottom_to_top', label: '⬆️ Bottom → Top Rise'),
    (id: 'front_street_sync', label: 'Street X-Lock (Upper+Lower Synced)'),
    (id: 'all_segments', label: 'Continuous Strip'),
    (id: 'perimeter_360', label: '360° Roof Orbit'),
    (id: 'front_back_sync', label: 'Front→Back Wave'),
    (id: 'front_only_quiet_sides', label: 'Quiet Sides'),
  ];

  Widget _buildSyncAlignmentSelectorBar({bool compact = false}) {
    final currentZoneMode = widget.api.config.animation.zoneMode;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Text(
            '🔗 3-House Sync Alignment:',
            style: TextStyle(
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF00F5D4),
            ),
          ),
          const SizedBox(width: 6),
          for (final mode in _kSyncAlignmentModes)
            Padding(
              padding: const EdgeInsets.only(right: 5),
              child: InkWell(
                borderRadius: BorderRadius.circular(99),
                onTap: () =>
                    widget.api.patchAnimation({'zone_mode': mode.id}),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 7 : 9,
                    vertical: compact ? 2.5 : 3.5,
                  ),
                  decoration: BoxDecoration(
                    color: currentZoneMode == mode.id
                        ? const Color(0xFF00F5D4).withValues(alpha: 0.22)
                        : const Color(0xFF060B18),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: currentZoneMode == mode.id
                          ? const Color(0xFF00F5D4)
                          : const Color(0xFF1E293B),
                    ),
                  ),
                  child: Text(
                    mode.label,
                    style: TextStyle(
                      fontSize: compact ? 9.5 : 10.5,
                      fontWeight: FontWeight.w700,
                      color: currentZoneMode == mode.id
                          ? const Color(0xFF00F5D4)
                          : const Color(0xFFCBD5E1),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActiveVisualizerCanvas(
    AnimationConfig anim,
    List<HouseConfig> houses, {
    required double height,
    required bool compact,
  }) {
    if (_stageViewMode == '2d') {
      return ThreeHouseScenePreview(
        clock: _masterClock,
        animation: anim,
        houses: houses,
        liveHouseColors: widget.api.liveHouseColors,
        height: height,
        compact: compact,
      );
    }
    final focusId = _stageViewMode.startsWith('3d:')
        ? _stageViewMode.substring(3)
        : null;
    return Isometric3DScenePreview(
      clock: _masterClock,
      animation: anim,
      houses: houses,
      focusHouseId: focusId,
      liveHouseColors: widget.api.liveHouseColors,
      height: height,
    );
  }

  Widget _buildCompactPinnedVisualizerCard() {
    final anim = widget.api.config.animation;
    final houses = widget.api.config.sortedHouses;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            _buildVisualizerModeBar(houses, compact: true),
            const SizedBox(height: 6),
            _buildActiveVisualizerCanvas(
              anim,
              houses,
              height: _stageViewMode == '2d' ? 82 : 112,
              compact: true,
            ),
            const SizedBox(height: 6),
            _buildSyncAlignmentSelectorBar(compact: true),
            const SizedBox(height: 6),
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
            const SizedBox(height: 8),
            _buildVisualizerModeBar(houses, compact: false),
            const SizedBox(height: 8),
            _buildActiveVisualizerCanvas(
              anim,
              houses,
              height: 142,
              compact: false,
            ),
            const SizedBox(height: 8),
            _buildSyncAlignmentSelectorBar(compact: false),
            const SizedBox(height: 10),
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
                      onSelected: (_) => setState(() {
                        _selectedCategory = id;
                        _selectedSubcategory = 'all';
                      }),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final sub in (_selectedCategory == 'Multi-House'
                      ? const [
                          ('all', 'All Multi-House'),
                          ('Halloween', '🎃 Halloween'),
                          ('Christmas', '🎄 Christmas'),
                          ('Diwali', '🪔 Diwali'),
                          ("New Year's Eve", "🎆 New Year's Eve"),
                          ('Center-Out (My House)', '💥 Center-Out'),
                          ('Celebrations', '🏈 Celebrations'),
                        ]
                      : const [
                          ('all', 'All Types'),
                          ('multi_house', '🏘️ Multi-House'),
                          ('official', '🏷️ Official Govee'),
                          ('ai_custom', '🤖 AI & Custom'),
                          ('diy', '🛠️ My Govee DIY'),
                        ]))
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(99),
                        onTap: () =>
                            setState(() => _selectedSubcategory = sub.$1),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _selectedSubcategory == sub.$1
                                ? const Color(0xFFA855F7).withValues(alpha: 0.22)
                                : const Color(0xFF060B18),
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(
                              color: _selectedSubcategory == sub.$1
                                  ? const Color(0xFFC084FC)
                                  : const Color(0xFF1E293B),
                            ),
                          ),
                          child: Text(
                            sub.$2,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: _selectedSubcategory == sub.$1
                                  ? const Color(0xFFE9D5FF)
                                  : const Color(0xFF94A3B8),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
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
            // Live Multi-House CustomPainter Preview + High-Density 36-Puck Mini-Preview Bar!
            ThreeHouseScenePreview(
              clock: _masterClock,
              animation: scene.animation.copyWith(running: true),
              houses: houses,
              height: panoramicPreview ? 93 : 71,
              compact: !panoramicPreview,
            ),
            const SizedBox(height: 3),
            SizedBox(
              height: 8,
              width: double.infinity,
              child: AnimatedBuilder(
                animation: _masterClock,
                builder: (context, _) {
                  final elapsedSec = _masterClock.value * 60.0;
                  final unwrappedPhase = elapsedSec * scene.animation.speed;
                  final activeAnim = scene.animation.copyWith(running: true);
                  const puckCount = 36;
                  return Row(
                    children: List<Widget>.generate(puckCount, (i) {
                      final x = (i + 0.5) / puckCount;
                      final c = evaluateEffectAtPoint(
                        x: x,
                        unwrappedPhase: unwrappedPhase,
                        elapsedSec: elapsedSec,
                        anim: activeAnim,
                      );
                      return Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 0.4),
                          decoration: BoxDecoration(
                            color: c,
                            borderRadius: BorderRadius.circular(99),
                            boxShadow: [
                              BoxShadow(
                                color: c.withValues(alpha: 0.55),
                                blurRadius: 3.0,
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  );
                },
              ),
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
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  final nextOverride =
                      !widget.api.config.schedule.overrideGoveeAppSchedules;
                  widget.api.patchSchedule({
                    'override_govee_app_schedules': nextOverride,
                  });
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: widget.api.config.schedule.overrideGoveeAppSchedules
                        ? const Color(0xFFF59E0B).withValues(alpha: 0.2)
                        : const Color(0xFF00F5D4).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color:
                          widget.api.config.schedule.overrideGoveeAppSchedules
                              ? const Color(0xFFFBBF24)
                              : const Color(0xFF00F5D4),
                    ),
                  ),
                  child: Text(
                    widget.api.config.schedule.overrideGoveeAppSchedules
                        ? 'Govee Sched: OFF'
                        : 'Govee Sched: ON',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color:
                          widget.api.config.schedule.overrideGoveeAppSchedules
                              ? const Color(0xFFFCD34D)
                              : const Color(0xFF00F5D4),
                    ),
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
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.vpn_key_rounded,
                        color: Color(0xFF00F5D4), size: 19),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Houses, Govee API Keys & Physical Light Test ($enabledCount/${houses.length} Enabled)',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7B2CBF),
                        foregroundColor: Colors.white,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => _openHouseLightDesigner(context),
                      icon: const Icon(Icons.architecture_rounded, size: 16),
                      label: const Text(
                        '🏗️ Design House & Lights',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w800),
                      ),
                    ),
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
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Sculpt each house in 3D or 2D (triangle gables, flat garages, 2nd-story dormers), map where each controller\'s segments sit on the roofline, configure Govee Cloud OpenAPI keys, or send a 1-tap physical test pulse.',
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
                  onOpenDesigner: () => _openHouseLightDesigner(
                    context,
                    initialHouseId: house.id,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openHouseLightDesigner(BuildContext context, {String? initialHouseId}) {
    final houses = widget.api.config.sortedHouses;
    if (houses.isEmpty) return;
    final defaultHouse = houses.firstWhere(
      (h) => h.id == initialHouseId,
      orElse: () => houses.firstWhere(
        (h) => h.isMyHouse,
        orElse: () => houses.first,
      ),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF060B18),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return FractionallySizedBox(
          heightFactor: 0.94,
          child: _HouseLightDesignerSheet(
            api: widget.api,
            clock: _masterClock,
            initialHouseId: defaultHouse.id,
            onApplyStageMode: (mode) {
              setState(() {
                _stageViewMode = mode;
              });
            },
          ),
        );
      },
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
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                schedule.overrideGoveeAppSchedules
                    ? 'Govee App Schedules: Disabled / Overridden'
                    : 'Govee App Schedules: Enabled (Allowed)',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                schedule.overrideGoveeAppSchedules
                    ? 'Sync Studio watchdog overrides Govee Home app timers every 45s'
                    : 'Allows Govee Home app timers to trigger between Sync Studio start/stop times',
                style: const TextStyle(fontSize: 11),
              ),
              value: !schedule.overrideGoveeAppSchedules,
              activeThumbColor: const Color(0xFF00F5D4),
              onChanged: (allowGovee) => widget.api.patchSchedule({
                'override_govee_app_schedules': !allowGovee,
              }),
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
  // ANDROID APP VERSION & RELEASE ARCHIVE CARD
  // ===========================================================================

  Widget _buildApkVersionAndArchiveCard() {
    final releases = widget.api.apkReleases;
    final hasUpdate = widget.api.apkUpdateAvailable;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.system_update_alt,
                    color: Color(0xFF00F5D4), size: 19),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Android App Version & Release Archive',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  ),
                  onPressed: () =>
                      widget.api.fetchApkInfoSilently(showFeedback: true),
                  icon: const Icon(Icons.refresh, size: 14),
                  label: const Text(
                    'Check Updates',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF060B18),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasUpdate
                      ? const Color(0xFFA855F7).withValues(alpha: 0.6)
                      : const Color(0xFF00F5D4).withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Installed: v$kAppVersionName • Build $kAppVersionCode',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF00F5D4),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasUpdate
                              ? 'Newer build on server: v${widget.api.latestApkVersionName} (Build ${widget.api.latestApkVersionCode})'
                              : 'Latest server build: v${widget.api.latestApkVersionName} (Build ${widget.api.latestApkVersionCode})',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => widget.api.downloadApkVersion(
                      version: widget.api.latestApkVersionName,
                    ),
                    icon: const Icon(Icons.download, size: 15),
                    label: Text(
                      hasUpdate
                          ? 'Update v${widget.api.latestApkVersionName}'
                          : 'Download v${widget.api.latestApkVersionName}',
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            if (releases.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                'Archived Server APK Versions (Install or Roll Back):',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFCBD5E1),
                ),
              ),
              const SizedBox(height: 6),
              for (final rel in releases)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B1325),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF1E293B)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'v${rel["version_name"] ?? "3.1.0"} (Build ${rel["version_code"] ?? 4})${rel["version_code"] == kAppVersionCode ? " • Installed" : ""}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                              ),
                              onPressed: () => widget.api.downloadApkVersion(
                                version: (rel['version_name'] ?? '').toString(),
                              ),
                              icon: const Icon(Icons.download, size: 13),
                              label: Text(
                                'v${rel["version_name"] ?? ""}',
                                style: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                        if (rel['changelog'] is List &&
                            (rel['changelog'] as List).isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              (rel['changelog'] as List)
                                  .map((e) => '• $e')
                                  .join('\n'),
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
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
  final VoidCallback? onOpenDesigner;

  const _HouseEditorCard({
    required this.house,
    required this.api,
    this.canDelete = false,
    this.onOpenDesigner,
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
    final arch = house.architecture;
    final presetMeta = kArchitecturePresetMeta.firstWhere(
      (m) => m.id == arch.presetStyle,
      orElse: () => kArchitecturePresetMeta.first,
    );

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
                color: const Color(0xFF7B2CBF).withValues(alpha: 0.55),
              ),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Text(
                  '${presetMeta.title} • ${arch.sections.length} Roof/Wall Sections (${arch.defaultViewMode.toUpperCase()} Default)',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFE2E8F0),
                  ),
                ),
                if (widget.onOpenDesigner != null)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7B2CBF),
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                    ),
                    onPressed: widget.onOpenDesigner,
                    icon: const Icon(Icons.architecture_rounded, size: 15),
                    label: const Text(
                      '🏗️ Design 3D/2D House & Lights',
                      style:
                          TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                    ),
                  ),
              ],
            ),
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
              child: _buildControllerCardWithZoneSplit(house, ctrl),
            ),
        ],
      ),
    );
  }

  Widget _buildControllerCardWithZoneSplit(
      HouseConfig house, ControllerConfig ctrl) {
    final segWalls = ctrl.getSegmentWalls(
      defaultSecondWall:
          (!house.isMyHouse && house.controllers.length > 1) ? 'right' : 'front',
    );
    final frontSegs = segWalls.where((w) => w == 'front').length;
    final secondWall =
        segWalls.firstWhere((w) => w != 'front', orElse: () => 'right');
    final sideSegs = math.max(0, ctrl.segmentCount - frontSegs);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1325),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lightbulb_outline,
                  size: 16, color: Color(0xFF00F5D4)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${ctrl.name} • ${ctrl.sku} (${ctrl.segmentCount} segs)${ctrl.ip.isNotEmpty ? " • ${ctrl.ip}" : ""}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
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
                  'Test Light',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '3D Split — Front: $frontSegs segs',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF00F5D4),
                ),
              ),
              Text(
                '${secondWall.toUpperCase()}: $sideSegs segs',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFC084FC),
                ),
              ),
            ],
          ),
          Slider(
            value: frontSegs.toDouble().clamp(0.0, ctrl.segmentCount.toDouble()),
            min: 0,
            max: ctrl.segmentCount.toDouble(),
            divisions: math.max(1, ctrl.segmentCount),
            activeColor: const Color(0xFF00F5D4),
            onChanged: (v) {
              final newFront = v.round();
              final rem = math.max(0, ctrl.segmentCount - newFront);
              final zones = <Map<String, dynamic>>[];
              if (newFront > 0) {
                zones.add({'wall': 'front', 'segments': newFront});
              }
              if (rem > 0) {
                zones.add({'wall': secondWall, 'segments': rem});
              }
              widget.api.updateControllerWallZones(ctrl.id, zones);
            },
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                '2nd Wall:',
                style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
              ),
              for (final wOpt in ['left', 'right', 'back'])
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    final rem = math.max(1, ctrl.segmentCount - frontSegs);
                    final fCnt = math.max(0, ctrl.segmentCount - rem);
                    final zones = <Map<String, dynamic>>[];
                    if (fCnt > 0) {
                      zones.add({'wall': 'front', 'segments': fCnt});
                    }
                    zones.add({'wall': wOpt, 'segments': rem});
                    widget.api.updateControllerWallZones(ctrl.id, zones);
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: (secondWall == wOpt && sideSegs > 0)
                          ? const Color(0xFFA855F7).withValues(alpha: 0.25)
                          : const Color(0xFF060B18),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: (secondWall == wOpt && sideSegs > 0)
                            ? const Color(0xFFC084FC)
                            : const Color(0xFF1E293B),
                      ),
                    ),
                    child: Text(
                      wOpt.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                ),
                onPressed: () {
                  final cornerIdx =
                      (frontSegs - 1).clamp(0, ctrl.segmentCount - 1);
                  widget.api.locateControllerSegment(ctrl.id, cornerIdx);
                },
                icon: const Icon(Icons.my_location,
                    size: 13, color: Color(0xFFFBBF24)),
                label: Text(
                  'Spotlight Corner #${math.max(1, frontSegs)}',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFFCD34D),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// INTERACTIVE 3D & 2D HOUSE & LIGHT DESIGNER STUDIO
// =============================================================================

class _HouseLightDesignerSheet extends StatefulWidget {
  final GoveeApiService api;
  final Animation<double> clock;
  final String initialHouseId;
  final ValueChanged<String>? onApplyStageMode;

  const _HouseLightDesignerSheet({
    required this.api,
    required this.clock,
    required this.initialHouseId,
    this.onApplyStageMode,
  });

  @override
  State<_HouseLightDesignerSheet> createState() =>
      _HouseLightDesignerSheetState();
}

class _HouseLightDesignerSheetState extends State<_HouseLightDesignerSheet> {
  late String _selectedHouseId;
  late HouseArchitecture _workingArch;
  late List<ControllerConfig> _workingControllers;
  String _designerMode = '3d'; // '3d' (Default) or '2d'
  int _activeTab = 0; // 0: Roof & Wall Sections, 1: Controller Light Placement
  String? _selectedSectionId;
  String? _selectedControllerId;
  int _spotlightSegIdx = 0;
  final TextEditingController _sectionLabelCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedHouseId = widget.initialHouseId;
    _loadHouseIntoEditor(_selectedHouseId);
  }

  @override
  void dispose() {
    _sectionLabelCtrl.dispose();
    super.dispose();
  }

  HouseConfig get _currentHouse {
    final houses = widget.api.config.sortedHouses;
    return houses.firstWhere(
      (h) => h.id == _selectedHouseId,
      orElse: () => houses.first,
    );
  }

  void _loadHouseIntoEditor(String houseId) {
    final houses = widget.api.config.sortedHouses;
    final house = houses.firstWhere(
      (h) => h.id == houseId,
      orElse: () => houses.first,
    );
    _selectedHouseId = house.id;
    _workingArch = house.architecture;
    _workingControllers = house.controllers.map((c) {
      final resolvedSpans = house.effectiveControllerSpans(c);
      return c.copyWith(
        sectionSpans: resolvedSpans,
      );
    }).toList();
    _selectedSectionId =
        _workingArch.sections.isNotEmpty ? _workingArch.sections.first.id : null;
    if (_selectedSectionId != null) {
      final sec = _workingArch.sections
          .firstWhere((s) => s.id == _selectedSectionId);
      _sectionLabelCtrl.text = sec.label;
    }
    _selectedControllerId = _workingControllers.isNotEmpty
        ? _workingControllers.first.id
        : null;
    _spotlightSegIdx = 0;
  }

  ArchSection? get _selectedSection {
    if (_workingArch.sections.isEmpty) return null;
    return _workingArch.sections.firstWhere(
      (s) => s.id == _selectedSectionId,
      orElse: () => _workingArch.sections.first,
    );
  }

  ControllerConfig? get _selectedController {
    if (_workingControllers.isEmpty) return null;
    return _workingControllers.firstWhere(
      (c) => c.id == _selectedControllerId,
      orElse: () => _workingControllers.first,
    );
  }

  void _updateSelectedSection(ArchSection updated) {
    setState(() {
      _workingArch = _workingArch.copyWith(
        sections: _workingArch.sections
            .map((s) => s.id == updated.id ? updated : s)
            .toList(),
      );
      if (_sectionLabelCtrl.text != updated.label) {
        _sectionLabelCtrl.text = updated.label;
      }
      // Keep controller spans wall synced with section wall
      _workingControllers = _workingControllers.map((c) {
        return c.copyWith(
          sectionSpans: c.sectionSpans
              .map((sp) => sp.sectionId == updated.id
                  ? sp.copyWith(wall: updated.wall)
                  : sp)
              .toList(),
        );
      }).toList();
    });
  }

  void _applyArchitectureTemplate(String presetId) {
    final tpl = kArchitecturePresets[presetId];
    if (tpl == null) return;
    setState(() {
      _workingArch = tpl.copyWith(
        defaultViewMode: _workingArch.defaultViewMode,
      );
      _selectedSectionId =
          _workingArch.sections.isNotEmpty ? _workingArch.sections.first.id : null;
      if (_selectedSectionId != null) {
        _sectionLabelCtrl.text = _workingArch.sections.first.label;
      }
      // Re-balance controller spans onto the new template's sections
      final tempHouse = _currentHouse.copyWith(
        architecture: _workingArch,
        controllers: _workingControllers
            .map((c) => c.copyWith(sectionSpans: const []))
            .toList(),
      );
      _workingControllers = tempHouse.controllers.map((c) {
        return c.copyWith(
          sectionSpans: tempHouse.effectiveControllerSpans(c),
        );
      }).toList();
    });
  }

  void _addSection(String shape, String label, {int story = 1, String wall = 'front'}) {
    final newId = 'sec-${DateTime.now().millisecondsSinceEpoch % 100000}';
    final newSec = ArchSection(
      id: newId,
      label: label,
      shape: shape,
      wall: wall,
      story: story,
      xStart: story == 2 ? 0.20 : 0.12,
      xEnd: story == 2 ? 0.80 : 0.88,
      eaveHeight: story == 2 ? 0.66 : 0.50,
      peakHeight: shape == 'flat_eave'
          ? (story == 2 ? 0.66 : 0.50)
          : (story == 2 ? 0.94 : 0.86),
      peakOffset: 0.50,
      depthOffset: story == 2 ? -0.05 : 0.08,
      hasDoor: false,
      hasGarage: false,
      windowStyle: 'standard',
    );
    setState(() {
      _workingArch = _workingArch.copyWith(
        sections: [..._workingArch.sections, newSec],
      );
      _selectedSectionId = newId;
      _sectionLabelCtrl.text = label;
    });
  }

  void _deleteSelectedSection() {
    if (_workingArch.sections.length <= 1) return;
    final rem = _workingArch.sections
        .where((s) => s.id != _selectedSectionId)
        .toList();
    setState(() {
      _workingArch = _workingArch.copyWith(sections: rem);
      _selectedSectionId = rem.first.id;
      _sectionLabelCtrl.text = rem.first.label;
    });
  }

  int _getControllerSegmentsForSection(ControllerConfig ctrl, String sectionId) {
    int sum = 0;
    for (final sp in ctrl.sectionSpans) {
      if (sp.sectionId == sectionId) sum += sp.segments;
    }
    return sum;
  }

  String _getControllerDirectionForSection(
      ControllerConfig ctrl, String sectionId) {
    for (final sp in ctrl.sectionSpans) {
      if (sp.sectionId == sectionId) return sp.direction;
    }
    final sec = _workingArch.sections.where((s) => s.id == sectionId).firstOrNull;
    if (sec != null && (sec.story >= 2 || sec.wall == 'back' || sec.wall == 'left')) {
      return 'rtl';
    }
    return 'ltr';
  }

  void _setControllerSegmentsForSection(
    ControllerConfig ctrl,
    ArchSection sec,
    int newCount, {
    String? direction,
  }) {
    final clamped = newCount.clamp(0, ctrl.segmentCount);
    final existingDir =
        direction ?? _getControllerDirectionForSection(ctrl, sec.id);
    final nextSpans = <SectionSpan>[];
    bool found = false;
    for (final sp in ctrl.sectionSpans) {
      if (sp.sectionId == sec.id) {
        found = true;
        if (clamped > 0) {
          nextSpans.add(
            sp.copyWith(
              segments: clamped,
              wall: sec.wall,
              direction: existingDir,
            ),
          );
        }
      } else if (sp.segments > 0) {
        nextSpans.add(sp);
      }
    }
    if (!found && clamped > 0) {
      nextSpans.add(
        SectionSpan(
          sectionId: sec.id,
          wall: sec.wall,
          segments: clamped,
          direction: existingDir,
        ),
      );
    }

    // Build synced wall_zones from sectionSpans
    final wallTotals = <String, int>{};
    for (final sp in nextSpans) {
      wallTotals[sp.wall] = (wallTotals[sp.wall] ?? 0) + sp.segments;
    }
    final nextZones = wallTotals.entries
        .where((e) => e.value > 0)
        .map((e) => <String, dynamic>{'wall': e.key, 'segments': e.value})
        .toList();

    setState(() {
      _workingControllers = _workingControllers
          .map((c) => c.id == ctrl.id
              ? c.copyWith(sectionSpans: nextSpans, wallZones: nextZones)
              : c)
          .toList();
    });
  }

  void _autoBalanceControllerAcrossFrontSections(ControllerConfig ctrl) {
    final frontSecs = _workingArch.frontSections.isNotEmpty
        ? _workingArch.frontSections
        : _workingArch.sections;
    _distributeControllerAcrossSections(ctrl, frontSecs);
  }

  void _distributeControllerAcrossSections(
    ControllerConfig ctrl,
    List<ArchSection> targetSecs,
  ) {
    if (targetSecs.isEmpty) return;
    final spans = <SectionSpan>[];
    int rem = ctrl.segmentCount;
    for (int i = 0; i < targetSecs.length; i++) {
      final sec = targetSecs[i];
      final cnt = i == targetSecs.length - 1
          ? rem
          : (ctrl.segmentCount / targetSecs.length).round().clamp(1, rem);
      rem -= cnt;
      if (cnt > 0) {
        final ccwDir =
            (sec.story >= 2 || sec.wall == 'back' || sec.wall == 'left')
                ? 'rtl'
                : 'ltr';
        spans.add(
          SectionSpan(
            sectionId: sec.id,
            wall: sec.wall,
            segments: cnt,
            direction: ccwDir,
          ),
        );
      }
    }
    final wallTotals = <String, int>{};
    for (final sp in spans) {
      wallTotals[sp.wall] = (wallTotals[sp.wall] ?? 0) + sp.segments;
    }
    final nextZones = wallTotals.entries
        .where((e) => e.value > 0)
        .map((e) => <String, dynamic>{'wall': e.key, 'segments': e.value})
        .toList();
    setState(() {
      _workingControllers = _workingControllers
          .map((c) => c.id == ctrl.id
              ? c.copyWith(sectionSpans: spans, wallZones: nextZones)
              : c)
          .toList();
    });
  }

  void _applyWiringRoutePreset(ControllerConfig ctrl, String presetKey) {
    final allSecs = _workingArch.sections;
    if (allSecs.isEmpty) return;
    if (presetKey == 'bottom_to_top_ccw') {
      final tempHouse = _currentHouse.copyWith(
        architecture: _workingArch,
        controllers: _workingControllers
            .map((c) => c.copyWith(sectionSpans: const []))
            .toList(),
      );
      final ccwSpans = tempHouse.effectiveControllerSpans(
        ctrl.copyWith(sectionSpans: const []),
      );
      if (ccwSpans.isNotEmpty) {
        final wallTotals = <String, int>{};
        for (final sp in ccwSpans) {
          wallTotals[sp.wall] = (wallTotals[sp.wall] ?? 0) + sp.segments;
        }
        final nextZones = wallTotals.entries
            .where((e) => e.value > 0)
            .map((e) => <String, dynamic>{'wall': e.key, 'segments': e.value})
            .toList();
        setState(() {
          _workingControllers = _workingControllers
              .map((c) => c.id == ctrl.id
                  ? c.copyWith(sectionSpans: ccwSpans, wallZones: nextZones)
                  : c)
              .toList();
        });
        return;
      }
    }
    List<ArchSection> targets = const [];
    if (presetKey == 'upper_lower_front') {
      final lowerF =
          allSecs.where((s) => s.wall == 'front' && s.story == 1).toList();
      final upperF =
          allSecs.where((s) => s.wall == 'front' && s.story == 2).toList();
      targets = [...lowerF, ...upperF];
    } else if (presetKey == 'upper_front_right') {
      final upperF =
          allSecs.where((s) => s.wall == 'front' && s.story == 2).toList();
      final rightS = allSecs.where((s) => s.wall == 'right').toList();
      targets = [...upperF, ...rightS];
    } else if (presetKey == 'lower_front_left_back') {
      final lowerF =
          allSecs.where((s) => s.wall == 'front' && s.story == 1).toList();
      final leftS = allSecs.where((s) => s.wall == 'left').toList();
      final backS = allSecs.where((s) => s.wall == 'back').toList();
      targets = [...lowerF, ...leftS, ...backS];
    } else if (presetKey == 'full_360_perimeter') {
      final frontS = allSecs.where((s) => s.wall == 'front').toList();
      final rightS = allSecs.where((s) => s.wall == 'right').toList();
      final backS = allSecs.where((s) => s.wall == 'back').toList();
      final leftS = allSecs.where((s) => s.wall == 'left').toList();
      targets = [...frontS, ...rightS, ...backS, ...leftS];
    }
    if (targets.isEmpty) {
      targets = _workingArch.frontSections.isNotEmpty
          ? _workingArch.frontSections
          : allSecs;
    }
    _distributeControllerAcrossSections(ctrl, targets);
  }

  void _resetCurrentHouseToRealPhotoLayout() {
    final photoArch = HouseArchitecture.defaultForHouse(
      _selectedHouseId,
      _currentHouse.order,
    );
    setState(() {
      _workingArch = photoArch;
      _selectedSectionId =
          _workingArch.sections.isNotEmpty ? _workingArch.sections.first.id : null;
      if (_selectedSectionId != null) {
        _sectionLabelCtrl.text = _workingArch.sections.first.label;
      }
      final tempHouse = _currentHouse.copyWith(
        architecture: _workingArch,
        controllers: _workingControllers
            .map((c) => c.copyWith(sectionSpans: const []))
            .toList(),
      );
      _workingControllers = tempHouse.controllers.map((c) {
        final spans = tempHouse.effectiveControllerSpans(c);
        final wallTotals = <String, int>{};
        for (final sp in spans) {
          wallTotals[sp.wall] = (wallTotals[sp.wall] ?? 0) + sp.segments;
        }
        final zones = wallTotals.entries
            .where((e) => e.value > 0)
            .map((e) => <String, dynamic>{'wall': e.key, 'segments': e.value})
            .toList();
        return c.copyWith(sectionSpans: spans, wallZones: zones);
      }).toList();
    });
  }

  Future<void> _saveDesignToHouse() async {
    await widget.api.updateHouseArchitecture(
      _selectedHouseId,
      _workingArch,
      updatedControllers: _workingControllers,
    );
    if (widget.onApplyStageMode != null) {
      widget.onApplyStageMode!(
        _workingArch.defaultViewMode == '2d' ? '2d' : '3d_all',
      );
    }
    if (mounted) {
      Navigator.pop(context);
    }
  }

  void _handle2DBlueprintDrag(Offset localPos, Size canvasSize) {
    final sec = _selectedSection;
    if (sec == null) return;
    final padX = math.max(20.0, canvasSize.width * 0.08);
    final houseW = math.max(60.0, canvasSize.width - padX * 2);
    final groundY = canvasSize.height * 0.82;
    final topY = canvasSize.height * 0.10;
    final usableH = math.max(40.0, groundY - topY);

    final normX = ((localPos.dx - padX) / houseW).clamp(0.02, 0.98);
    final normH = ((groundY - localPos.dy) / usableH).clamp(0.22, 0.98);

    final leftDist = (normX - sec.xStart).abs();
    final rightDist = (normX - sec.xEnd).abs();
    final apexX = sec.xStart + (sec.xEnd - sec.xStart) * sec.peakOffset;
    final apexDist = (normX - apexX).abs();

    if (sec.isPitchedGable &&
        apexDist <= leftDist &&
        apexDist <= rightDist) {
      final spanW = math.max(0.10, sec.xEnd - sec.xStart);
      final newPeakOffset = ((normX - sec.xStart) / spanW).clamp(0.18, 0.82);
      final newPeakH = math.max(sec.eaveHeight + 0.04, normH).clamp(0.26, 0.98);
      _updateSelectedSection(
        sec.copyWith(
          peakHeight: newPeakH,
          peakOffset: newPeakOffset,
        ),
      );
    } else if (leftDist < rightDist) {
      final newStart = math.min(sec.xEnd - 0.12, normX).clamp(0.0, 0.88);
      _updateSelectedSection(
        sec.copyWith(
          xStart: newStart,
          eaveHeight: normH.clamp(0.22, 0.92),
          peakHeight: sec.shape == 'flat_eave'
              ? normH.clamp(0.22, 0.92)
              : math.max(sec.peakHeight, normH + 0.06),
        ),
      );
    } else {
      final newEnd = math.max(sec.xStart + 0.12, normX).clamp(0.12, 1.0);
      _updateSelectedSection(
        sec.copyWith(
          xEnd: newEnd,
          eaveHeight: normH.clamp(0.22, 0.92),
          peakHeight: sec.shape == 'flat_eave'
              ? normH.clamp(0.22, 0.92)
              : math.max(sec.peakHeight, normH + 0.06),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final houses = widget.api.config.sortedHouses;
    final previewHouse = _currentHouse.copyWith(
      architecture: _workingArch,
      controllers: _workingControllers,
    );

    return Column(
      children: [
        // Studio Header Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
          child: Row(
            children: [
              const GoveeSyncLogoBadge(size: 32),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🏗️ 3D & 2D House & Light Designer',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Sculpt triangle peaks, square garages & dormers + map controller segments',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFBBF24),
                  side: BorderSide(
                    color: const Color(0xFFFBBF24).withValues(alpha: 0.65),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _resetCurrentHouseToRealPhotoLayout,
                icon: const Icon(Icons.photo_camera_back_outlined, size: 15),
                label: const Text(
                  '📸 Reset to Real Photo Layout',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 6),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00F5D4),
                  foregroundColor: const Color(0xFF040711),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _saveDesignToHouse,
                icon: const Icon(Icons.save_rounded, size: 16),
                label: const Text(
                  '💾 Save House & Light Map',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),

        // 3-House Sync Alignment Selector Bar inside Designer Sheet
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Text(
                  '🔗 3-House Sync Alignment:',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF00F5D4),
                  ),
                ),
                const SizedBox(width: 6),
                for (final mode in const [
                  ('ccw_loop', '↺ Bottom → Top CCW Loop'),
                  ('bottom_to_top', '⬆️ Bottom → Top Rise'),
                  ('front_street_sync', 'Street X-Lock (Upper+Lower Synced)'),
                  ('all_segments', 'Continuous Strip'),
                  ('perimeter_360', '360° Roof Orbit'),
                  ('front_back_sync', 'Front→Back Wave'),
                  ('front_only_quiet_sides', 'Quiet Sides'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      selected: widget.api.config.animation.zoneMode == mode.$1,
                      selectedColor:
                          const Color(0xFF00F5D4).withValues(alpha: 0.22),
                      label: Text(
                        mode.$2,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onSelected: (_) {
                        setState(() {
                          widget.api.patchAnimation({'zone_mode': mode.$1});
                        });
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),

        // House Selector + 3D/2D Mode Switcher Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final h in houses)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      selected: h.id == _selectedHouseId,
                      selectedColor:
                          const Color(0xFF00F5D4).withValues(alpha: 0.25),
                      label: Text(
                        '${h.isMyHouse ? "⭐ My House" : h.name.split("(").first.trim()} (${h.totalSegments} segs)',
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                      onSelected: (_) {
                        setState(() {
                          _loadHouseIntoEditor(h.id);
                        });
                      },
                    ),
                  ),
                const SizedBox(width: 8),
                SegmentedButton<String>(
                  style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const [
                    ButtonSegment(
                      value: '3d',
                      label: Text('🧊 3D Orbit (Default)',
                          style: TextStyle(fontSize: 10.5)),
                    ),
                    ButtonSegment(
                      value: '2d',
                      label: Text('📐 2D Blueprint Touch',
                          style: TextStyle(fontSize: 10.5)),
                    ),
                  ],
                  selected: {_designerMode},
                  onSelectionChanged: (sel) {
                    setState(() {
                      _designerMode = sel.first;
                      _workingArch = _workingArch.copyWith(
                        defaultViewMode: sel.first,
                      );
                    });
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),

        // Interactive Live 3D / 2D Preview Canvas
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF040711),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF00F5D4).withValues(alpha: 0.45),
              ),
            ),
            child: Column(
              children: [
                if (_designerMode == '3d')
                  Isometric3DScenePreview(
                    clock: widget.clock,
                    animation: widget.api.config.animation,
                    houses: [previewHouse],
                    focusHouseId: previewHouse.id,
                    height: 196,
                    cameraYawOverride: _workingArch.cameraYaw,
                    cameraPitchOverride: _workingArch.cameraPitch,
                    cameraZoomOverride: _workingArch.cameraZoom,
                    selectedSectionId: _selectedSectionId,
                    highlightedControllerId:
                        _activeTab == 1 ? _selectedControllerId : null,
                    highlightedSegmentIndex:
                        _activeTab == 1 ? _spotlightSegIdx : null,
                    designMode: true,
                    onSectionTapped: (secId) {
                      setState(() {
                        _selectedSectionId = secId;
                        final sec = _selectedSection;
                        if (sec != null) {
                          _sectionLabelCtrl.text = sec.label;
                        }
                      });
                    },
                    onOrbitChanged: (newYaw, newPitch) {
                      setState(() {
                        _workingArch = _workingArch.copyWith(
                          cameraYaw: newYaw,
                          cameraPitch: newPitch,
                        );
                      });
                    },
                  )
                else
                  LayoutBuilder(
                    builder: (ctx, box) {
                      final canvasSize = Size(box.maxWidth, 196);
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanUpdate: (details) =>
                            _handle2DBlueprintDrag(details.localPosition, canvasSize),
                        onTapDown: (details) =>
                            _handle2DBlueprintDrag(details.localPosition, canvasSize),
                        child: ThreeHouseScenePreview(
                          clock: widget.clock,
                          animation: widget.api.config.animation,
                          houses: [previewHouse],
                          focusHouseId: previewHouse.id,
                          selectedSectionId: _selectedSectionId,
                          highlightedControllerId:
                              _activeTab == 1 ? _selectedControllerId : null,
                          highlightedSegmentIndex:
                              _activeTab == 1 ? _spotlightSegIdx : null,
                          designMode: true,
                          compact: false,
                          height: 196,
                        ),
                      );
                    },
                  ),
                // Camera Orbit Quick Angles (in 3D) or Touch Hint (in 2D)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: _designerMode == '3d'
                      ? SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              const Text(
                                '3D Camera:',
                                style: TextStyle(
                                    fontSize: 10.5, color: Color(0xFF94A3B8)),
                              ),
                              const SizedBox(width: 6),
                              for (final cam in [
                                ('Street 3D', -26.0, 20.0, 1.0),
                                ('Front Straight', 0.0, 14.0, 1.05),
                                ('Left Side', -58.0, 22.0, 1.0),
                                ('Right Side', 58.0, 22.0, 1.0),
                                ('Top Roof', -22.0, 48.0, 0.95),
                              ])
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: () => setState(() {
                                      _workingArch = _workingArch.copyWith(
                                        cameraYaw: cam.$2,
                                        cameraPitch: cam.$3,
                                        cameraZoom: cam.$4,
                                      );
                                    }),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0B1325),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: const Color(0xFF1E293B)),
                                      ),
                                      child: Text(
                                        cam.$1,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF00F5D4),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        )
                      : const Text(
                          '👆 Drag gold handles on the 2D blueprint above to sculpt triangle peak height, apex offset, or eave span!',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Color(0xFFFBBF24),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Studio Sub-Tabs: [🏠 Roof & Wall Sections] vs [💡 Controller Light Placement]
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<int>(
                  segments: [
                    ButtonSegment(
                      value: 0,
                      icon: const Icon(Icons.roofing_rounded, size: 16),
                      label: Text(
                        '🏠 Roof & Wall Sections (${_workingArch.sections.length})',
                        style: const TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w800),
                      ),
                    ),
                    ButtonSegment(
                      value: 1,
                      icon: const Icon(Icons.lightbulb_rounded, size: 16),
                      label: Text(
                        '💡 Controller Light Placement (${_workingControllers.length})',
                        style: const TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                  selected: {_activeTab},
                  onSelectionChanged: (sel) =>
                      setState(() => _activeTab = sel.first),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Scrollable Studio Inspector Body
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
            children: [
              if (_activeTab == 0)
                _buildRoofSectionsEditorTab()
              else
                _buildControllerLightPlacementTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRoofSectionsEditorTab() {
    final sec = _selectedSection;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1-Tap Architectural Templates
        const Text(
          '1-Tap House Architecture Templates (Customize Any Section Below):',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Color(0xFF00F5D4),
          ),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: kArchitecturePresetMeta.map((tpl) {
              final isSelected = _workingArch.presetStyle == tpl.id;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _applyArchitectureTemplate(tpl.id),
                  child: Container(
                    width: 185,
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF00F5D4).withValues(alpha: 0.16)
                          : const Color(0xFF0B1325),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF00F5D4)
                            : const Color(0xFF1E293B),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tpl.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          tpl.subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),

        // Section Pills + Quick Add Section Buttons
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (int i = 0; i < _workingArch.sections.length; i++)
              ChoiceChip(
                selected: _workingArch.sections[i].id == _selectedSectionId,
                selectedColor: const Color(0xFFFBBF24).withValues(alpha: 0.25),
                label: Text(
                  '#${i + 1} ${_workingArch.sections[i].label} (${_workingArch.sections[i].wall.toUpperCase()})',
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700),
                ),
                onSelected: (_) {
                  setState(() {
                    _selectedSectionId = _workingArch.sections[i].id;
                    _sectionLabelCtrl.text = _workingArch.sections[i].label;
                  });
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact),
              onPressed: () =>
                  _addSection('triangle_gable', 'Triangle Gable Peak'),
              icon: const Icon(Icons.change_history, size: 14),
              label: const Text('+ Triangle Peak',
                  style: TextStyle(fontSize: 11)),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact),
              onPressed: () => _addSection('flat_eave', 'Square Flat Eave'),
              icon: const Icon(Icons.crop_16_9, size: 14),
              label: const Text('+ Square Flat Eave',
                  style: TextStyle(fontSize: 11)),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact),
              onPressed: () => _addSection(
                'dormer_peak',
                '2nd-Story Dormer Peak',
                story: 2,
              ),
              icon: const Icon(Icons.home_work_outlined, size: 14),
              label: const Text('+ 2nd-Story Dormer',
                  style: TextStyle(fontSize: 11)),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact),
              onPressed: () => _addSection(
                'flat_eave',
                'Side/Back Wing Eave',
                wall: 'right',
              ),
              icon: const Icon(Icons.subdirectory_arrow_right, size: 14),
              label: const Text('+ Side/Back Wing',
                  style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (sec != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0B1325),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFFFBBF24).withValues(alpha: 0.45),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _sectionLabelCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Selected Section Name',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) =>
                            _updateSelectedSection(sec.copyWith(label: v)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_workingArch.sections.length > 1)
                      IconButton(
                        tooltip: 'Delete Section',
                        onPressed: _deleteSelectedSection,
                        icon: const Icon(Icons.delete_outline,
                            color: Color(0xFFF87171)),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Section Roof Shape:',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final sh in [
                      ('triangle_gable', '🔺 Triangle Gable'),
                      ('steep_gable', '⛰️ Steep A-Frame'),
                      ('flat_eave', '⬛ Square Flat Eave'),
                      ('dormer_peak', '🏠 2nd-Story Dormer'),
                      ('hip_roof', '⛺ Hip Roof'),
                      ('shed_slope', '📐 Angled Slope'),
                    ])
                      ChoiceChip(
                        selected: sec.shape == sh.$1,
                        label: Text(sh.$2,
                            style: const TextStyle(fontSize: 11)),
                        onSelected: (_) {
                          final nextPeak = sh.$1 == 'flat_eave'
                              ? sec.eaveHeight
                              : math.max(sec.peakHeight, sec.eaveHeight + 0.24);
                          _updateSelectedSection(
                            sec.copyWith(
                              shape: sh.$1,
                              peakHeight: nextPeak.clamp(0.25, 1.0),
                            ),
                          );
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: sec.wall,
                        decoration: const InputDecoration(
                          labelText: 'Wall / Orientation',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: 'front', child: Text('Front (Street)')),
                          DropdownMenuItem(
                              value: 'left', child: Text('Left Side Wall')),
                          DropdownMenuItem(
                              value: 'right', child: Text('Right Side Wall')),
                          DropdownMenuItem(
                              value: 'back', child: Text('Back Yard Wall')),
                        ],
                        onChanged: (w) {
                          if (w != null) {
                            _updateSelectedSection(sec.copyWith(wall: w));
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: sec.story,
                        decoration: const InputDecoration(
                          labelText: 'Story Level',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: 1, child: Text('1st Floor / Main')),
                          DropdownMenuItem(
                              value: 2, child: Text('2nd Story / Upper')),
                        ],
                        onChanged: (st) {
                          if (st != null) {
                            _updateSelectedSection(sec.copyWith(story: st));
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Horizontal Width Span: ${(sec.xStart * 100).round()}% → ${(sec.xEnd * 100).round()}%',
                  style: const TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
                RangeSlider(
                  values: RangeValues(
                    sec.xStart.clamp(0.0, 0.96),
                    math.max(sec.xStart + 0.04, sec.xEnd).clamp(0.04, 1.0),
                  ),
                  min: 0.0,
                  max: 1.0,
                  divisions: 50,
                  activeColor: const Color(0xFF00F5D4),
                  onChanged: (rv) {
                    if (rv.end - rv.start >= 0.08) {
                      _updateSelectedSection(
                        sec.copyWith(xStart: rv.start, xEnd: rv.end),
                      );
                    }
                  },
                ),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Eave Height: ${(sec.eaveHeight * 100).round()}%',
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                          Slider(
                            value: sec.eaveHeight.clamp(0.20, 0.95),
                            min: 0.20,
                            max: 0.95,
                            activeColor: const Color(0xFF00F5D4),
                            onChanged: (v) {
                              _updateSelectedSection(
                                sec.copyWith(
                                  eaveHeight: v,
                                  peakHeight: sec.shape == 'flat_eave'
                                      ? v
                                      : math.max(sec.peakHeight, v + 0.05),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    if (sec.shape != 'flat_eave')
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Triangle Peak Height: ${(sec.peakHeight * 100).round()}%',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFFBBF24)),
                            ),
                            Slider(
                              value: math
                                  .max(sec.eaveHeight, sec.peakHeight)
                                  .clamp(0.20, 1.0),
                              min: 0.20,
                              max: 1.0,
                              activeColor: const Color(0xFFFBBF24),
                              onChanged: (v) {
                                _updateSelectedSection(
                                  sec.copyWith(
                                    peakHeight: math.max(sec.eaveHeight, v),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                Row(
                  children: [
                    if (sec.shape != 'flat_eave')
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Peak Center Position: ${(sec.peakOffset * 100).round()}%',
                              style: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w700),
                            ),
                            Slider(
                              value: sec.peakOffset.clamp(0.15, 0.85),
                              min: 0.15,
                              max: 0.85,
                              activeColor: const Color(0xFFA855F7),
                              onChanged: (v) => _updateSelectedSection(
                                sec.copyWith(peakOffset: v),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '3D Depth Step-Out: ${sec.depthOffset >= 0 ? "+" : ""}${(sec.depthOffset * 100).round()}%',
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                          Slider(
                            value: sec.depthOffset.clamp(-0.35, 0.35),
                            min: -0.35,
                            max: 0.35,
                            activeColor: const Color(0xFF38BDF8),
                            onChanged: (v) => _updateSelectedSection(
                              sec.copyWith(depthOffset: v),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilterChip(
                      selected: sec.hasGarage,
                      label: const Text('🚗 Garage Door',
                          style: TextStyle(fontSize: 11)),
                      onSelected: (v) =>
                          _updateSelectedSection(sec.copyWith(hasGarage: v)),
                    ),
                    FilterChip(
                      selected: sec.hasDoor,
                      label: const Text('🚪 Front Entry Door',
                          style: TextStyle(fontSize: 11)),
                      onSelected: (v) =>
                          _updateSelectedSection(sec.copyWith(hasDoor: v)),
                    ),
                    for (final wStyle in [
                      ('picture', '🪟 Picture (4-Window)'),
                      ('modern_grid', '🪟 Modern Grid (3-Win)'),
                      ('double_hung', '🪟 Double-Hung'),
                      ('double', '🪟 Double Window'),
                      ('arched', '🏛️ Arched Window'),
                      ('none', 'No Window'),
                    ])
                      ChoiceChip(
                        selected: sec.windowStyle == wStyle.$1,
                        label: Text(wStyle.$2,
                            style: const TextStyle(fontSize: 10.5)),
                        onSelected: (_) => _updateSelectedSection(
                          sec.copyWith(windowStyle: wStyle.$1),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildControllerLightPlacementTab() {
    final ctrl = _selectedController;
    if (ctrl == null) {
      return const Text('No controllers configured for this house.');
    }
    final allocatedTotal = ctrl.sectionSpans.fold<int>(
      0,
      (acc, sp) => acc + sp.segments,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Controller Strip & Assign Segments to Each Roof/Wall Section:',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Color(0xFF00F5D4),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _workingControllers.map((c) {
            final isSel = c.id == ctrl.id;
            return ChoiceChip(
              selected: isSel,
              selectedColor: const Color(0xFF00F5D4).withValues(alpha: 0.25),
              label: Text(
                '💡 ${c.name} • ${c.sku} (${c.segmentCount} segs)',
                style:
                    const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
              ),
              onSelected: (_) {
                setState(() {
                  _selectedControllerId = c.id;
                  _spotlightSegIdx = 0;
                });
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF0B1325),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: allocatedTotal == ctrl.segmentCount
                  ? const Color(0xFF00F5D4).withValues(alpha: 0.5)
                  : const Color(0xFFFBBF24).withValues(alpha: 0.65),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  Text(
                    'Allocated: $allocatedTotal / ${ctrl.segmentCount} segments across sections',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: allocatedTotal == ctrl.segmentCount
                          ? const Color(0xFF00F5D4)
                          : const Color(0xFFFBBF24),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: _resetCurrentHouseToRealPhotoLayout,
                        icon: const Icon(
                          Icons.photo_camera_back_outlined,
                          size: 14,
                          color: Color(0xFFFBBF24),
                        ),
                        label: const Text(
                          '📸 Photo Default Spans',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFFDE68A),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () =>
                            _autoBalanceControllerAcrossFrontSections(ctrl),
                        icon: const Icon(Icons.auto_fix_high, size: 14),
                        label: const Text(
                          'Auto-Fit Front Sections',
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 6),
                      FilterChip(
                        selected: ctrl.reversed,
                        label: const Text('Reverse Strip Order',
                            style: TextStyle(fontSize: 11)),
                        onSelected: (rev) {
                          setState(() {
                            _workingControllers = _workingControllers
                                .map((c) => c.id == ctrl.id
                                    ? c.copyWith(reversed: rev)
                                    : c)
                                .toList();
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '⚡ 1-Tap Wiring Route Presets:',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFC084FC),
                ),
              ),
              const SizedBox(height: 5),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final route in const [
                    ('bottom_to_top_ccw', '↺ Bottom → Top CCW (Real House Default)'),
                    ('upper_lower_front', 'Upper + Lower Front'),
                    ('upper_front_right', 'Upper Front + Right Side'),
                    ('lower_front_left_back', 'Lower Front + Left + Back'),
                    ('full_360_perimeter', 'Full 360° Perimeter'),
                  ])
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: const Color(0xFF060B18),
                      side: BorderSide(
                        color: const Color(0xFFA855F7).withValues(alpha: 0.55),
                      ),
                      label: Text(
                        route.$2,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFE9D5FF),
                        ),
                      ),
                      onPressed: () => _applyWiringRoutePreset(ctrl, route.$1),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Per-Section Segment Allocation Rows (with +/- steppers & LTR / RTL flip)
        for (final sec in _workingArch.sections)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Builder(
              builder: (context) {
                final segsOnSec =
                    _getControllerSegmentsForSection(ctrl, sec.id);
                final dirOnSec =
                    _getControllerDirectionForSection(ctrl, sec.id);
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: segsOnSec > 0
                        ? const Color(0xFF0F1A34)
                        : const Color(0xFF080E1E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: segsOnSec > 0
                          ? const Color(0xFF00F5D4).withValues(alpha: 0.45)
                          : const Color(0xFF1E293B),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${sec.isPitchedGable ? "🔺" : "⬛"} ${sec.label} (${sec.wall.toUpperCase()} • Story ${sec.story})',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          InkWell(
                            borderRadius: BorderRadius.circular(6),
                            onTap: () => _setControllerSegmentsForSection(
                              ctrl,
                              sec,
                              segsOnSec,
                              direction: (dirOnSec == 'rtl' ||
                                      dirOnSec == 'reverse')
                                  ? 'ltr'
                                  : 'rtl',
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF060B18),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: const Color(0xFF334155)),
                              ),
                              child: Text(
                                (dirOnSec == 'rtl' || dirOnSec == 'reverse')
                                    ? 'RTL ← (2F CCW)'
                                    : 'LTR → (1F CCW)',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFCBD5E1),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            borderRadius: BorderRadius.circular(6),
                            onTap: segsOnSec > 0
                                ? () => _setControllerSegmentsForSection(
                                      ctrl,
                                      sec,
                                      segsOnSec - 1,
                                    )
                                : null,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF060B18),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: const Color(0xFF334155)),
                              ),
                              child: const Text(
                                '−',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFFFBBF24),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$segsOnSec segs',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF00F5D4),
                            ),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            borderRadius: BorderRadius.circular(6),
                            onTap: segsOnSec < ctrl.segmentCount
                                ? () => _setControllerSegmentsForSection(
                                      ctrl,
                                      sec,
                                      segsOnSec + 1,
                                    )
                                : null,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF060B18),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: const Color(0xFF334155)),
                              ),
                              child: const Text(
                                '+',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF00F5D4),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: segsOnSec
                            .toDouble()
                            .clamp(0.0, ctrl.segmentCount.toDouble()),
                        min: 0,
                        max: ctrl.segmentCount.toDouble(),
                        divisions: math.max(1, ctrl.segmentCount),
                        activeColor: const Color(0xFF00F5D4),
                        onChanged: (v) {
                          _setControllerSegmentsForSection(
                            ctrl,
                            sec,
                            v.round(),
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

        const SizedBox(height: 8),
        // Physical Outdoor Segment Spotlight Finder
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0B1325),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFFFBBF24).withValues(alpha: 0.45),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '🔦 Spotlight Physical Segment (#${_spotlightSegIdx + 1} of ${ctrl.segmentCount})',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFFBBF24),
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFBBF24),
                      foregroundColor: const Color(0xFF040711),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () {
                      widget.api.locateControllerSegment(
                        ctrl.id,
                        _spotlightSegIdx.clamp(0, ctrl.segmentCount - 1),
                      );
                    },
                    icon: const Icon(Icons.my_location, size: 15),
                    label: Text(
                      'Flash Seg #${_spotlightSegIdx + 1} on House',
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              Slider(
                value: _spotlightSegIdx
                    .toDouble()
                    .clamp(0.0, math.max(0, ctrl.segmentCount - 1).toDouble()),
                min: 0,
                max: math.max(1, ctrl.segmentCount - 1).toDouble(),
                divisions: math.max(1, ctrl.segmentCount - 1),
                activeColor: const Color(0xFFFBBF24),
                onChanged: (v) {
                  setState(() {
                    _spotlightSegIdx = v.round();
                  });
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}


