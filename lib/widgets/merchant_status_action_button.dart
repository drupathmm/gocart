import 'package:flutter/material.dart';

class MerchantStatusActionButton extends StatelessWidget {
  final String status;
  final VoidCallback? onPressed;
  final VoidCallback? onReject;

  const MerchantStatusActionButton({
    super.key,
    required this.status,
    required this.onPressed,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final isPending = status == 'pending';
    final isSuspended = status == 'suspended';
    final isApproved = status == 'approved';
    final isRejected = status == 'rejected';
    final isKnown = isPending || isSuspended || isApproved;
    final label = isPending
        ? 'Approve'
        : isSuspended
        ? 'Review requests'
        : isApproved
        ? 'Suspend'
        : isRejected
        ? 'Rejected'
        : 'Status unavailable';

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.tonal(
          onPressed: isKnown ? onPressed : null,
          style: FilledButton.styleFrom(
            foregroundColor: isPending || isSuspended
                ? const Color(0xFF541B3D)
                : Colors.red.shade700,
          ),
          child: Text(label),
        ),
        if (isPending)
          TextButton(onPressed: onReject, child: const Text('Reject')),
      ],
    );
  }
}
