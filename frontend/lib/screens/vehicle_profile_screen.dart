import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart' show UserSession;
import '../widgets/notification_bell.dart';

const _baseUrl = 'http://localhost:8001';

class VehicleProfileScreen extends StatefulWidget {
  const VehicleProfileScreen({super.key});

  @override
  State<VehicleProfileScreen> createState() => _VehicleProfileScreenState();
}

class _VehicleProfileScreenState extends State<VehicleProfileScreen> {
  final _storage = const FlutterSecureStorage();

  List<Map<String, dynamic>> _vehicles = [];
  int? _expandedIndex;
  String? _userName;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initUser();
    _loadVehicles();
  }

  Future<void> _initUser() async {
    final session = UserSession.instance;
    if (session.user != null) {
      if (mounted) setState(() => _userName = session.user!['name'] as String?);
      return;
    }
    final token = session.token;
    if (token == null) return;
    try {
      final res = await Dio(
        BaseOptions(
          baseUrl: _baseUrl,
          headers: {'Authorization': 'Bearer $token'},
          connectTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 5),
        ),
      ).get('/auth/me');
      session.user = Map<String, dynamic>.from(res.data as Map);
      if (mounted) setState(() => _userName = session.user!['name'] as String?);
    } catch (_) {}
  }

  Future<String?> _getToken() async {
    if (UserSession.instance.token != null) return UserSession.instance.token;
    try {
      return await _storage.read(key: 'jwt_token');
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadVehicles() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final token = await _getToken();
    if (token == null) {
      setState(() {
        _loading = false;
        _error = 'Not logged in.';
      });
      return;
    }
    try {
      final res = await Dio(
        BaseOptions(
          baseUrl: _baseUrl,
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
          headers: {'Authorization': 'Bearer $token'},
        ),
      ).get('/vehicles');
      setState(() {
        _vehicles = (res.data as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } on DioException catch (e) {
      setState(() {
        _loading = false;
        _error =
            e.response?.data?['detail']?.toString() ??
            'Could not load vehicles.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        centerTitle: false,

        leading: Padding(
          padding: const EdgeInsets.all(10),
          child: CircleAvatar(
            backgroundColor: AppColors.primaryContainer,
            child: Text(
              _userName != null && _userName!.isNotEmpty
                  ? _userName![0].toUpperCase()
                  : '?',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.onPrimary,
              ),
            ),
          ),
        ),

        title: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'MFU TRACKER',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
            if (_userName != null && _userName!.isNotEmpty)
              Text(
                _userName!,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: AppColors.onPrimary,
                ),
              ),
          ],
        ),

        actions: [
          IconButton(
            onPressed: _showAddVehicleSheet,
            icon: const Icon(
              Icons.add_circle_outline,
              color: AppColors.onPrimary,
            ),
            tooltip: 'Add Vehicle',
          ),
          const NotificationBell(
            color: AppColors.onPrimary,
            padding: EdgeInsets.only(right: 8),
          ),
        ],
      ),
      body: RefreshIndicator(onRefresh: _loadVehicles, child: _buildBody()),
    );
  }

  Future<void> _showAddVehicleSheet() async {
    if (_vehicles.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Vehicle Limit Reached'),
          content: const Text(
            'You can only register 1 vehicle per account. Please remove your existing vehicle before adding a new one.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    final token = await _getToken();
    if (!mounted) return;
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Not logged in.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddVehicleSheet(
        token: token,
        onCreated: (created) => setState(() {
          _vehicles = [..._vehicles, created];
          _expandedIndex = _vehicles.length - 1;
        }),
      ),
    );
  }

  Future<void> _deleteVehicle(int index) async {
    final token = await _getToken();
    final vehicleId = _vehicles[index]['id'] as String?;
    if (token == null || vehicleId == null) return;
    try {
      await Dio(
        BaseOptions(
          baseUrl: _baseUrl,
          headers: {'Authorization': 'Bearer $token'},
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      ).delete('/vehicles/$vehicleId');
      if (!mounted) return;
      setState(() {
        _vehicles = [..._vehicles]..removeAt(index);
        _expandedIndex = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vehicle removed'),
          backgroundColor: AppColors.green,
        ),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.response?.data?['detail']?.toString() ??
                'Could not remove vehicle.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _vehicles.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 40),
          Center(
            child: Text(
              _error!,
              style: const TextStyle(color: AppColors.error),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: OutlinedButton(
              onPressed: _loadVehicles,
              child: const Text('Retry'),
            ),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionHeader(
          icon: Icons.two_wheeler,
          title: 'Vehicle Profile',
          subtitle:
              'Manage your registered motorcycle details and surveillance settings.',
        ),
        const SizedBox(height: 12),
        if (_vehicles.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('No vehicle registered yet.')),
          ),
        ..._vehicles.asMap().entries.map(
          (e) => _VehicleCard(
            key: ValueKey(e.value['id']),
            data: e.value,
            index: e.key,
            isExpanded: _expandedIndex == e.key,
            onToggle: () => setState(() {
              _expandedIndex = _expandedIndex == e.key ? null : e.key;
            }),
            onSaved: (updated) => setState(() => _vehicles[e.key] = updated),
            onDelete: () => _deleteVehicle(e.key),
          ),
        ),
        const SizedBox(height: 8),
        if (_vehicles.isNotEmpty)
          _DetectionThresholdCard(
            vehicleId: _vehicles.first["id"],
            detection: _vehicles.first["detection"] ?? 1,
          ), // ถ้าในอนาคต 1 User มีหลาย Vehicle ควรให้ Detection Card อยู่ในแต่ละ _VehicleCard ไม่ใช่มี Detection Card เดียวอยู่ล่างสุด
        const SizedBox(height: 32),
      ],
    );
  }
}

// ── Vehicle Card (expandable) ─────────────────────────────────────────────────

class _VehicleCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final int index;
  final bool isExpanded;
  final VoidCallback onToggle;
  final ValueChanged<Map<String, dynamic>> onSaved;
  final VoidCallback onDelete;

  const _VehicleCard({
    super.key,
    required this.data,
    required this.index,
    required this.isExpanded,
    required this.onToggle,
    required this.onSaved,
    required this.onDelete,
  });

  @override
  State<_VehicleCard> createState() => _VehicleCardState();
}

class _VehicleCardState extends State<_VehicleCard> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _modelCtrl;
  late final TextEditingController _plateCtrl;
  late final TextEditingController _provinceCtrl;
  late final TextEditingController _colorCtrl;
  late final TextEditingController _geofenceCtrl;

  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    _modelCtrl = TextEditingController(text: d['model'] ?? '');
    _plateCtrl = TextEditingController(text: d['license_plate'] ?? '');
    _provinceCtrl = TextEditingController(text: d['province'] ?? '');
    _colorCtrl = TextEditingController(text: d['color'] ?? '');
    _geofenceCtrl = TextEditingController(
      text: (d['geofence_radius_m'] ?? 50).toString(),
    );

    for (final c in [
      _modelCtrl,
      _plateCtrl,
      _provinceCtrl,
      _colorCtrl,
      _geofenceCtrl,
    ]) {
      c.addListener(() => setState(() => _dirty = true));
    }
  }

  @override
  void dispose() {
    _modelCtrl.dispose();
    _plateCtrl.dispose();
    _provinceCtrl.dispose();
    _colorCtrl.dispose();
    _geofenceCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final token = UserSession.instance.token;
    final vehicleId = widget.data['id'] as String?;
    if (token == null || vehicleId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Not logged in.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final patchRes =
          await Dio(
            BaseOptions(
              baseUrl: _baseUrl,
              headers: {'Authorization': 'Bearer $token'},
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 5),
            ),
          ).patch(
            '/vehicles/$vehicleId',
            data: {
              'model': _modelCtrl.text.trim(),
              'license_plate': _plateCtrl.text.trim(),
              'province': _provinceCtrl.text.trim(),
              'color': _colorCtrl.text.trim(),
              'geofence_radius_m': int.tryParse(_geofenceCtrl.text) ?? 50,
            },
          );
      final result = patchRes.data as Map<String, dynamic>;

      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = false;
      });
      widget.onSaved(result);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile saved'),
          backgroundColor: AppColors.green,
        ),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.response?.data?['detail']?.toString() ??
                'Could not save profile.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _discard() {
    final d = widget.data;
    _modelCtrl.text = d['model'] ?? '';
    _plateCtrl.text = d['license_plate'] ?? '';
    _provinceCtrl.text = d['province'] ?? '';
    _colorCtrl.text = d['color'] ?? '';
    _geofenceCtrl.text = (d['geofence_radius_m'] ?? 50).toString();
    setState(() => _dirty = false);
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Vehicle'),
        content: const Text(
          'Are you sure you want to remove this vehicle? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) widget.onDelete();
  }

  @override
  Widget build(BuildContext context) {
    final label = _plateCtrl.text.isNotEmpty
        ? _plateCtrl.text
        : 'Motorcycle Profile ${widget.index + 1}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: const Border(
          left: BorderSide(color: AppColors.primary, width: 4),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: widget.onToggle,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.motorcycle,
                      color: AppColors.onPrimaryContainer,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ),
                  if (_dirty)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.secondary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  IconButton(
                    onPressed: widget.onToggle,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    color: AppColors.primary,
                    tooltip: 'Edit',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    widget.isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (widget.isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(color: AppColors.outlineVariant, height: 1),
                    const SizedBox(height: 16),
                    _buildIdentificationSection(),
                    const SizedBox(height: 20),
                    _buildActionButtons(),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildIdentificationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldHeader(
          icon: Icons.badge_outlined,
          title: 'Identification Details',
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _modelCtrl,
          decoration: const InputDecoration(labelText: 'Vehicle Model'),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _plateCtrl,
          decoration: const InputDecoration(labelText: 'License Plate'),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _provinceCtrl,
          decoration: const InputDecoration(labelText: 'Province'),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _colorCtrl,
          decoration: const InputDecoration(labelText: 'Color'),
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.done,
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: (_dirty && !_saving) ? _discard : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  minimumSize: const Size.fromHeight(44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Discard Changes'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(_saving ? 'SAVING…' : 'SAVE PROFILE'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _saving ? null : _confirmDelete,
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('Remove Vehicle'),
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
        ),
      ],
    );
  }
}

