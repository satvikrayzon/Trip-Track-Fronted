import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/network/models/api_result.dart';
import '../../../auth/data/datasources/users_remote_datasource.dart';
import '../../../auth/data/models/user_model.dart';
import '../controllers/admin_travel_requests_controller.dart';

class AdminRequestsFilterSheet extends StatefulWidget {
  final AdminTravelRequestsController controller;

  const AdminRequestsFilterSheet({super.key, required this.controller});

  static Future<void> show(BuildContext context, AdminTravelRequestsController controller) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (context) => Theme(
        data: ThemeData.light().copyWith(
          scaffoldBackgroundColor: Colors.white,
          canvasColor: Colors.white,
          bottomSheetTheme: const BottomSheetThemeData(
            backgroundColor: Colors.white,
          ),
        ),
        child: AdminRequestsFilterSheet(controller: controller),
      ),
    );
  }

  @override
  State<AdminRequestsFilterSheet> createState() => _AdminRequestsFilterSheetState();
}

class _AdminRequestsFilterSheetState extends State<AdminRequestsFilterSheet> {
  DateTime? _startDate;
  DateTime? _endDate;
  UserModel? _selectedUser;
  List<UserModel> _users = [];
  bool _isLoadingUsers = true;

  @override
  void initState() {
    super.initState();
    _startDate = widget.controller.startDate.value;
    _endDate = widget.controller.endDate.value;
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final api = ServiceLocator.I.get<UsersRemoteDataSource>();
      final res = await api.listUsers();
      if (res case ApiSuccess(:final data)) {
        setState(() {
          _users = data;
          _users.sort((a, b) => a.name.compareTo(b.name));
          
          if (widget.controller.selectedUserId.value != null) {
            _selectedUser = _users.where((u) => u.uid == widget.controller.selectedUserId.value).firstOrNull;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _isLoadingUsers = false);
    }
  }

  Future<void> _pickDate(bool isStart) async {
    final initial = isStart ? _startDate : _endDate;
    final first = DateTime(2020);
    final last = DateTime.now().add(const Duration(days: 365));

    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: first,
      lastDate: last,
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate != null && _endDate!.isBefore(picked)) {
            _endDate = picked;
          }
        } else {
          _endDate = picked;
          if (_startDate != null && _startDate!.isAfter(picked)) {
            _startDate = picked;
          }
        }
      });
    }
  }

  void _setQuickFilter(String type) {
    final now = DateTime.now();
    setState(() {
      if (type == 'this_month') {
        _startDate = DateTime(now.year, now.month, 1);
        _endDate = DateTime(now.year, now.month + 1, 0);
      } else if (type == 'last_month') {
        _startDate = DateTime(now.year, now.month - 1, 1);
        _endDate = DateTime(now.year, now.month, 0);
      } else if (type == 'all') {
        _startDate = null;
        _endDate = null;
      }
    });
  }

  void _applyFilters() {
    widget.controller.setDateRange(_startDate, _endDate);
    widget.controller.setSelectedUser(_selectedUser?.uid);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('MMM dd, yyyy');

    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Advanced Filters', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Date Range', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickDate(true),
                  child: Text(_startDate != null ? df.format(_startDate!) : 'Start Date'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickDate(false),
                  child: Text(_endDate != null ? df.format(_endDate!) : 'End Date'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ActionChip(
                label: const Text('This Month'),
                onPressed: () => _setQuickFilter('this_month'),
              ),
              ActionChip(
                label: const Text('Last Month'),
                onPressed: () => _setQuickFilter('last_month'),
              ),
              ActionChip(
                label: const Text('All Time'),
                onPressed: () => _setQuickFilter('all'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('User', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
          const SizedBox(height: 8),
          if (_isLoadingUsers)
            const Center(child: CircularProgressIndicator())
          else
            DropdownButtonFormField<UserModel?>(
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12),
              ),
              style: const TextStyle(
                color: Color(0xFF1F2937),
                fontSize: 14,
              ),
              value: _selectedUser,
              hint: const Text(
                'All Users',
                style: TextStyle(color: Color(0xFF9CA3AF)),
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text(
                    'All Users',
                    style: TextStyle(color: Color(0xFF1F2937)),
                  ),
                ),
                ..._users.map(
                  (u) => DropdownMenuItem(
                    value: u,
                    child: Text(
                      '${u.name} (${u.employeeCode ?? "-"})',
                      style: const TextStyle(color: Color(0xFF1F2937)),
                    ),
                  ),
                ),
              ],
              onChanged: (val) {
                setState(() => _selectedUser = val);
              },
            ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  _setQuickFilter('all');
                  setState(() => _selectedUser = null);
                },
                child: const Text('Reset'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _applyFilters,
                child: const Text('Apply Filters'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
