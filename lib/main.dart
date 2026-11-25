import 'dart:async';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'storage_scanner.dart';

void main() => runApp(const PolarSaverApp());

/// Polar Suite Brand Palette: Royal Blue, Powder Blue, Silver, and White
class PolarColors {
  static const Color royalBlue = Color(0xFF1E40AF);
  static const Color deepRoyal = Color(0xFF172554);
  static const Color powderBlue = Color(0xFFB0E0E6);
  static const Color silver = Color(0xFFC0C0C0);
  static const Color white = Color(0xFFFFFFFF);
  static const Color iceSurface = Color(0xFFF4F9FC);
}

class PolarSaverApp extends StatelessWidget {
  const PolarSaverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Polar Saver',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: const ColorScheme.light(
          primary: PolarColors.royalBlue,
          onPrimary: PolarColors.white,
          secondary: PolarColors.powderBlue,
          onSecondary: PolarColors.deepRoyal,
          surface: PolarColors.white,
          onSurface: PolarColors.deepRoyal,
          outline: PolarColors.silver,
        ),
        scaffoldBackgroundColor: PolarColors.iceSurface,
      ),
      home: const PolarSaverHomePage(),
    );
  }
}

class PolarSaverHomePage extends StatefulWidget {
  const PolarSaverHomePage({super.key});

  @override
  State<PolarSaverHomePage> createState() => _PolarSaverHomePageState();
}

class _PolarSaverHomePageState extends State<PolarSaverHomePage> {
  final Battery _battery = Battery();
  StreamSubscription<BatteryState>? _batteryStateSub;
  Timer? _pollTimer;

  int _tabIndex = 0;

  // Battery metrics
  int _batteryLevel = 100;
  BatteryState _batteryState = BatteryState.unknown;
  bool _inBatterySaveMode = false;
  double _chargeAlertLimit = 80;
  bool _chargeAlertEnabled = true;
  bool _alertShownForCycle = false;

  // Duplicate Finder state
  bool _scanningDuplicates = false;
  List<DuplicateGroup> _duplicateGroups = [];

