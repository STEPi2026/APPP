import 'package:flutter/material.dart';

import '../models/learning_next_action.dart';

class LearningNextActionNotice extends StatelessWidget {
  final LearningNextAction action;
  final VoidCallback? onAction;
  const LearningNextActionNotice({
    super.key,
    required this.action,
    this.onAction,
  });
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xFFF3EEFF),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE6DFFF)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          action.title,
          style: const TextStyle(
            color: Color(0xFF7C5CFA),
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 8),
        Text(action.message, style: const TextStyle(height: 1.6, fontSize: 13)),
        if (onAction != null) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onAction,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF7C5CFA),
            ),
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: Text(action.title),
          ),
        ],
      ],
    ),
  );
}
