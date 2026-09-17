import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/coach_source.dart';

/// Renders the citations for one Coach answer, in the exact order the
/// backend returned them. The model's inline "[Source N]" labels refer to
/// that order, so this widget must never sort, filter, dedupe, or re-rank --
/// index i here is always "[Source i+1]".
class CoachCitations extends StatelessWidget {
  const CoachCitations({super.key, required this.sources, required this.grounded});

  final List<CoachSource> sources;
  final bool grounded;

  @override
  Widget build(BuildContext context) {
    if (sources.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < sources.length; i++)
              _CitationTile(index: i + 1, source: sources[i]),
          ],
        ),
      );
    }

    // grounded:false with no sources is a legitimate, honest answer (a
    // general-knowledge question the retrieval gate correctly found nothing
    // to cite for) -- not a failure, so it gets a plain informational line,
    // never an empty "citations" box or a "no sources found" warning look.
    if (!grounded) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(
          'General knowledge — no specific code citation for this answer.',
          style: TextStyle(
            fontSize: 11,
            fontStyle: FontStyle.italic,
            color: AppTheme.textSecondary,
          ),
        ),
      );
    }

    // grounded:true with no sources never happens from a live Coach call --
    // this is the welcome banner / demo reply path. Nothing to show.
    return const SizedBox.shrink();
  }
}

class _CitationTile extends StatelessWidget {
  const _CitationTile({required this.index, required this.source});

  final int index;
  final CoachSource source;

  @override
  Widget build(BuildContext context) {
    final heading = source.title ?? source.document ?? source.source;
    final fields = <String>[
      if (source.issuingAuthority != null) 'Issuing authority: ${source.issuingAuthority}',
      if (source.edition != null) 'Edition: ${source.edition}',
      if (source.revision != null) 'Revision: ${source.revision}',
      if (source.jurisdictions != null)
        'Jurisdiction(s): ${source.jurisdictions!.join(', ')}',
      if (source.scope != null) 'Scope: ${source.scope}',
      if (source.page != null) 'Page: ${source.page}',
      if (source.locator != null) 'Locator: ${source.locator}',
      if (source.ref != null) 'Ref: ${source.ref}',
    ];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.navy.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.separator),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            heading != null ? '[Source $index] $heading' : '[Source $index]',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.textSecondary,
            ),
          ),
          for (final field in fields)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                field,
                style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}
