import 'package:flutter/material.dart';

import '../core/ui/app_chrome.dart';
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
      text:
          'Ask any ARE question. I will answer with formula, code reference, and exam traps.',
      time: DateTime.now(),
    ),
  ];

  bool _loading = false;
  bool _voiceReady = false;
  bool _listening = false;

  static const _demoPrompt = 'I do not understand egress capacity for 300 people in a hall.';
  static const _demoReply = '''
Formula:
Required stair egress width = occupant load x 0.2 in/person
300 x 0.2 = 60 inches

Code reference:
IBC 2021 Section 1005.3.1 (verify NYC amendments).

Exam value:
Usually tested as a 10-15 point competency item.

Common mistakes:
1) Using 0.15 instead of 0.2 for stair calculations.
2) Ignoring minimum clear width requirements.
''';

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

    final response = await _coachService.askCoach(prompt);
    if (!mounted) return;

    setState(() {
      _messages.add(ChatMessage(
        role: ChatRole.coach,
        text: response,
        time: DateTime.now(),
      ));
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      child: Stack(
        children: [
          const Positioned.fill(child: AppBackdrop()),
          Column(
            children: [
              ListTile(
                title: const Text(
                  'AI Coach',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
                subtitle: const Text('Premium: voice + interview simulation'),
                trailing: IconButton(
                  onPressed: _speakLastCoachMessage,
                  icon: const Icon(Icons.volume_up_outlined),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    const Chip(label: Text('Demo mode')),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _runDemoScenario,
                      child: const Text('Run demo'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: _messages.length,
                  itemBuilder: (_, index) {
                    final msg = _messages[index];
                    final isUser = msg.role == ChatRole.user;
                    return Align(
                      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 320),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isUser
                              ? Theme.of(context).colorScheme.primary
                              : (isDark
                                  ? Colors.white.withValues(alpha: 0.12)
                                  : Colors.white.withValues(alpha: 0.96)),
                          border: Border.all(
                            color: isUser
                                ? Colors.transparent
                                : (isDark
                                    ? Colors.white.withValues(alpha: 0.16)
                                    : const Color(0xFFE5E7EB)),
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              msg.text,
                              style: TextStyle(
                                color: isUser ? Colors.white : Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            if (!isUser) ...[
                              const SizedBox(height: 6),
                              Text(
                                'AI-generated. Verify with official NCARB materials.',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.35)
                                      : const Color(0xFF9CA3AF),
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
              if (_loading) const LinearProgressIndicator(minHeight: 2),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: AppGlassCard(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: _toggleListening,
                          icon: Icon(_listening ? Icons.mic_off : Icons.mic),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            minLines: 1,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              hintText: 'Explain fire separation...',
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _sendMessage,
                          icon: const Icon(Icons.send_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