// ── Detection Threshold Card ──────────────────────────────────────────────────

class _DetectionThresholdCard extends StatefulWidget {
  final String vehicleId;
  final int detection;

  const _DetectionThresholdCard({
    required this.vehicleId,
    required this.detection,
  });

  @override
  State<_DetectionThresholdCard> createState() =>
      _DetectionThresholdCardState();
}

class _DetectionThresholdCardState extends State<_DetectionThresholdCard> {
  int _selectedDelay = 1;

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _selectedDelay = widget.detection; //_selectedDelay = widget.detection ?? 2;
  }

  Future<void> _save() async {
    final token = UserSession.instance.token;

    if (token == null) return;

    final dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,

        headers: {"Authorization": "Bearer $token"},
      ),
    );

    try {
      await dio.put(
        "/vehicle/detection",

        data: {"vehicle_id": widget.vehicleId, "detection": _selectedDelay},
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Detection threshold updated"),
          backgroundColor: AppColors.green,
        ),
      );
    } on DioException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.response?.data["detail"] ?? "Unable to save"),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: const Border(
          left: BorderSide(color: AppColors.secondaryContainer, width: 4),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FieldHeader(
            icon: Icons.videocam_outlined,
            title: 'Detection Threshold',
          ),
          const SizedBox(height: 6),
          const Text(
            'Set the delay before the campus CCTV network begins actively tracking this vehicle after leaving a designated parking zone. Minimum threshold is 1 minute.',
            style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _selectedDelay,
                  decoration: const InputDecoration(
                    labelText: 'Delay Time',
                    prefixIcon: Icon(Icons.timer_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1 Minute')),
                    DropdownMenuItem(value: 2, child: Text('2 Minutes')),
                    DropdownMenuItem(value: 3, child: Text('3 Minutes')),
                    DropdownMenuItem(value: 4, child: Text('4 Minutes')),
                    DropdownMenuItem(value: 5, child: Text('5 Minutes')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedDelay = value;
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(72, 56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                ),
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Add Vehicle Bottom Sheet ──────────────────────────────────────────────────

class _AddVehicleSheet extends StatefulWidget {
  final String token;
  final ValueChanged<Map<String, dynamic>> onCreated;

  const _AddVehicleSheet({required this.token, required this.onCreated});

  @override
  State<_AddVehicleSheet> createState() => _AddVehicleSheetState();
}

class _AddVehicleSheetState extends State<_AddVehicleSheet> {
  final _formKey = GlobalKey<FormState>();
  final _modelCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();
  final _provinceCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _modelCtrl.dispose();
    _plateCtrl.dispose();
    _provinceCtrl.dispose();
    _colorCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final createRes =
          await Dio(
            BaseOptions(
              baseUrl: _baseUrl,
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 5),
              headers: {'Authorization': 'Bearer ${widget.token}'},
            ),
          ).post(
            '/vehicles',
            data: {
              'model': _modelCtrl.text.trim(),
              'license_plate': _plateCtrl.text.trim(),
              'province': _provinceCtrl.text.trim(),
              'color': _colorCtrl.text.trim(),
              'geofence_radius_m': 5,
            },
          );
      final vehicle = createRes.data as Map<String, dynamic>;

      widget.onCreated(vehicle);
      if (!mounted) return;
      Navigator.of(context).pop();
    } on DioException catch (e) {
      setState(() {
        _saving = false;
        _error =
            e.response?.data?['detail']?.toString() ?? 'Could not add vehicle.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: AppColors.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text(
                  'Add Vehicle',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: AppColors.error)),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _modelCtrl,
                  decoration: const InputDecoration(labelText: 'Vehicle Model'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _plateCtrl,
                  decoration: const InputDecoration(labelText: 'License Plate'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _provinceCtrl,
                  decoration: const InputDecoration(labelText: 'Province'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _colorCtrl,
                  decoration: const InputDecoration(labelText: 'Color'),
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.done,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          side: const BorderSide(
                            color: AppColors.outlineVariant,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _saving ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryContainer,
                          foregroundColor: AppColors.onPrimary,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.onPrimary,
                                ),
                              )
                            : const Text('Add Vehicle'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _FieldHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _FieldHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurface,
          ),
        ),
      ],
    );
  }
}
