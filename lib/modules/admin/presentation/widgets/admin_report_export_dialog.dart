import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/providers/app_providers.dart';
import '../../../../core/network/models/api_result.dart';
import '../../../auth/data/models/user_model.dart';
import '../../services/admin_report_service.dart';

class AdminReportExportDialog extends ConsumerStatefulWidget {
  const AdminReportExportDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const AdminReportExportDialog(),
    );
  }

  @override
  ConsumerState<AdminReportExportDialog> createState() => _AdminReportExportDialogState();
}

class _AdminReportExportDialogState extends ConsumerState<AdminReportExportDialog> {
  DateTime? _startDate;
  DateTime? _endDate;
  UserModel? _selectedUser;
  List<UserModel> _users = [];
  bool _isLoadingUsers = true;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final api = ref.read(usersApiProvider);
      final res = await api.listUsers();
      if (res case ApiSuccess(:final data)) {
        setState(() {
          _users = data;
          _users.sort((a, b) => a.name.compareTo(b.name));
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

  Future<void> _export() async {
    setState(() => _isExporting = true);
    try {
      final travelApi = ref.read(travelApiProvider);
      final service = AdminReportService(travelApi: travelApi);
      await service.exportReport(
        startDate: _startDate,
        endDate: _endDate,
        userId: _selectedUser?.uid,
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report downloaded successfully.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export report: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('MMM dd, yyyy');

    return AlertDialog(
      title: const Text('Export Report'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Date Range', style: TextStyle(fontWeight: FontWeight.bold)),
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
            const Text('User', style: TextStyle(fontWeight: FontWeight.bold)),
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
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isExporting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isExporting ? null : _export,
          child: _isExporting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Download Excel'),
        ),
      ],
    );
  }
}
