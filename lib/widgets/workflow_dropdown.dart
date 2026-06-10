import 'package:flutter/material.dart';
import '../config/theme.dart';
import '../config/constants.dart';

class WorkflowDropdown extends StatefulWidget {
  final String currentStatus;
  final ValueChanged<String> onChanged;

  const WorkflowDropdown({
    super.key,
    required this.currentStatus,
    required this.onChanged,
  });

  @override
  State<WorkflowDropdown> createState() => _WorkflowDropdownState();
}

class _WorkflowDropdownState extends State<WorkflowDropdown> {
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _statusIcon(widget.currentStatus),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Current: ${AppConstants.statusLabel(widget.currentStatus)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Change status:',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.primaryGrey,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              hint: Text(AppConstants.statusLabel(widget.currentStatus)),
              items: AppConstants.jobStatuses
                  .where((s) => AppConstants.jobStatuses.indexOf(s) > AppConstants.jobStatuses.indexOf(widget.currentStatus))
                  .map((step) {
                return DropdownMenuItem(
                  value: step,
                  child: Row(
                    children: [
                      _statusIcon(step),
                      const SizedBox(width: 8),
                      Text(AppConstants.statusLabel(step)),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  widget.onChanged(value);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusIcon(String status) {
    IconData icon;
    Color color;

    switch (status) {
      case 'accepted':
        icon = Icons.check_circle;
        color = Colors.blue;
        break;
      case 'on_route':
        icon = Icons.directions_car;
        color = Colors.orange;
        break;
      case 'on_site':
        icon = Icons.build;
        color = Colors.purple;
        break;
      case 'completed':
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      default:
        icon = Icons.help;
        color = Colors.grey;
    }

    return Icon(icon, color: color, size: 24);
  }
}