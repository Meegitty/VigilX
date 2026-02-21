import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geocoding/geocoding.dart';

import '../services/location_service.dart';
import '../services/sos_service.dart';
import '../storage/emergency_contacts_store.dart';
import '../models/emergency_contact.dart';
import 'manage_contacts_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool monitoringOn = true;

  LocationSnapshot? _loc;
  String? _locError;
  bool _loadingLoc = false;
  DateTime? _lastLocationUpdate;
  String? _locName;

  StreamSubscription<LocationSnapshot>? _locSub;

  List<EmergencyContact> _contacts = [];

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _refreshLocation();
    _startLiveLocation();
  }

  @override
  void dispose() {
    _stopLiveLocation();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    final list = await EmergencyContactsStore.load();
    if (!mounted) return;
    setState(() => _contacts = list);
  }

  Future<void> _refreshLocation() async {
    setState(() {
      _loadingLoc = true;
      _locError = null;
    });

    try {
      final snap = await LocationService.getCurrent();
      if (!mounted) return;
      setState(() {
        _loc = snap;
        _lastLocationUpdate = DateTime.now();
      });
      await _updatePlaceName(snap);
    } catch (e) {
      if (!mounted) return;
      setState(() => _locError = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => _loadingLoc = false);
    }
  }

  Future<void> _startLiveLocation() async {
    _locSub?.cancel();

    // Only track when monitoring is enabled
    if (!monitoringOn) return;

    try {
      final stream = await LocationService.subscribeToLocationChanges();
      _locSub = stream.listen(
        (snap) {
          if (!mounted || !monitoringOn) return;
          setState(() {
            _loc = snap;
            _lastLocationUpdate = DateTime.now();
            _locError = null;
          });
          _updatePlaceName(snap);
        },
        onError: (e) {
          if (!mounted) return;
          setState(() => _locError = e.toString());
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _locError = e.toString());
    }
  }

  void _stopLiveLocation() {
    _locSub?.cancel();
    _locSub = null;
  }

  Future<void> _updatePlaceName(LocationSnapshot snap) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        snap.latitude,
        snap.longitude,
      );
      if (!mounted || placemarks.isEmpty) return;

      final p = placemarks.first;
      final parts = <String>[
        if ((p.name ?? '').isNotEmpty) p.name!,
        if ((p.locality ?? '').isNotEmpty) p.locality!,
        if ((p.administrativeArea ?? '').isNotEmpty) p.administrativeArea!,
      ];

      setState(() {
        _locName = parts.isEmpty ? null : parts.join(', ');
      });
    } catch (_) {
      // If reverse geocoding fails, just keep coordinates.
    }
  }

  Future<void> _openInMaps() async {
    final loc = _loc;
    if (loc == null) return;

    final uri = Uri.parse('https://maps.google.com/?q=${loc.latitude},${loc.longitude}');
    final ok = await canLaunchUrl(uri);
    if (!ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Maps on this device.')),
      );
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _sendTestSOS() async {
    if (_contacts.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one emergency contact first.')),
      );
      return;
    }

    // Use current location if we have it; otherwise attempt refresh once
    var loc = _loc;
    if (loc == null) {
      await _refreshLocation();
      loc = _loc;
    }

    final message = SosService.buildSosMessage(
      isTest: true,
      time: DateTime.now(),
      location: loc,
    );

    // Open SMS composer for each contact (simple cross-platform path)
    for (final c in _contacts) {
      await SosService.openSmsComposer(phoneNumber: c.phone, body: message);
    }
  }

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF1E5AA8);
    const blueSoft = Color(0xFFDFEBFF);

    final loc = _loc;

    // GPS accuracy UI
    Color accuracyColor = Colors.grey;
    String accuracyText = 'Unknown';
    IconData accuracyIcon = Icons.gps_off;

    if (loc != null) {
      if (loc.accuracyMeters <= 20) {
        accuracyColor = Colors.green;
        accuracyText = 'Excellent (±${loc.accuracyMeters.toStringAsFixed(0)}m)';
        accuracyIcon = Icons.gps_fixed;
      } else if (loc.accuracyMeters <= 50) {
        accuracyColor = Colors.lightGreen;
        accuracyText = 'Good (±${loc.accuracyMeters.toStringAsFixed(0)}m)';
        accuracyIcon = Icons.gps_fixed;
      } else if (loc.accuracyMeters <= 100) {
        accuracyColor = Colors.orange;
        accuracyText = 'Fair (±${loc.accuracyMeters.toStringAsFixed(0)}m)';
        accuracyIcon = Icons.gps_not_fixed;
      } else {
        accuracyColor = Colors.red;
        accuracyText = 'Poor (±${loc.accuracyMeters.toStringAsFixed(0)}m)';
        accuracyIcon = Icons.gps_not_fixed;
      }
    }

    // Last update text
    String lastUpdateText = 'Never';
    if (_lastLocationUpdate != null) {
      final now = DateTime.now();
      final diff = now.difference(_lastLocationUpdate!);
      if (diff.inSeconds < 60) {
        lastUpdateText = 'Just now';
      } else if (diff.inMinutes < 60) {
        lastUpdateText = '${diff.inMinutes}m ago';
      } else {
        lastUpdateText = '${diff.inHours}h ago';
      }
    }

    final locText = (loc == null)
        ? (_loadingLoc ? 'Getting location…' : 'Location unavailable')
        : '${loc.latitude.toStringAsFixed(6)}, ${loc.longitude.toStringAsFixed(6)} (±${loc.accuracyMeters.toStringAsFixed(0)}m)';

    return Scaffold(
      appBar: AppBar(
        title: const Text('VigilX'),
        backgroundColor: Colors.transparent,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Row(
                children: [
                  Icon(
                    monitoringOn ? Icons.shield : Icons.shield_outlined,
                    color: monitoringOn ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    monitoringOn ? 'Monitoring ON' : 'Monitoring OFF',
                    style: TextStyle(
                      color: monitoringOn ? Colors.green : Colors.grey,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Monitoring Card
          Card(
            color: blueSoft,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Crash Monitoring',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: blue,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          monitoringOn
                              ? 'Crash detection is ready. Keep GPS on.'
                              : 'Turn monitoring on to enable crash detection.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: monitoringOn,
                    onChanged: (v) {
                      setState(() => monitoringOn = v);
                      if (v) {
                        _startLiveLocation();
                      } else {
                        _stopLiveLocation();
                      }
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // GPS Location Card - Enhanced
          Card(
            color: blueSoft,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(accuracyIcon, color: accuracyColor, size: 28),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'GPS Location',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: blue,
                                  ),
                            ),
                            Text(
                              'Updated: $lastUpdateText',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.black54,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _loadingLoc ? null : _refreshLocation,
                        icon: _loadingLoc
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh),
                        tooltip: 'Refresh location',
                      ),
                    ],
                  ),
                  const Divider(height: 24),

                  Row(
                    children: [
                      Icon(Icons.signal_cellular_alt, size: 18, color: accuracyColor),
                      const SizedBox(width: 8),
                      Text(
                        'Signal: $accuracyText',
                        style: TextStyle(
                          color: accuracyColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Location name + coordinates (tap to track in Maps)
                  InkWell(
                    onTap: loc != null ? _openInMaps : null,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: blue.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on, color: blue, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _locName ?? (loc == null ? 'Location unknown' : 'Finding place name…'),
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: Colors.black87,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  locText,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Colors.black87,
                                        fontFamily: 'monospace',
                                      ),
                                ),
                              ],
                            ),
                          ),
                          if (loc != null)
                            const Icon(
                              Icons.navigation,
                              color: Colors.blueAccent,
                              size: 20,
                            ),
                        ],
                      ),
                    ),
                  ),

                  if (_locError != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _locError!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.blue),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'For best accuracy, ensure GPS is on and you\'re outdoors',
                            style: TextStyle(fontSize: 12, color: Colors.blue),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Emergency contacts
          Card(
            color: Colors.red.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.people, color: Colors.red),
                      const SizedBox(width: 8),
                      Text(
                        'Emergency contacts',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Colors.red.shade900,
                            ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const ManageContactsScreen()),
                          );
                          await _loadContacts();
                        },
                        style: TextButton.styleFrom(foregroundColor: Colors.red.shade900),
                        child: const Text('Edit'),
                      )
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_contacts.isEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('No contacts yet. Tap Edit to add.', style: TextStyle(color: Colors.red.shade900)),
                    )
                  else
                    ..._contacts.take(3).map(
                          (c) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.person, color: Colors.red.shade700),
                            title: Text(c.name, style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.w600)),
                            subtitle: Text(c.phone, style: TextStyle(color: Colors.red.shade700)),
                          ),
                        ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Send via: SMS (opens message app)',
                      style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                    ),
                  )
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Actions
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton.icon(
                    onPressed: _sendTestSOS,
                    icon: const Icon(Icons.sms),
                    label: const Text('Send test SOS'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _refreshLocation,
                    icon: const Icon(Icons.my_location),
                    label: const Text('Update location now'),
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