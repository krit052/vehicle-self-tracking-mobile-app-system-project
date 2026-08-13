import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/notification_bell.dart';
import 'login_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const _baseUrl = 'http://localhost:8001';

  List<_AlertItem> _alerts = [];
  bool _loading = true;
  String? _error;

  // ── Calendar state ──
  final _stripController = ScrollController();
  DateTime _focusedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selectedDate;
  bool _yearView = false;
  bool _calendarExpanded = false; // ย่อ (แถบวัน) เป็นค่าเริ่มต้นเพื่อประหยัดพื้นที่
  bool _showAll = false; // true = แสดงแจ้งเตือนทุกวัน, false = เฉพาะวันที่เลือก

  // ── Selection (multi-delete) state ──
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _fetchNotifications();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_calendarExpanded) _scrollStripToDay(DateTime.now().day, animate: false);
    });
  }

  @override
  void dispose() {
    _stripController.dispose();
    super.dispose();
  }

  Dio get _dio {
    final token = UserSession.instance.token;
    return Dio(BaseOptions(
      baseUrl: _baseUrl,
      headers: token != null ? {'Authorization': 'Bearer $token'} : {},
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ));
  }

  Future<void> _fetchNotifications() async {
    if (UserSession.instance.token == null) {
      setState(() {
        _loading = false;
        _error = 'Not logged in.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _dio.get('/notifications');
      final data = (res.data as List).cast<Map<String, dynamic>>();
      setState(() {
        _alerts = data.map(_AlertItem.fromJson).toList();
        _loading = false;
      });
      _syncUnreadBadge();
    } on DioException catch (e) {
      setState(() {
        _loading = false;
        _error = e.response?.data?['detail']?.toString() ??
            'Could not load notifications.';
      });
    }
  }

  Future<void> _markRead(String id, int index) async {
    try {
      await _dio.patch('/notifications/$id/read');
      setState(() {
        _alerts[index] = _alerts[index].copyWithRead(true);
      });
      _syncUnreadBadge();
    } catch (_) {}
  }

  /// อัปเดตจำนวน unread เข้า NotificationCenter (แหล่งเดียว) → กระดิ่งทุกหน้าตรงกัน
  void _syncUnreadBadge() {
    NotificationCenter.instance.setUnread(
      _alerts.where((a) => !a.read).length,
    );
  }

  // ── Delete ──────────────────────────────────────────────────────────────────

  void _enterSelection(String id) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(id);
    });
  }

  void _toggleSelected(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      if (_selectedIds.isEmpty) _selectionMode = false;
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _deleteIds(List<String> ids) async {
    for (final id in ids) {
      try {
        await _dio.delete('/notifications/$id');
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _alerts.removeWhere((a) => ids.contains(a.id));
      _selectedIds.clear();
      _selectionMode = false;
    });
    _syncUnreadBadge();
  }

  Future<void> _confirmDeleteSelected() async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;
    final ok = await _confirmDialog(
      title: 'Delete Notifications',
      message: 'Delete ${ids.length} selected notification'
          '${ids.length == 1 ? '' : 's'}? This cannot be undone.',
    );
    if (ok == true) await _deleteIds(ids);
  }

  Future<void> _confirmDeleteAll() async {
    if (_alerts.isEmpty) return;
    final ok = await _confirmDialog(
      title: 'Delete All',
      message: 'Delete all notifications? This cannot be undone.',
    );
    if (ok != true) return;
    try {
      await _dio.delete('/notifications');
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _alerts.clear();
      _selectedIds.clear();
      _selectionMode = false;
    });
    _syncUnreadBadge();
  }

  Future<bool?> _confirmDialog({
    required String title,
    required String message,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ── Calendar helpers ──────────────────────────────────────────────────────────

  List<_AlertItem> get _filteredAlerts {
    if (_showAll || _selectedDate == null) return _alerts;
    return _alerts.where((a) {
      final d = a.createdAt;
      return d.year == _selectedDate!.year &&
          d.month == _selectedDate!.month &&
          d.day == _selectedDate!.day;
    }).toList();
  }

  /// วันที่ควรเลือกในเดือนที่โฟกัส: ถ้าเป็นเดือนปัจจุบันใช้วันนี้ ไม่งั้นใช้วันที่ 1
  DateTime _defaultDayInFocusedMonth() {
    final now = DateTime.now();
    final isCurrentMonth =
        _focusedMonth.year == now.year && _focusedMonth.month == now.month;
    return DateTime(
      _focusedMonth.year,
      _focusedMonth.month,
      isCurrentMonth ? now.day : 1,
    );
  }

  /// เลื่อน 1 ช่วง: โหมดปี = เปลี่ยนปี, โหมดเดือน = เปลี่ยนเดือน (ข้ามปีให้อัตโนมัติ)
  void _stepPeriod(int dir) {
    setState(() {
      _focusedMonth = _yearView
          ? DateTime(_focusedMonth.year + dir, _focusedMonth.month)
          : DateTime(_focusedMonth.year, _focusedMonth.month + dir);
      _selectedDate = _defaultDayInFocusedMonth();
      _showAll = false;
    });
    if (!_calendarExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollStripToDay(_selectedDate!.day, animate: false);
      });
    }
  }

  void _scrollStripToDay(int day, {bool animate = true}) {
    if (!_stripController.hasClients) return;
    const itemWidth = 48.0;
    final viewport = _stripController.position.viewportDimension;
    final offset = ((day - 1) * itemWidth) - (viewport / 2) + (itemWidth / 2);
    final clamped = offset.clamp(
      _stripController.position.minScrollExtent,
      _stripController.position.maxScrollExtent,
    );
    animate
        ? _stripController.animateTo(clamped,
            duration: const Duration(milliseconds: 300), curve: Curves.easeInOut)
        : _stripController.jumpTo(clamped);
  }

  void _toggleExpanded() {
    setState(() {
      _calendarExpanded = !_calendarExpanded;
      if (!_calendarExpanded) _yearView = false;
    });
    if (!_calendarExpanded) {
      final now = DateTime.now();
      final target = (_selectedDate != null &&
              _selectedDate!.year == _focusedMonth.year &&
              _selectedDate!.month == _focusedMonth.month)
          ? _selectedDate!.day
          : (_focusedMonth.year == now.year && _focusedMonth.month == now.month
              ? now.day
              : 1);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollStripToDay(target, animate: false);
      });
    }
  }

  bool _hasAlertsOn(int year, int month, [int? day]) {
    return _alerts.any((a) {
      final d = a.createdAt;
      return d.year == year &&
          d.month == month &&
          (day == null || d.day == day);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildCalendar(),
          if (!_loading && _error == null) _buildFilterBar(),
          Expanded(child: _buildBody()),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    if (_selectionMode) {
      return AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _exitSelection,
          tooltip: 'Cancel',
        ),
        title: Text(
          '${_selectedIds.length} selected',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _selectedIds.isEmpty ? null : _confirmDeleteSelected,
            tooltip: 'Delete selected',
          ),
        ],
      );
    }

    final userName = UserSession.instance.user?['name'] as String?;
    return AppBar(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.onPrimary,
      centerTitle: false,
      leading: Padding(
        padding: const EdgeInsets.all(10),
        child: CircleAvatar(
          backgroundColor: AppColors.primaryContainer,
          child: Text(
            userName != null && userName.isNotEmpty
                ? userName[0].toUpperCase()
                : '?',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.onPrimary,
            ),
          ),
        ),
      ),
      title: const Text(
        'MFU TRACKER',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      ),
      actions: [
        if (_alerts.isNotEmpty) ...[
          IconButton(
            icon: const Icon(Icons.checklist),
            tooltip: 'Select',
            onPressed: () => setState(() => _selectionMode = true),
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Delete all',
            onPressed: _confirmDeleteAll,
          ),
        ],
      ],
    );
  }

  Widget _buildCalendar() {
    final headerLabel = _yearView
        ? '${_focusedMonth.year}'
        : '${_monthName(_focusedMonth.month)} ${_focusedMonth.year}';

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => _stepPeriod(-1),
                icon: const Icon(Icons.chevron_left,
                    color: AppColors.onSurfaceVariant),
                tooltip: _yearView ? 'Previous year' : 'Previous month',
              ),
              // แตะหัวข้อ: ย่ออยู่ = ขยาย, ขยายอยู่ = สลับมุมมองเดือน ↔ ทั้งปี
              Expanded(
                child: Center(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      if (!_calendarExpanded) {
                        _toggleExpanded();
                      } else {
                        setState(() => _yearView = !_yearView);
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            headerLabel,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onSurface,
                            ),
                          ),
                          if (_calendarExpanded) ...[
                            const SizedBox(width: 4),
                            Icon(
                              _yearView
                                  ? Icons.arrow_drop_up
                                  : Icons.arrow_drop_down,
                              size: 20,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _stepPeriod(1),
                icon: const Icon(Icons.chevron_right,
                    color: AppColors.onSurfaceVariant),
                tooltip: _yearView ? 'Next year' : 'Next month',
              ),
              IconButton(
                onPressed: _toggleExpanded,
                icon: Icon(
                  _calendarExpanded ? Icons.unfold_less : Icons.unfold_more,
                  color: AppColors.onSurfaceVariant,
                ),
                tooltip: _calendarExpanded ? 'Collapse' : 'Expand',
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (!_calendarExpanded)
            _buildDayStrip()
          else
            _yearView ? _buildYearGrid() : _buildMonthGrid(),
        ],
      ),
    );
  }

  /// แถบวันเลื่อนแนวนอน (มุมมองย่อ) — เหมือนเวอร์ชันก่อน
  Widget _buildDayStrip() {
    final year = _focusedMonth.year;
    final month = _focusedMonth.month;
    final daysInMonth = DateUtils.getDaysInMonth(year, month);
    final now = DateTime.now();

    return SizedBox(
      height: 66,
      child: ListView.builder(
        controller: _stripController,
        scrollDirection: Axis.horizontal,
        itemCount: daysInMonth,
        itemExtent: 48,
        itemBuilder: (context, i) {
          final day = i + 1;
          final date = DateTime(year, month, day);
          final isSelected = _selectedDate?.year == year &&
              _selectedDate?.month == month &&
              _selectedDate?.day == day;
          final isToday =
              now.year == year && now.month == month && now.day == day;
          final hasAlerts = _hasAlertsOn(year, month, day);

          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedDate = date;
                _showAll = false;
              });
              _scrollStripToDay(day);
            },
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _dayLetter(date.weekday),
                  style: TextStyle(
                    fontSize: 11,
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : Colors.transparent,
                    shape: BoxShape.circle,
                    border: isToday && !isSelected
                        ? Border.all(color: AppColors.primary, width: 1.5)
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$day',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : AppColors.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: hasAlerts
                        ? (isSelected
                            ? Colors.white
                            : AppColors.secondaryContainer)
                        : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMonthGrid() {
    final year = _focusedMonth.year;
    final month = _focusedMonth.month;
    final daysInMonth = DateUtils.getDaysInMonth(year, month);
    // ช่องว่างนำหน้า: เริ่มสัปดาห์วันอาทิตย์ (Sun=0 … Sat=6)
    final leading = DateTime(year, month, 1).weekday % 7;
    final rows = ((leading + daysInMonth) / 7).ceil();
    const weekdays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    return Column(
      children: [
        Row(
          children: [
            for (int c = 0; c < 7; c++)
              Expanded(
                child: Center(
                  child: Text(
                    weekdays[c],
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: c == 0
                          ? AppColors.error
                          : AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (int r = 0; r < rows; r++)
          Row(
            children: [
              for (int c = 0; c < 7; c++)
                Expanded(child: _buildDayCell(r * 7 + c, leading, daysInMonth)),
            ],
          ),
      ],
    );
  }

  Widget _buildDayCell(int cellIndex, int leading, int daysInMonth) {
    final day = cellIndex - leading + 1;
    if (day < 1 || day > daysInMonth) {
      return const SizedBox(height: 42);
    }
    final year = _focusedMonth.year;
    final month = _focusedMonth.month;
    final date = DateTime(year, month, day);
    final now = DateTime.now();
    final isSelected = _selectedDate?.year == year &&
        _selectedDate?.month == month &&
        _selectedDate?.day == day;
    final isToday =
        now.year == year && now.month == month && now.day == day;
    final hasAlerts = _hasAlertsOn(year, month, day);

    return GestureDetector(
      onTap: () => setState(() {
        _selectedDate = date;
        _showAll = false;
      }),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 42,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : Colors.transparent,
                shape: BoxShape.circle,
                border: isToday && !isSelected
                    ? Border.all(color: AppColors.primary, width: 1.5)
                    : null,
              ),
              alignment: Alignment.center,
              child: Text(
                '$day',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : AppColors.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: hasAlerts
                    ? (isSelected
                        ? AppColors.primary
                        : AppColors.secondaryContainer)
                    : Colors.transparent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildYearGrid() {
    final now = DateTime.now();
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      childAspectRatio: 1.7,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      children: [
        for (int m = 1; m <= 12; m++)
          _buildMonthTile(m, now),
      ],
    );
  }

  Widget _buildMonthTile(int month, DateTime now) {
    final year = _focusedMonth.year;
    final isCurrentMonth = now.year == year && now.month == month;
    final isSelectedMonth = _focusedMonth.month == month;
    final hasAlerts = _hasAlertsOn(year, month);

    return GestureDetector(
      onTap: () => setState(() {
        _focusedMonth = DateTime(year, month);
        _yearView = false;
        _showAll = false;
        _selectedDate = _defaultDayInFocusedMonth();
      }),
      child: Container(
        decoration: BoxDecoration(
          color: isSelectedMonth
              ? AppColors.primary
              : AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(10),
          border: isCurrentMonth && !isSelectedMonth
              ? Border.all(color: AppColors.primary, width: 1.5)
              : null,
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _monthAbbr(month),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isSelectedMonth ? Colors.white : AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: hasAlerts
                    ? (isSelectedMonth
                        ? Colors.white
                        : AppColors.secondaryContainer)
                    : Colors.transparent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// แถบบอกตัวกรองปัจจุบัน + ปุ่มสลับดูทั้งหมด/เฉพาะวัน
  Widget _buildFilterBar() {
    final label = _showAll
        ? 'All notifications'
        : (_selectedDate != null
            ? '${_selectedDate!.day} ${_monthName(_selectedDate!.month)} ${_selectedDate!.year}'
            : 'All notifications');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(
        children: [
          Icon(
            _showAll ? Icons.notifications_active_outlined : Icons.event_outlined,
            size: 16,
            color: AppColors.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton.icon(
            onPressed: () => setState(() {
              _showAll = !_showAll;
              if (!_showAll && _selectedDate == null) {
                _selectedDate = _defaultDayInFocusedMonth();
              }
            }),
            icon: Icon(_showAll ? Icons.event : Icons.list_alt, size: 18),
            label: Text(_showAll ? 'By day' : 'View all'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return _buildLoading();
    if (_error != null) return _buildError();
    final filtered = _filteredAlerts;
    if (filtered.isEmpty) return _buildEmpty();
    return _buildList(filtered);
  }

  Widget _buildLoading() {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.primary),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, size: 40, color: AppColors.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            _error!,
            style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: _fetchNotifications,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<_AlertItem> alerts) {
    return RefreshIndicator(
      onRefresh: _fetchNotifications,
      color: AppColors.primary,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        itemCount: alerts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final alert = alerts[i];
          final index = _alerts.indexWhere((a) => a.id == alert.id);
          return _AlertCard(
            alert: alert,
            selectionMode: _selectionMode,
            selected: _selectedIds.contains(alert.id),
            onTap: _selectionMode
                ? () => _toggleSelected(alert.id)
                : (alert.read ? null : () => _markRead(alert.id, index)),
            onLongPress:
                _selectionMode ? null : () => _enterSelection(alert.id),
          );
        },
      ),
    );
  }

  Widget _buildEmpty() {
    final label = _showAll || _selectedDate == null
        ? 'any day'
        : '${_selectedDate!.day} ${_monthName(_selectedDate!.month)} ${_selectedDate!.year}';
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(36),
            ),
            child: const Icon(
              Icons.notifications_none,
              size: 36,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No notifications',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Nothing on $label',
            style: const TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return NavigationBar(
      selectedIndex: 0,
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      destinations: const [
        NavigationDestination(icon: Icon(Icons.map_outlined), label: 'Map'),
        NavigationDestination(
          icon: Icon(Icons.motorcycle_sharp),
          label: 'Vehicle',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          label: 'Profile',
        ),
      ],
      onDestinationSelected: (_) => Navigator.of(context).pop(),
    );
  }

  String _monthName(int month) => const [
    '',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ][month];

  String _monthAbbr(int month) => const [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][month];

  String _dayLetter(int weekday) =>
      const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][weekday - 1];
}

// ── Alert Card ────────────────────────────────────────────────────────────────

class _AlertCard extends StatelessWidget {
  final _AlertItem alert;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selectionMode;
  final bool selected;

  const _AlertCard({
    required this.alert,
    this.onTap,
    this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedOpacity(
        opacity: alert.read && !selectionMode ? 0.6 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primaryContainer.withValues(alpha: 0.15)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border(
              left: BorderSide(color: _typeColor(alert.alertType), width: 4),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 5,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (selectionMode) ...[
                  Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 22,
                    color: selected
                        ? AppColors.primary
                        : AppColors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                ] else ...[
                  _AlertIcon(type: alert.alertType),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _typeTitle(alert.alertType),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _typeColor(alert.alertType),
                              ),
                            ),
                          ),
                          if (!alert.read && !selectionMode)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _typeColor(alert.alertType),
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _bodyText(alert.alertType),
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.onSurface,
                          height: 1.4,
                        ),
                      ),
                      if (alert.licensePlate.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(
                              Icons.pin_outlined,
                              size: 12,
                              color: AppColors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                alert.cameraName.isNotEmpty
                                    ? '${alert.licensePlate}  ·  ${alert.cameraName}'
                                    : alert.licensePlate,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.access_time,
                            size: 12,
                            color: AppColors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatTime(alert.createdAt),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _typeColor(String type) => switch (type) {
    'MOVED' => const Color(0xFFE65100),
    'LOST' => AppColors.error,
    'UNAUTHORIZED_MOVE' => AppColors.error,
    'PLATE_DETECTED' => AppColors.blue,
    _ => AppColors.onSurfaceVariant,
  };

  String _typeTitle(String type) => switch (type) {
    'MOVED' => 'Vehicle Moved',
    'LOST' => 'Vehicle Lost',
    'UNAUTHORIZED_MOVE' => 'Is This You?',
    'PLATE_DETECTED' => 'License Plate Detected',
    _ => 'Vehicle Alert',
  };

  String _bodyText(String type) => switch (type) {
    'MOVED' => 'Your vehicle has moved outside its geofence radius.',
    'LOST' => 'Your vehicle has disappeared from camera view.',
    'UNAUTHORIZED_MOVE' =>
      'Your vehicle left its zone without being unlocked. Confirm this was you.',
    'PLATE_DETECTED' =>
      'Your vehicle was detected by a campus CCTV camera.',
    _ => 'An alert was triggered for your vehicle.',
  };

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _AlertIcon extends StatelessWidget {
  final String type;
  const _AlertIcon({required this.type});

  @override
  Widget build(BuildContext context) {
    final (icon, bg, fg) = switch (type) {
      'MOVED' => (
        Icons.warning_amber_rounded,
        const Color(0xFFFFF3E0),
        const Color(0xFFE65100),
      ),
      'LOST' => (
        Icons.visibility_off_outlined,
        const Color(0xFFFFEDED),
        AppColors.error,
      ),
      'UNAUTHORIZED_MOVE' => (
        Icons.no_encryption_gmailerrorred_outlined,
        const Color(0xFFFFEDED),
        AppColors.error,
      ),
      'PLATE_DETECTED' => (
        Icons.pin_outlined,
        const Color(0xFFE3F2FD),
        AppColors.blue,
      ),
      _ => (
        Icons.notifications_outlined,
        AppColors.surfaceContainer,
        AppColors.onSurfaceVariant,
      ),
    };
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 20, color: fg),
    );
  }
}

// ── Data Model ────────────────────────────────────────────────────────────────

class _AlertItem {
  final String id;
  final String alertType;
  final String snapshotUrl;
  final DateTime createdAt;
  final bool read;
  final String licensePlate;
  final String cameraName;

  const _AlertItem({
    required this.id,
    required this.alertType,
    required this.snapshotUrl,
    required this.createdAt,
    required this.read,
    this.licensePlate = '',
    this.cameraName = '',
  });

  factory _AlertItem.fromJson(Map<String, dynamic> json) => _AlertItem(
    id: json['id'] as String,
    alertType: json['alert_type'] as String? ?? 'INFO',
    snapshotUrl: json['snapshot_url'] as String? ?? '',
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    read: json['read'] as bool? ?? false,
    licensePlate: json['license_plate'] as String? ?? '',
    cameraName: json['camera_name'] as String? ?? '',
  );

  _AlertItem copyWithRead(bool read) => _AlertItem(
    id: id,
    alertType: alertType,
    snapshotUrl: snapshotUrl,
    createdAt: createdAt,
    read: read,
    licensePlate: licensePlate,
    cameraName: cameraName,
  );
}
