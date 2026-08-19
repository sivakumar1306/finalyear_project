import 'package:flutter/material.dart';

class StatusBadge extends StatelessWidget {
  final bool connected;
  const StatusBadge({super.key, required this.connected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: connected ? Colors.green.shade100 : Colors.red.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: connected ? Colors.green : Colors.red, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: connected ? Colors.green : Colors.red),
          const SizedBox(width: 6),
          Text(
            connected ? 'Connected' : 'Disconnected',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: connected ? Colors.green.shade800 : Colors.red.shade800,
            ),
          ),
        ],
      ),
    );
  }
}