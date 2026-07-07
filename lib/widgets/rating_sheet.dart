import 'package:flutter/material.dart';

import '../constants/colors.dart';

/// Shared 5-star rating bottom sheet, reused by all 4 rating checkpoints
/// (sender<->rider at handoff, receiver<->rider at delivery). Skippable —
/// rating is a nice-to-have, never blocks the underlying confirm action
/// that triggers it.
Future<void> showRatingSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required Future<void> Function(int rating, String? comment) onSubmit,
}) {
  int rating = 0;
  final commentCtrl = TextEditingController();
  var submitting = false;

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: EzizaColors.kBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(title,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: EzizaColors.kText)),
            const SizedBox(height: 4),
            Text(subtitle,
                style:
                    const TextStyle(color: EzizaColors.kMuted, fontSize: 13)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final filled = i < rating;
                return GestureDetector(
                  onTap: () => setSheet(() => rating = i + 1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                        filled ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: EzizaColors.kGold,
                        size: 40),
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: commentCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Add a comment (optional)',
                hintStyle: const TextStyle(color: EzizaColors.kMuted, fontSize: 13),
                filled: true,
                fillColor: EzizaColors.kSurface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: EzizaColors.kBorder)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: EzizaColors.kBorder)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: EzizaColors.kPurple, width: 1.5)),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: TextButton(
                  onPressed: submitting ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Skip',
                      style: TextStyle(color: EzizaColors.kMuted)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: (submitting || rating == 0)
                      ? null
                      : () async {
                          setSheet(() => submitting = true);
                          try {
                            await onSubmit(
                                rating,
                                commentCtrl.text.trim().isEmpty
                                    ? null
                                    : commentCtrl.text.trim());
                          } catch (_) {}
                          if (ctx.mounted) Navigator.of(ctx).pop();
                        },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      gradient: rating == 0
                          ? null
                          : const LinearGradient(
                              colors: [EzizaColors.kPurple, EzizaColors.kPurpleD]),
                      color: rating == 0 ? EzizaColors.kBorder : null,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: submitting
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text('Submit Rating',
                              style: TextStyle(
                                  color: rating == 0
                                      ? EzizaColors.kMuted
                                      : Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14)),
                    ),
                  ),
                ),
              ),
            ]),
          ],
        ),
      );
    }),
  );
}
