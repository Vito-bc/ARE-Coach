import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/quiz_question.dart';
import '../services/report_repository.dart';

Future<void> showFlagQuestionSheet(
  BuildContext context, {
  required QuizQuestion question,
  required bool firebaseReady,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _FlagSheet(question: question, firebaseReady: firebaseReady),
  );
}

class _FlagSheet extends StatefulWidget {
  const _FlagSheet({required this.question, required this.firebaseReady});
  final QuizQuestion question;
  final bool firebaseReady;

  @override
  State<_FlagSheet> createState() => _FlagSheetState();
}

class _FlagSheetState extends State<_FlagSheet> {
  FlagReason? _selected;
  final _commentController = TextEditingController();
  bool _submitting = false;
  bool _submitted = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selected == null || _submitting) return;

    if (!widget.firebaseReady) {
      setState(() => _submitted = true);
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _submitted = true);
      return;
    }

    setState(() => _submitting = true);
    try {
      await ReportRepository().flagQuestion(
        uid: uid,
        questionId: widget.question.id,
        questionText: widget.question.question,
        reason: _selected!,
        comment: _commentController.text,
      );
      if (mounted) setState(() => _submitted = true);
    } catch (_) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to submit report. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF161B22),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: _submitted ? _SuccessView() : _FormView(
          selected: _selected,
          commentController: _commentController,
          submitting: _submitting,
          onReasonSelected: (r) => setState(() => _selected = r),
          onSubmit: _submit,
        ),
      ),
    );
  }
}

class _FormView extends StatelessWidget {
  const _FormView({
    required this.selected,
    required this.commentController,
    required this.submitting,
    required this.onReasonSelected,
    required this.onSubmit,
  });

  final FlagReason? selected;
  final TextEditingController commentController;
  final bool submitting;
  final ValueChanged<FlagReason> onReasonSelected;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.separator,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Flag this question',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Help us improve the question bank.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 16),
        ...FlagReason.values.map((reason) => _ReasonTile(
              reason: reason,
              selected: selected == reason,
              onTap: () => onReasonSelected(reason),
            )),
        const SizedBox(height: 12),
        TextField(
          controller: commentController,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Additional comments (optional)',
            hintStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            filled: true,
            fillColor: AppTheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.separator),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.separator, width: 0.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.yellow, width: 1),
            ),
            contentPadding: const EdgeInsets.all(12),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: selected == null || submitting ? null : onSubmit,
            child: Text(submitting ? 'Submitting...' : 'Submit Report'),
          ),
        ),
      ],
    );
  }
}

class _ReasonTile extends StatelessWidget {
  const _ReasonTile({
    required this.reason,
    required this.selected,
    required this.onTap,
  });

  final FlagReason reason;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppTheme.yellow.withValues(alpha: 0.1) : AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppTheme.yellow : AppTheme.separator,
            width: selected ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              size: 18,
              color: selected ? AppTheme.yellow : AppTheme.textSecondary,
            ),
            const SizedBox(width: 10),
            Text(
              reason.label,
              style: TextStyle(
                color: selected ? AppTheme.textPrimary : AppTheme.textSecondary,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 24),
        const Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 48),
        const SizedBox(height: 12),
        const Text(
          'Report submitted',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Thanks for helping improve the question bank.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
