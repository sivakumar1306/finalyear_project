import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/main_tab_provider.dart';
import '../../services/chat_api_service.dart';
import '../../services/incident_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_back_button.dart';
import 'voice_listening_sheet.dart';
import 'insights_header.dart';
import 'sleep_highlights_card.dart';
import 'heart_rate_chat_card.dart';
import 'blood_oxygen_chat_card.dart';
import 'hrv_chat_card.dart';
import 'blood_pressure_chat_card.dart';
import 'steps_chat_card.dart';
import 'temperature_chat_card.dart';
import 'stress_chat_card.dart';
import '../../widgets/app_typography.dart';

// Persist the active conversation id per-user so the thread survives an
// app close/reopen. Keyed by user id so switching accounts doesn't leak
// one user's conversation into another's screen.
String _conversationPrefsKey(String userId) => 'chat_conversation_id_$userId';

class ChatScreen extends StatefulWidget {
  final String? initialPrompt;
  const ChatScreen({super.key, this.initialPrompt});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<InsightsHeaderState> _insightsKey =
      GlobalKey<InsightsHeaderState>();
  final List<Map<String, dynamic>> _messages = [];
  bool _isLoading = false;
  bool _hasText = false;
  bool _isRestoring = true;
  String? _conversationId;
  String _errorMessage = '';
  int _scrollTimerId = 0;
  bool _sentInitialPrompt = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _restoreConversation();
  }

  void _onTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  // Restores the last active conversation (if any) so the chat survives an
  // app close/reopen instead of always starting blank.
  Future<void> _restoreConversation() async {
    final userId = SupabaseService.currentUser?.id;

    // Not logged in: the backend never saves history for an "anonymous"
    // user_id, so there's nothing to restore — just show the empty state.
    if (userId == null) {
      setState(() => _isRestoring = false);
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      String? conversationId = prefs.getString(_conversationPrefsKey(userId));

      if (conversationId == 'NEW_CHAT') {
        // User explicitly started a new chat; do not restore past conversations
        return;
      }

      // No cached conversation id yet on this device — fall back to the
      // most recent conversation stored on the server for this user.
      if (conversationId == null) {
        final convResult = await ChatApiService.getConversations();
        final conversations = convResult['conversations'] as List<dynamic>?;
        if (conversations != null && conversations.isNotEmpty) {
          conversationId = conversations.first['id'] as String?;
        }
      }

      if (conversationId != null) {
        final msgResult = await ChatApiService.getMessages(conversationId);
        final rawMessages = msgResult['messages'] as List<dynamic>?;
        if (rawMessages != null && rawMessages.isNotEmpty) {
          setState(() {
            _conversationId = conversationId;
            _messages.addAll(
              rawMessages.map((m) => Map<String, dynamic>.from(m as Map)),
            );
          });
          await prefs.setString(_conversationPrefsKey(userId), conversationId);
          _scrollToBottom();
        }
      }
    } catch (e, st) {
      IncidentService.reportUnhandled(
        source: 'chat_screen',
        error: e,
        stackTrace: st,
        customMessage: 'restore conversation failed',
      );
    } finally {
      if (mounted) {
        setState(() => _isRestoring = false);
        _maybeSendInitialPrompt();
      }
    }
  }

  void _maybeSendInitialPrompt() {
    final prompt = widget.initialPrompt?.trim();
    if (prompt == null || prompt.isEmpty || _sentInitialPrompt) return;
    if (_messages.isNotEmpty) {
      _controller.text = prompt;
      setState(() => _hasText = true);
      return;
    }
    _sentInitialPrompt = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sendMessage(prompt);
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Explicitly resets the shell to the Home tab before popping, so "back"
  // from AI Assist always lands on Home — regardless of which tab (Home or
  // Settings) was active before the user opened chat.
  void _goBackToHome() {
    context.read<MainTabProvider>().setTab(0);
    Navigator.of(context).pop();
  }

  Future<void> _startNewChat() async {
    if (_messages.isEmpty) return; // nothing to clear

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceDeep,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Start a new chat?',
          style: AppTypography.inter(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'This clears the current conversation from view. Your history isn\'t deleted.',
          style: AppTypography.inter(
            color: AppTheme.white60,
            fontSize: 13,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: AppTypography.inter(color: AppTheme.white60),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Start new',
              style: AppTypography.inter(
                color: AppTheme.gold,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    setState(() {
      _messages.clear();
      _conversationId = null;
      _errorMessage = '';
    });

    final userId = SupabaseService.currentUser?.id;
    if (userId != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_conversationPrefsKey(userId), 'NEW_CHAT');
    }
  }

  void _startVoiceInput() async {
    final transcript = await VoiceListeningSheet.show(context);
    if (transcript != null && transcript.isNotEmpty) {
      _sendMessage(transcript);
    }
  }

  void _sendMessage([String? suggestion]) async {
    final text = suggestion ?? _controller.text.trim();
    if (text.isEmpty || _isLoading) return;

    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _isLoading = true;
      _errorMessage = '';
    });
    _controller.clear();
    _scrollToBottom();

    try {
      // Strip user-supplied "[System Context: ...]" blocks before sending so a
      // user cannot inject their own instructions that ride alongside the
      // app-level system context below and override it on the AI backend.
      final String sanitizedText = text.replaceAll(
        RegExp(r'\[System Context:.*?\]', caseSensitive: false, dotAll: true),
        '',
      ).trim();
      String payloadText = sanitizedText;
      if (!InsightsHeaderState.hasData) {
        payloadText += '\n\n[System Context: The user currently has NO data available (0 days of readings). Do not hallucinate or invent any metrics, scores, or charts. Inform the user they need to wear their ring longer to gather data.]';
      }

      final result = await ChatApiService.chat(payloadText, _conversationId);
      setState(() {
        _messages.add({
          'role': 'assistant',
          'content': result['reply'] ?? 'No response received.',
          'card': result['card'],
        });
        _conversationId = result['conversation_id'];
        _isLoading = false;
      });

      // Remember which conversation this is so reopening the app resumes it.
      final userId = SupabaseService.currentUser?.id;
      if (userId != null && _conversationId != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_conversationPrefsKey(userId), _conversationId!);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Connection error. Check if backend is running.';
        _isLoading = false;
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    _scrollTimerId++;
    final tid = _scrollTimerId;
    Future.delayed(const Duration(milliseconds: 100), () {
      if (tid != _scrollTimerId) return;
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Pull-to-refresh handler — re-fetches the insights header's data. The
  // header itself no longer has its own refresh icon/toggle (see
  // insights_header.dart), so this gesture is now the only way to refresh it.
  Future<void> _onPullToRefresh() async {
    await _insightsKey.currentState?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final bool isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return PopScope(
      // Also catch system/gesture back (not just the visible arrow) so the
      // tab-reset stays consistent no matter how the user leaves the screen.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _goBackToHome();
      },
      child: Scaffold(
        backgroundColor: AppTheme.bg,
        appBar: null, // Removed standard AppBar to match Figma design
        resizeToAvoidBottomInset:
            true, // Allow standard resizing; we scroll the header out of the way dynamically
        body: SafeArea(
          bottom:
              false, // Let input bar handle its own bottom padding dynamically to avoid keyboard overflow
          child: Column(
            children: [
              // Back button — top-left, matches Figma. Explicitly resets the
              // shell to the Home tab (see _goBackToHome) rather than just
              // popping, so this always returns to Home.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    GlassBackButton(onTap: _goBackToHome),
                  ],
                ),
              ),

              // Error Message Banner (if any)
              if (_errorMessage.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  color: AppTheme.danger.withValues(alpha: 0.15),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: AppTheme.danger,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage,
                          style: const TextStyle(
                            color: AppTheme.danger,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _errorMessage = ''),
                        child: const Icon(
                          Icons.close,
                          color: AppTheme.danger,
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                ),

              // Messages Area / Suggestion Chips / Header
              Expanded(
                child: _isRestoring
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.gold,
                          strokeWidth: 2,
                        ),
                      )
                    : _messages.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _onPullToRefresh,
                        color: AppTheme.gold,
                        backgroundColor: AppTheme.surfaceDeep,
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          // header(1) + messages + loading(0/1) + trailing "new chat" chip(0/1)
                          itemCount:
                              _messages.length +
                              (_isLoading ? 1 : 0) +
                              1 +
                              (_messages.isNotEmpty && !_isLoading ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  InsightsHeader(key: _insightsKey),
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 18,
                                      bottom: 14,
                                    ),
                                    child: Container(
                                      height: 0.5,
                                      color: AppTheme.white10,
                                    ),
                                  ),
                                ],
                              );
                            }

                            // Adjust index because of the header at index 0
                            final int msgIndex = index - 1;

                            if (_isLoading && msgIndex == _messages.length) {
                              // Typing loading indicator (aligned left)
                              return Align(
                                alignment: Alignment.centerLeft,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        left: 6,
                                        bottom: 4,
                                      ),
                                      child: Text(
                                        'AI ASSIST',
                                        style: AppTypography.inter(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w500,
                                          letterSpacing: 0.12 * 10,
                                          color: AppTheme.white40,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      margin: const EdgeInsets.symmetric(
                                        vertical: 6,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 16,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.white04,
                                        border: Border.all(
                                          color: const Color(0x12FFFFFF),
                                          width: 1,
                                        ),
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(6),
                                          topRight: Radius.circular(28),
                                          bottomLeft: Radius.circular(18),
                                          bottomRight: Radius.circular(18),
                                        ),
                                      ),
                                      child: const _ChatLoadingIndicator(),
                                    ),
                                  ],
                                ),
                              );
                            }

                            // Trailing "New chat" chip — the very last list item, shown once a
                            // reply (and any card) has fully rendered and nothing is loading.
                            final bool showNewChatButton =
                                _messages.isNotEmpty && !_isLoading;
                            final int trailingIndex =
                                _messages.length + (_isLoading ? 1 : 0) + 1;
                            if (showNewChatButton && index == trailingIndex) {
                              return Padding(
                                padding: const EdgeInsets.only(
                                  top: 20,
                                  bottom: 8,
                                ),
                                child: Center(
                                  child: GestureDetector(
                                    onTap: _startNewChat,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 9,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.white04,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: AppTheme.glassButtonBorder,
                                          width: 0.5,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.add_comment_outlined,
                                            size: 14,
                                            color: AppTheme.gold,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'New chat',
                                            style: AppTypography.inter(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                              color: const Color(0xCCFFFFFF),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }

                            final msg = _messages[msgIndex];
                            final isUser = msg['role'] == 'user';

                          if (isUser) {
                            return _buildUserBubble(
                              context,
                              msg['content'] ?? '',
                            );
                          } else {
                            final String content = msg['content'] ?? '';
                            final card = msg['card'];
                            
                            // Guard against hallucinated cards when there's actually no data,
                            // rather than relying on unreliable string matching of the LLM's text.
                            final bool hasNoData = !InsightsHeaderState.hasData;
                            
                            final cardWidget =
                                (card != null && !hasNoData) ? _buildChatCard(context, card) : null;
                            return Align(
                              alignment: Alignment.centerLeft,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (content.isNotEmpty)
                                    _buildAssistantBubble(context, content),
                                  if (cardWidget != null) ...[
                                    const SizedBox(height: 8),
                                    // Cache the blurred card layer so scrolling
                                    // doesn't re-blur the backdrop each frame.
                                    RepaintBoundary(
                                      child: cardWidget,
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }
                        },
                        ),
                      ),
              ),

              // Input Bar
              _buildInputBar(isKeyboardOpen),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return RefreshIndicator(
      onRefresh: _onPullToRefresh,
      color: AppTheme.gold,
      backgroundColor: AppTheme.surfaceDeep,
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          InsightsHeader(key: _insightsKey),
          Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 14),
            child: Container(
              height: 0.5,
              color: AppTheme.white10, // rgba(255,255,255,0.1)
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Color(0x14C9A86E), // rgba(201,168,110,0.08)
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.smart_toy_rounded,
                  size: 48,
                  color: AppTheme.gold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'AI Assist',
                style: AppTypography.inter(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Ask me anything about your health',
                style: AppTypography.inter(
                  color: AppTheme.white52, // rgba(255,255,255,0.52)
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              for (final question in (InsightsHeaderState.suggestedQuestions ?? [
                'How does my sleep look this week?',
                'I have a headache',
                'What vitamins should I take?',
              ])) ...[
                _SuggestionChip(
                  text: question,
                  onTap: _sendMessage,
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUserBubble(BuildContext context, String content) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        constraints: BoxConstraints(
          maxWidth: math.min(MediaQuery.of(context).size.width * 0.78, 274.7),
        ),
        decoration: BoxDecoration(
          color: const Color(0x1FC9A86E), // rgba(201,168,110,0.12)
          border: Border.all(
            color: const Color(0x40C9A86E), // rgba(201,168,110,0.25)
            width: 1,
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(6),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(18),
          ),
        ),
        child: Text(
          content,
          style: AppTypography.inter(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            height: 1.50,
            letterSpacing: -0.005 * 13,
            color: AppTheme.white96, // rgba(255,255,255,0.96)
          ),
        ),
      ),
    );
  }

  Widget? _buildChatCard(BuildContext context, Map<String, dynamic> card) {
    final type = card['type'];
    final data = card['data'];
    if (data == null) return null;

    switch (type) {
      case 'sleep_highlights':
        return SleepHighlightsCard(
          data: data,
          onTap: () => Navigator.pushNamed(context, '/sleep'),
        );
      case 'heart_rate_trend':
        return HeartRateChatCard(
          data: data,
          onTap: () => Navigator.pushNamed(context, '/heart-rate'),
        );
      case 'spo2_trend':
        return BloodOxygenChatCard(
          data: data,
          onTap: () => Navigator.pushNamed(context, '/blood-oxygen'),
        );
      case 'hrv_trend':
        return HrvChatCard(
          data: data,
          onTap: () => Navigator.pushNamed(context, '/hrv'),
        );
      case 'bp_trend':
        return BloodPressureChatCard(
          data: data,
          onTap: () => Navigator.pushNamed(context, '/blood-pressure'),
        );
      case 'steps_trend':
        return StepsChatCard(
          data: data,
          onTap: () => Navigator.pushNamed(context, '/steps'),
        );
      case 'temperature_trend':
        return TemperatureChatCard(
          data: data,
          onTap: () => Navigator.pushNamed(context, '/temperature'),
        );
      case 'stress_trend':
        return StressChatCard(
          data: data,
          onTap: () => Navigator.pushNamed(context, '/pressure'),
        );
      default:
        return null;
    }
  }

  Widget _buildAssistantBubble(BuildContext context, String content) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 4),
            child: Text(
              'AI ASSIST',
              style: AppTypography.inter(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.12 * 10,
                color: AppTheme.white40, // rgba(255,255,255,0.4)
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            constraints: BoxConstraints(
              maxWidth: math.min(
                MediaQuery.of(context).size.width * 0.78,
                274.7,
              ),
            ),
            decoration: BoxDecoration(
              color: AppTheme.white04, // rgba(255,255,255,0.04)
              border: Border.all(
                color: const Color(0x12FFFFFF), // rgba(255,255,255,0.07)
                width: 1,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(28),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
            ),
            child: Text(
              content,
              style: AppTypography.inter(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                height: 1.50,
                letterSpacing: -0.005 * 13,
                color: AppTheme.white96, // rgba(255,255,255,0.96)
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(bool isKeyboardOpen) {
    // Send button only appears once the user has typed something; otherwise
    // the pill fills the row with just the mic icon, matching the Figma spec.
    final bool showSend = _hasText;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: EdgeInsets.fromLTRB(12, 16, 12, isKeyboardOpen ? 12 : 24),
          decoration: const BoxDecoration(
            color: Color(0x8C050505), // rgba(5,5,5,0.55)
            border: Border(
              top: BorderSide(
                color: AppTheme.gridLine, // rgba(255,255,255,0.05)
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.fromLTRB(18, 8, 14, 8),
                  decoration: BoxDecoration(
                    color: AppTheme.gridLine, // rgba(255,255,255,0.05)
                    border: Border.all(
                      color: AppTheme.white10, // rgba(255,255,255,0.1)
                      width: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          onSubmitted: (_) => _sendMessage(),
                          enabled: !_isLoading,
                          style: AppTypography.inter(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Ask about your health ...',
                            hintStyle: AppTypography.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              letterSpacing: -0.005 * 13,
                              color: const Color(
                                0x6BFFFFFF,
                              ), // rgba(255,255,255,0.42)
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _isLoading ? null : _startVoiceInput,
                        child: const Icon(
                          Icons.mic_none_rounded,
                          color: AppTheme.gold,
                          size: 28,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Animated show/hide of the send button based on whether text is present.
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                child: showSend
                    ? Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: GestureDetector(
                          onTap: _isLoading ? null : _sendMessage,
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: _isLoading
                                  ? Colors.transparent
                                  : AppTheme.gold,
                              shape: BoxShape.circle,
                              border: _isLoading
                                  ? Border.all(
                                      color: AppTheme.white10,
                                      width: 0.5,
                                    )
                                  : null,
                            ),
                            child: Center(
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: AppTheme.gold,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.send,
                                      color: Colors.black,
                                      size: 20,
                                    ),
                            ),
                          ),
                        ),
                      )
                    : const SizedBox(width: 0, height: 52),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String text;
  final Function(String) onTap;
  const _SuggestionChip({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(text),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.white04, // rgba(255,255,255,0.03)
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppTheme.glassButtonBorder, // rgba(255,255,255,0.08)
            width: 0.5,
          ),
        ),
        child: Text(
          text,
          style: AppTypography.inter(
            color: AppTheme.white52, // rgba(255,255,255,0.52)
            fontSize: 13,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _ChatLoadingIndicator extends StatefulWidget {
  const _ChatLoadingIndicator();

  @override
  State<_ChatLoadingIndicator> createState() => _ChatLoadingIndicatorState();
}

class _ChatLoadingIndicatorState extends State<_ChatLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildDot(0),
        const SizedBox(width: 12),
        _buildDot(1),
        const SizedBox(width: 12),
        _buildDot(2),
      ],
    );
  }

  Widget _buildDot(int index) {
    final double size = index == 1 ? 12.0 : 8.0;
    final Color color = index == 1
        ? AppTheme.gold
        : const Color(0xB2C9A86E); // rgba(201,168,110,0.7)

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final double delay = index * 0.3;
        final double t = (_controller.value - delay) % 1.0;
        final double opacity = 0.3 + 0.7 * math.sin(t * math.pi);
        return Opacity(
          opacity: opacity.clamp(0.2, 1.0),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        );
      },
    );
  }
}
