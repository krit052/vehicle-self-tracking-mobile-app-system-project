import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import 'notifications_screen.dart';

// Static mock vehicles
final _mockVehicles = [
  {
    'id': 'v1',
    'model': 'Honda Wave 110i',
    'license_plate': 'กข-1234',
  },
];

class VehicleProfileScreen extends StatefulWidget {
  const VehicleProfileScreen({super.key});

  @override
  State<VehicleProfileScreen> createState() => _VehicleProfileScreenState();
}

class _VehicleProfileScreenState extends State<VehicleProfileScreen> {
  List<Map<String, dynamic>> _vehicles = List<Map<String, dynamic>>.from(_mockVehicles);
  int? _expandedIndex;


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        title: const Text(
          'MFU TRACKER',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 1.5),
        ),
        centerTitle: false,
        leading: const Padding(
          padding: EdgeInsets.all(12),
          child: Icon(Icons.person, color: AppColors.onPrimary),
        ),
        actions: [
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
            icon: const Icon(Icons.notifications_outlined, color: AppColors.onPrimary),
            padding: const EdgeInsets.only(right: 8),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader(
            icon: Icons.two_wheeler,
            title: 'Vehicle Profile',
            subtitle: 'Manage your registered motorcycle details and surveillance settings.',
          ),
          const SizedBox(height: 12),
          ..._vehicles.asMap().entries.map((e) => _VehicleCard(
                key: ValueKey(e.key),
                data: e.value,
                index: e.key,
                isExpanded: _expandedIndex == e.key,
                onToggle: () => setState(() {
                  _expandedIndex = _expandedIndex == e.key ? null : e.key;
                }),
                onSaved: (updated) => setState(() => _vehicles[e.key] = updated),
              )),
          const SizedBox(height: 8),
          _DetectionThresholdCard(),
          const SizedBox(height: 32),
        ],
      ),
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

  const _VehicleCard({
    super.key,
    required this.data,
    required this.index,
    required this.isExpanded,
    required this.onToggle,
    required this.onSaved,
  });

  @override
  State<_VehicleCard> createState() => _VehicleCardState();
}

class _VehicleCardState extends State<_VehicleCard> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _modelCtrl;
  late final TextEditingController _plateCtrl;
  late final TextEditingController _colorCtrl;
  late final TextEditingController _geofenceCtrl;

  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    _modelCtrl    = TextEditingController(text: d['model'] ?? '');
    _plateCtrl    = TextEditingController(text: d['license_plate'] ?? '');
    _colorCtrl    = TextEditingController(text: d['color'] ?? '');
    _geofenceCtrl = TextEditingController(text: (d['geofence_radius_m'] ?? 50).toString());

    for (final c in [_modelCtrl, _plateCtrl, _colorCtrl, _geofenceCtrl]) {
      c.addListener(() => setState(() => _dirty = true));
    }
  }

  @override
  void dispose() {
    _modelCtrl.dispose();
    _plateCtrl.dispose();
    _colorCtrl.dispose();
    _geofenceCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final updated = {
      ...widget.data,
      'model': _modelCtrl.text.trim(),
      'license_plate': _plateCtrl.text.trim(),
      'color': _colorCtrl.text.trim(),
      'geofence_radius_m': int.tryParse(_geofenceCtrl.text) ?? 50,
      '_isNew': false,
    };
    setState(() => _dirty = false);
    widget.onSaved(updated);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile saved'), backgroundColor: Color(0xFF1E8A3E)),
    );
  }


  void _discard() {
    final d = widget.data;
    _modelCtrl.text    = d['model'] ?? '';
    _plateCtrl.text    = d['license_plate'] ?? '';
    _colorCtrl.text    = d['color'] ?? '';
    _geofenceCtrl.text = (d['geofence_radius_m'] ?? 50).toString();
    setState(() => _dirty = false);
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
        border: const Border(left: BorderSide(color: AppColors.primary, width: 4)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
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
                    child: const Icon(Icons.motorcycle, color: AppColors.onPrimaryContainer, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.onSurface),
                    ),
                  ),
                  if (_dirty)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(color: AppColors.secondary, shape: BoxShape.circle),
                    ),
                  const SizedBox(width: 8),
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
                    _buildImagesSection(),
                    const SizedBox(height: 20),
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

  Widget _buildImagesSection() {
    final slots = ['Front View', 'Back View', 'Left Side', 'Right Side', 'License Plate'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldHeader(icon: Icons.photo_library_outlined, title: 'Motorcycle Images'),
        const SizedBox(height: 4),
        const Text(
          'Upload clear photos of your vehicle from all angles for accurate CCTV identification.',
          style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: slots.map((label) => _PhotoTile(label: label)).toList(),
        ),
      ],
    );
  }

  Widget _buildIdentificationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldHeader(icon: Icons.badge_outlined, title: 'Identification Details'),
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
                onPressed: _dirty ? _discard : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  minimumSize: const Size.fromHeight(44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Discard Changes'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('SAVE PROFILE'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Detection Threshold Card ──────────────────────────────────────────────────

class _DetectionThresholdCard extends StatefulWidget {
  const _DetectionThresholdCard();

  @override
  State<_DetectionThresholdCard> createState() => _DetectionThresholdCardState();
}

class _DetectionThresholdCardState extends State<_DetectionThresholdCard> {
  final _ctrl = TextEditingController(text: '2');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() {
    final val = int.tryParse(_ctrl.text);
    if (val == null || val < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Minimum threshold is 1 minute'), backgroundColor: AppColors.error),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Threshold updated'), backgroundColor: Color(0xFF1E8A3E)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: const Border(left: BorderSide(color: AppColors.secondaryContainer, width: 4)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FieldHeader(icon: Icons.videocam_outlined, title: 'Detection Threshold'),
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
                child: TextFormField(
                  controller: _ctrl,
                  decoration: const InputDecoration(
                    labelText: 'Delay Time (Minutes)',
                    prefixIcon: Icon(Icons.timer_outlined),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(72, 56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionHeader({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
          ],
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant)),
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
        Text(title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
      ],
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final String label;

  const _PhotoTile({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: (MediaQuery.of(context).size.width - 64) / 3,
      height: 80,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.add_a_photo_outlined, color: AppColors.onSurfaceVariant, size: 22),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(fontSize: 10, color: AppColors.onSurfaceVariant),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