  // Residual Cleaner state
  bool _scanningJunk = false;
  JunkScanResult? _junkResult;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _initBatteryMonitoring();
  }

  @override
  void dispose() {
    _batteryStateSub?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _chargeAlertLimit = prefs.getDouble('charge_alert_limit') ?? 80;
        _chargeAlertEnabled = prefs.getBool('charge_alert_enabled') ?? true;
      });
    }
  }

  Future<void> _saveChargePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('charge_alert_limit', _chargeAlertLimit);
    await prefs.setBool('charge_alert_enabled', _chargeAlertEnabled);
  }

  Future<void> _initBatteryMonitoring() async {
    await _refreshBatteryStats();
    _batteryStateSub = _battery.onBatteryStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _batteryState = state;
          if (state == BatteryState.discharging) {
            _alertShownForCycle = false;
          }
        });
      }
      _refreshBatteryStats();
    });
    _pollTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _refreshBatteryStats(),
    );
  }

  Future<void> _refreshBatteryStats() async {
    try {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      final saveMode = await _battery.isInBatterySaveMode;
      if (!mounted) return;
      setState(() {
        _batteryLevel = level;
        _batteryState = state;
        _inBatterySaveMode = saveMode;
      });

      if (_chargeAlertEnabled &&
          state == BatteryState.charging &&
          level >= _chargeAlertLimit.round() &&
          !_alertShownForCycle) {
        _alertShownForCycle = true;
        _showToast(
          'Polar Saver: Battery reached $level%. Unplug now to extend battery lifespan!',
        );
      }
    } catch (_) {}
  }

  Future<void> _scanDuplicates() async {
    setState(() => _scanningDuplicates = true);
    try {
      final groups = await StorageScanner.findDuplicates();
      if (mounted) {
        setState(() => _duplicateGroups = groups);
        if (groups.isEmpty) {
          _showToast('No duplicate files found in accessible folders.');
        }
      }
    } finally {
      if (mounted) setState(() => _scanningDuplicates = false);
    }
  }

  Future<void> _deleteDuplicateExtras(DuplicateGroup group) async {
    int deleted = 0;
    // Keep the first file, remove duplicates
    for (int i = 1; i < group.files.length; i++) {
      try {
        await group.files[i].delete();
        deleted++;
      } catch (_) {}
    }
    _showToast('Removed $deleted duplicate file(s).');
    await _scanDuplicates();
  }

  Future<void> _scanJunk() async {
    setState(() => _scanningJunk = true);
    try {
      final res = await StorageScanner.scanResidualJunk();
      if (mounted) setState(() => _junkResult = res);
    } finally {
      if (mounted) setState(() => _scanningJunk = false);
    }
  }

  Future<void> _cleanJunk() async {
    if (_junkResult == null) return;
    int removedFiles = 0;
    int removedDirs = 0;

    for (final f in _junkResult!.tempFiles) {
      try {
        await f.delete();
        removedFiles++;
      } catch (_) {}
    }
    for (final d in _junkResult!.emptyDirs) {
      try {
        await d.delete();
        removedDirs++;
      } catch (_) {}
    }

    _showToast(
      'Cleaned $removedFiles residual temp file(s) and $removedDirs empty folder(s).',
    );
    await _scanJunk();
  }

  void _showToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: PolarColors.deepRoyal,
        content: Text(msg, style: const TextStyle(color: PolarColors.white)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String get _batteryStateLabel => switch (_batteryState) {
        BatteryState.charging => 'Charging',
        BatteryState.full => 'Fully Charged',
        BatteryState.discharging => 'On Battery',
        BatteryState.connectedNotCharging => 'Plugged In (Not Charging)',
        _ => 'Monitoring',
      };

  String get _estimatedRuntime {
    if (_batteryState == BatteryState.charging) {
      final remaining = (100 - _batteryLevel).clamp(0, 100);
      final mins = (remaining * 1.1).round();
      return '~$mins min to full';
    }
    final hrs = (_batteryLevel * 0.14).toStringAsFixed(1);
    return '~$hrs hrs remaining';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: PolarColors.royalBlue,
        foregroundColor: PolarColors.white,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/icon/polar_saver_icon.png',
                width: 32,
                height: 32,
              ),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Polar Saver',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                Text(
                  'Battery & Device Health',
                  style: TextStyle(
                    fontSize: 11,
                    color: PolarColors.powderBlue,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: [
          _buildBatteryTab(),
          _buildDuplicatesTab(),
          _buildHealthCleanerTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        backgroundColor: PolarColors.white,
        indicatorColor: PolarColors.powderBlue,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.battery_charging_full_outlined),
            selectedIcon: Icon(
              Icons.battery_charging_full,
              color: PolarColors.royalBlue,
            ),
            label: 'Battery',
          ),
          NavigationDestination(
            icon: Icon(Icons.file_copy_outlined),
            selectedIcon: Icon(Icons.file_copy, color: PolarColors.royalBlue),
            label: 'Duplicates',
          ),
          NavigationDestination(
            icon: Icon(Icons.cleaning_services_outlined),
            selectedIcon: Icon(
              Icons.cleaning_services,
              color: PolarColors.royalBlue,
            ),
            label: 'Health & Clean',
          ),
        ],
      ),
    );
  }

  Widget _buildBatteryTab() {
    return RefreshIndicator(
      color: PolarColors.royalBlue,
      onRefresh: _refreshBatteryStats,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Hero Battery Gauge Card
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [PolarColors.royalBlue, PolarColors.deepRoyal],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: PolarColors.silver, width: 1.5),
            ),
            padding: const EdgeInsets.all(22),
            child: Column(
              children: [
                SizedBox(
                  width: 140,
                  height: 140,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        value: _batteryLevel / 100.0,
                        strokeWidth: 12,
                        backgroundColor: PolarColors.white.withValues(alpha: 0.18),
                        color: PolarColors.powderBlue,
                      ),
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$_batteryLevel%',
                              style: const TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: PolarColors.white,
                              ),
                            ),
                            Text(
                              _batteryStateLabel,
                              style: const TextStyle(
                                fontSize: 12,
                                color: PolarColors.powderBlue,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _statPill('Estimate', _estimatedRuntime),
                    _statPill(
                      'Power Saver',
                      _inBatterySaveMode ? 'Active' : 'Off',
                    ),
                    _statPill(
                      'Health Care',
                      _batteryLevel <= 85 ? 'Optimal' : 'High Charge',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Charge Limit Alarm Card
          Card(
            color: PolarColors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: PolarColors.silver, width: 1.2),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.shield, color: PolarColors.royalBlue),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Battery Lifespan Charge Alert',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: PolarColors.deepRoyal,
                          ),
                        ),
                      ),
                      Switch(
                        activeTrackColor: PolarColors.royalBlue,
                        value: _chargeAlertEnabled,
                        onChanged: (v) {
                          setState(() => _chargeAlertEnabled = v);
                          _saveChargePrefs();
                        },
                      ),
                    ],
                  ),
                  const Text(
                    'Unplugging around 80–85% reduces lithium-ion wear and keeps your battery healthy for years.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text(
                        'Alert at:',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Expanded(
                        child: Slider(
                          activeColor: PolarColors.royalBlue,
                          min: 60,
                          max: 100,
                          divisions: 8,
                          label: '${_chargeAlertLimit.round()}%',
                          value: _chargeAlertLimit,
                          onChanged: (v) {
                            setState(() => _chargeAlertLimit = v);
                            _saveChargePrefs();
                          },
                        ),
                      ),
                      Text(
                        '${_chargeAlertLimit.round()}%',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: PolarColors.royalBlue,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Battery Optimization Checklist
          Card(
            color: PolarColors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: PolarColors.silver, width: 1.2),
            ),
            child: const Column(
              children: [
                ListTile(
                  leading: Icon(Icons.thermostat, color: PolarColors.royalBlue),
                  title: Text(
                    'Avoid Heat While Charging',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'Keep your phone out of direct sun or heavy gaming while plugged in.',
                  ),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.brightness_6, color: PolarColors.royalBlue),
                  title: Text(
                    'Adaptive Brightness & Screen Timeout',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'Setting screen timeout to 30 seconds is the #1 daily battery saver.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statPill(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: PolarColors.powderBlue),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: PolarColors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildDuplicatesTab() {
    final totalReclaimable = _duplicateGroups.fold<int>(
      0,
      (sum, g) => sum + g.reclaimableBytes,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: PolarColors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: PolarColors.silver, width: 1.2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Duplicate File Scanner (SHA-256)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: PolarColors.deepRoyal,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Compares file sizes and cryptographic SHA-256 hashes to find exact duplicate downloads, documents, and photos.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: PolarColors.royalBlue,
                    ),
                    onPressed: _scanningDuplicates ? null : _scanDuplicates,
                    icon: _scanningDuplicates
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: PolarColors.white,
                            ),
                          )
                        : const Icon(Icons.search),
                    label: Text(
                      _scanningDuplicates
                          ? 'Scanning Files...'
                          : 'Scan for Duplicate Files',
                    ),
                  ),
                ),
                if (_duplicateGroups.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Found ${_duplicateGroups.length} duplicate group(s) • '
                    '${StorageScanner.formatBytes(totalReclaimable)} reclaimable',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: PolarColors.royalBlue,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        ..._duplicateGroups.map((group) {
          final sampleName = p.basename(group.files.first.path);
          return Card(
            color: PolarColors.white,
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: PolarColors.silver),
            ),
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: PolarColors.powderBlue,
                foregroundColor: PolarColors.deepRoyal,
                child: Icon(Icons.file_copy),
              ),
              title: Text(
                sampleName,
                style: const TextStyle(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${group.files.length} copies • Save ${StorageScanner.formatBytes(group.reclaimableBytes)}',
              ),
              trailing: TextButton(
                onPressed: () => _deleteDuplicateExtras(group),
                child: const Text('Clean Extras'),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildHealthCleanerTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: PolarColors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: PolarColors.silver, width: 1.2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Residual Temp & Empty Folder Cleaner',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: PolarColors.deepRoyal,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Android does not use a Windows-style registry—instead, clutter builds up as temporary files (.tmp, .log, .bak) and orphaned empty folders.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: PolarColors.royalBlue,
                        ),
                        onPressed: _scanningJunk ? null : _scanJunk,
                        icon: _scanningJunk
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: PolarColors.white,
                                ),
                              )
                            : const Icon(Icons.radar),
                        label: const Text('Scan Clutter'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: (_junkResult != null &&
                                (_junkResult!.tempFiles.isNotEmpty ||
                                    _junkResult!.emptyDirs.isNotEmpty))
                            ? _cleanJunk
                            : null,
                        icon: const Icon(Icons.cleaning_services),
                        label: const Text('Clean Now'),
                      ),
                    ),
                  ],
                ),
                if (_junkResult != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: PolarColors.iceSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: PolarColors.powderBlue),
                    ),
                    child: Text(
                      'Temp files: ${_junkResult!.tempFiles.length} '
                      '(${StorageScanner.formatBytes(_junkResult!.totalJunkBytes)})\n'
                      'Empty folders: ${_junkResult!.emptyDirs.length}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: PolarColors.deepRoyal,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
