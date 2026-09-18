import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Matches the real `launchUrl` top-level function's shape closely enough
/// that it can be passed directly as the default; tests inject a fake
/// instead of exercising the real platform plugin (which has no host
/// implementation in `flutter test` and must never be invoked there).
typedef UrlLauncher = Future<bool> Function(Uri url, {LaunchMode mode});

/// The Terms of Service / Privacy Policy assent checkbox shown directly
/// above the primary action button at every account-creation entry point
/// (register, Apple sign-in, guest). Never pre-ticked -- a pre-ticked box is
/// not assent, so [value] must default to false at every call site.
class TermsAssentCheckbox extends StatelessWidget {
  const TermsAssentCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    @visibleForTesting UrlLauncher? launcher,
  }) : _launcher = launcher;

  final bool value;
  final ValueChanged<bool> onChanged;
  final UrlLauncher? _launcher;

  static const termsUrl =
      'https://vito-bc.github.io/ARE-Coach/terms-and-conditions.html';
  static const privacyUrl =
      'https://vito-bc.github.io/ARE-Coach/privacy-policy.html';

  Future<void> _openLink(BuildContext context, String url) async {
    final launch = _launcher ?? launchUrl;
    var opened = false;
    try {
      opened = await launch(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    // A link that silently does nothing is worse than no link: the user
    // cannot read what they are agreeing to and has no idea why.
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the link. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle =
        Theme.of(context).textTheme.bodySmall ?? const TextStyle(fontSize: 13);
    final linkStyle = baseStyle.copyWith(
      decoration: TextDecoration.underline,
      fontWeight: FontWeight.w600,
      color: Theme.of(context).colorScheme.primary,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: value,
          onChanged: (v) => onChanged(v ?? false),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 13),
            child: Wrap(
              children: [
                Text('I have read and agree to the ', style: baseStyle),
                GestureDetector(
                  onTap: () => _openLink(context, termsUrl),
                  child: Text('Terms of Service', style: linkStyle),
                ),
                Text(' and ', style: baseStyle),
                GestureDetector(
                  onTap: () => _openLink(context, privacyUrl),
                  child: Text('Privacy Policy', style: linkStyle),
                ),
                Text('.', style: baseStyle),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
