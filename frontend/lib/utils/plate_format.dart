/// Formats a license plate for display with its province inserted in the
/// middle, matching how the backend formats plates in notifications
/// (see `_plate_with_province` in backend/api/main.py):
/// Used for read-only display only — the raw `license_plate` and `province`
/// fields stay separate everywhere else (editing, API payloads).
String formatPlateWithProvince(String plate, String? province) {
  final trimmedPlate = plate.trim();
  final trimmedProvince = province?.trim() ?? '';
  if (trimmedProvince.isEmpty) return trimmedPlate;

  final match = RegExp(r'^(\S+)\s+(.*)$').firstMatch(trimmedPlate);
  if (match != null && match.group(2)!.isNotEmpty) {
    return '${match.group(1)} $trimmedProvince ${match.group(2)}';
  }
  return '$trimmedPlate $trimmedProvince'.trim();
}
