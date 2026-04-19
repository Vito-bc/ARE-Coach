import 'package:flutter/material.dart';

import '../core/result.dart';
import '../core/theme/app_theme.dart';
import '../models/chat_message.dart';
import '../services/coach_service.dart';
import '../services/voice_service.dart';

class CoachScreen extends StatefulWidget {
  const CoachScreen({super.key});

  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends State<CoachScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _coachService = CoachService();
  final _voiceService = VoiceService();
  final List<ChatMessage> _messages = [
    ChatMessage(
      role: ChatRole.coach,
      text: CoachService.isLive
          ? 'Ask any ARE question — I\'ll answer with formulas, code references, and exam traps.'
          : 'Demo mode: responses use a local fallback. Set COACH_API_URL at build time to enable live AI.',
      time: DateTime.now(),
    ),
  ];

  bool _loading = false;
  bool _voiceReady = false;
  bool _listening = false;

  static const _demoPrompt =
      'I do not understand egress capacity for 300 people in a hall.';
  static const _demoReply = '''Formula:
Required stair egress width = occupant load × 0.2 in/person
300 × 0.2 = 60 inches

Code reference:
IBC 2021 Section 1005.3.1 (verify NYC amendments).

Exam value:
Usually tested as a 10–15 point competency item.

Common mistakes:
1) Using 0.15 instead of 0.2 for stair calculations.
2) Ignoring minimum clear width requirements.''';

  @override
  void initState() {
    super.initState();
    _bootstrapVoice();
  }

  Future<void> _bootstrapVoice() async {
    final ready = await _voiceService.init();
    if (!mounted) return;
    setState(() => _voiceReady = ready);
  }

  Future<void> _sendMessage() async {
    final prompt = _controller.text.trim();
    if (prompt.isEmpty || _loading) return;

    setState(() {
      _loading = true;
      _messages.add(ChatMessage(
        role: ChatRole.user,
        text: prompt,
        time: DateTime.now(),
      ));
      _controller.clear();
    });
    _scrollToBottom();

    final result = await _coachService.askCoach(prompt);
    if (!mounted) return;

    final (text, role) = switch (result) {
      Ok(:final value) => (value, ChatRole.coach),
      Err(:final message) => (message, ChatRole.error),
    };

    setState(() {
      _messages.add(ChatMessage(role: role, text: text, time: DateTime.now()));
      _loading = false;
    });
    _scrollToBottom();
  }

  Future<void> _toggleListening() async {
    if (!_voiceReady) return;
    if (_listening) {
      await _voiceService.stopListening();
      if (!mounted) return;
      setState(() => _listening = false);
      return;
    }
    setState(() => _listening = true);
    await _voiceService.listen(
      onResult: (words) {
        if (!mounted) return;
        setState(() => _controller.text = words);
      },
    );
  }

  Future<void> _speakLastCoachMessage() async {
    final coachMessages = _messages.where((m) => m.role == ChatRole.coach);
    if (coachMessages.isEmpty) return;
    await _voiceService.speak(coachMessages.last.text);
  }

  void _runDemoScenario() {
    if (_loading) return;
    setState(() {
      _messages.add(ChatMessage(
        role: ChatRole.user,
        text: _demoPrompt,
        time: DateTime.now(),
      ));
      _messages.add(ChatMessage(
        role: ChatRole.coach,
        text: _demoReply,
        time: DateTime.now(),
      ));
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _coachService.dispose();
    _voiceService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.navy,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AI Coach',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                            letterSpacing: -1,
                          ),
                        ),
                        Text(
                          CoachService.isLive
                              ? 'Live — voice + interview simulation'
                              : 'Demo mode — set COACH_API_URL to enable AI',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // speak last coach message
                  IconButton(
                    onPressed: _speakLastCoachMessage,
                    icon: const Icon(Icons.volume_up_outlined),
                    color: AppTheme.textSecondary,
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.surface,
                    ),
                  ),
                ],
              ),
            ),

            // ── Demo banner (only shown when not live) ─────────────────
            if (!CoachService.isLive)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppTheme.warning.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: AppTheme.warning,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Using local fallback answers',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.warning,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _runDemoScenario,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          foregroundColor: AppTheme.warning,
                        ),
                        child: const Text(
                          'Run demo',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // ── Messages ───────────────────────────────────────────────
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                itemCount: _messages.length,
                itemBuilder: (_, index) {
                  final msg = _messages[index];
                  final isUser = msg.role == ChatRole.user;
                  final isError = msg.role == ChatRole.error;
                  return Align(
                    alignment:
                        isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.80,
                      ),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isUser
                            ? AppTheme.yellow.withValues(alpha: 0.15)
                            : isError
                                ? AppTheme.error.withValues(alpha: 0.10)
                                : AppTheme.surface,
                        border: Border.all(
                          color: isUser
                              ? AppTheme.yellow.withValues(alpha: 0.4)
                              : isError
                                  ? AppTheme.error.withValues(alpha: 0.4)
                                  : AppTheme.separator,
                          width: 1,
                        ),
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: Radius.circular(isUser ? 16 : 4),
                          bottomRight: Radius.circular(isUser ? 4 : 16),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            msg.text,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color: isUser
                                  ? AppTheme.yellow
                                  : isError
                                      ? AppTheme.error
                                      : AppTheme.textPrimary,
                            ),
                          ),
                          if (msg.role == ChatRole.coach) ...[
                            const SizedBox(height: 6),
                            const Text(
                              'AI-generated — verify with official NCARB materials.',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            if (_loading)
              const LinearProgressIndicator(
                minHeight: 2,
                color: AppTheme.yellow,
                backgroundColor: AppTheme.surface,
              ),

            // ── Input bar ──────────────────────────────────────────────
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.separator),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: _voiceReady ? _toggleListening : null,
                    icon: Icon(
                      _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                    ),
                    color: _listening ? AppTheme.yellow : AppTheme.textSecondary,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Ask about egress, fire ratings, ADA…',
                        hintStyle: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  IconButton(
                    onPressed: _loading ? null : _sendMessage,
                    icon: const Icon(Icons.send_rounded),
                    color: _loading ? AppTheme.textSecondary : AppTheme.yellow,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
