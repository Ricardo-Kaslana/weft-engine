import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:weft/weft.dart';

import 'live_document.dart';
import 'live_tag_renderers.dart';

void main() {
  runApp(const WeftLiveApp());
}

class WeftLiveApp extends StatefulWidget {
  const WeftLiveApp({super.key, this.enableLiveUpdates = true});

  /// Widget tests disable the timer so the fake clock can settle.
  final bool enableLiveUpdates;

  @override
  State<WeftLiveApp> createState() => _WeftLiveAppState();
}

class _WeftLiveAppState extends State<WeftLiveApp> {
  bool _dark = false;

  @override
  void initState() {
    super.initState();
    _dark = Uri.base.queryParameters['theme'] == 'dark';
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Weft Live',
      debugShowCheckedModeBanner: false,
      theme: _theme(LivePalette.light),
      darkTheme: _theme(LivePalette.dark),
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      home: WeftLivePage(
        isDark: _dark,
        enableLiveUpdates: widget.enableLiveUpdates,
        onToggleTheme: () => setState(() => _dark = !_dark),
      ),
    );
  }

  ThemeData _theme(LivePalette palette) {
    final brightness = palette.isDark ? Brightness.dark : Brightness.light;
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
    );
    final scheme = ColorScheme.fromSeed(
      seedColor: palette.accent,
      brightness: brightness,
    ).copyWith(
      primary: palette.accent,
      secondary: palette.teal,
      surface: palette.surface,
      onSurface: palette.ink,
      outline: palette.line,
    );
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.page,
      canvasColor: palette.page,
      dividerColor: palette.line,
      iconTheme: IconThemeData(color: palette.ink),
      textTheme: base.textTheme.apply(
        bodyColor: palette.ink,
        displayColor: palette.ink,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: palette.hero,
        contentTextStyle: TextStyle(color: palette.heroInk, fontSize: 13),
        actionTextColor: palette.lime,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
}

class WeftLivePage extends StatefulWidget {
  const WeftLivePage({
    super.key,
    required this.isDark,
    required this.onToggleTheme,
    this.enableLiveUpdates = true,
  });

  final bool isDark;
  final VoidCallback onToggleTheme;
  final bool enableLiveUpdates;

  @override
  State<WeftLivePage> createState() => _WeftLivePageState();
}

class _WeftLivePageState extends State<WeftLivePage> {
  static const _normalizer = WeftNormalizer(customTags: liveCustomTags);
  static const _pageId = 'weft-live-page';
  static const _sections = <_SectionTarget>[
    _SectionTarget(id: 'stream', label: '直播流'),
    _SectionTarget(id: 'signal', label: '数据'),
    _SectionTarget(id: 'agenda', label: '议程'),
    _SectionTarget(id: 'echo', label: '回声'),
  ];

  final _random = math.Random(26);
  final _viewKey = GlobalKey<WeftViewState>();
  final _progress = ValueNotifier<double>(0);
  late final WeftController _controller;
  late final ScrollController _scrollController;
  Timer? _timer;

  var _filter = LiveFilter.all;
  var _live = true;
  var _revision = 0;
  var _tick = 0;
  var _incomingCursor = 0;
  var _stageIndex = 1;
  var _viewers = 12480;
  var _interactions = 38240;
  var _questions = 216;
  var _claps = 1284;
  var _clockSeconds = 10 * 3600 + 42 * 60 + 6;
  late String _updatedAt;
  var _updates = List<LiveUpdate>.of(_initialUpdates);
  var _pollOptions = <PollOption>[
    const PollOption(id: 'layout', label: '让长文按场景重排', votes: 468),
    const PollOption(id: 'data', label: '让数据拥有叙事', votes: 392),
    const PollOption(id: 'pace', label: '让读者控制节奏', votes: 257),
  ];
  String? _votedOption;
  String? _voteNote;
  var _pulse = _seedPulse();
  var _anchors = <String, NodeId>{};
  var _tagActions = <NodeId, _TagAction>{};

  LivePalette get _palette =>
      widget.isDark ? LivePalette.dark : LivePalette.light;

  @override
  void initState() {
    super.initState();
    _updatedAt = _formatClock(_clockSeconds);
    _controller = WeftController();
    _scrollController = ScrollController()..addListener(_syncProgress);
    _rebuildDocument();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyDeepLink();
      });
    });
    if (widget.enableLiveUpdates) {
      _timer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _advanceLive(),
      );
    }
  }

  @override
  void didUpdateWidget(WeftLivePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isDark != widget.isDark) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _rebuildDocument();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController
      ..removeListener(_syncProgress)
      ..dispose();
    _controller.dispose();
    _progress.dispose();
    super.dispose();
  }

  void _advanceLive() {
    if (!_live || !mounted) return;
    setState(() {
      _tick += 1;
      _clockSeconds += 2;
      _updatedAt = _formatClock(_clockSeconds);
      final viewerDelta = _random.nextInt(210) - 60;
      _viewers = (_viewers + viewerDelta).clamp(9000, 99999).toInt();
      _interactions += 12 + _random.nextInt(84);
      if (_tick % 5 == 0) _questions += 1;
      final next = (_pulse.last + (_random.nextDouble() - 0.42) * 0.18)
          .clamp(0.12, 0.98)
          .toDouble();
      _pulse = <double>[..._pulse.skip(1), next];
      if (_tick % 10 == 0 && _stageIndex < liveAgenda.length - 1) {
        _stageIndex += 1;
      }
      if (_tick % 6 == 0) _addIncomingUpdate();
    });
    _rebuildDocument();
  }

  void _addIncomingUpdate() {
    final template =
        _incomingUpdates[_incomingCursor % _incomingUpdates.length];
    _incomingCursor += 1;
    _updates = <LiveUpdate>[
      LiveUpdate(
        time: _formatClock(_clockSeconds).substring(0, 5),
        topic: template.topic,
        title: template.title,
        body: template.body,
        quote: template.quote,
        fresh: true,
      ),
      for (final update in _updates) update.withFresh(false),
    ];
    if (_updates.length > 7) {
      _updates = _updates.sublist(0, 7);
    }
  }

  void _rebuildDocument() {
    final snapshot = _normalizer.normalize(
      buildLiveDocument(_model()),
      id: _pageId,
      revision: ++_revision,
    );
    _anchors = _collectAnchors(snapshot.body);
    _tagActions = _collectTagActions(snapshot.body);
    _controller.loadDocument(snapshot);
    _scheduleProgressSync();
  }

  LivePageModel _model() {
    return LivePageModel(
      palette: _palette,
      filter: _filter,
      updates: _updates,
      stageIndex: _stageIndex,
      pollOptions: _pollOptions,
      votedOption: _votedOption,
      isLive: _live,
      viewers: _viewers,
      interactions: _interactions,
      questions: _questions,
      claps: _claps,
      pulse: _pulse,
      phase: (_tick + _claps) % 16,
      updatedAt: _updatedAt,
      voteNote: _voteNote,
    );
  }

  void _syncProgress() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final max = position.maxScrollExtent;
    _progress.value =
        max <= 0 ? 0 : (position.pixels / max).clamp(0.0, 1.0).toDouble();
  }

  void _scheduleProgressSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncProgress();
    });
  }

  void _setFilter(LiveFilter filter) {
    if (_filter == filter) return;
    setState(() => _filter = filter);
    _rebuildDocument();
  }

  void _toggleLive() {
    setState(() => _live = !_live);
    _rebuildDocument();
  }

  void _vote(String optionId) {
    final current = _pollOptions.where((option) => option.id == optionId).first;
    if (_votedOption == optionId) {
      setState(() {
        _voteNote = '你已经投过「${current.label}」，结果保持不变。';
      });
      _rebuildDocument();
      return;
    }
    setState(() {
      _pollOptions = <PollOption>[
        for (final option in _pollOptions)
          if (option.id == optionId)
            option.withVotes(option.votes + 1)
          else if (option.id == _votedOption)
            option.withVotes(math.max(0, option.votes - 1))
          else
            option,
      ];
      _votedOption = optionId;
      _voteNote = '已记录你的选择：${current.label}。结果条已经重算。';
    });
    _rebuildDocument();
  }

  void _clap() {
    setState(() {
      _claps += 1;
      _tick += 1;
    });
    _rebuildDocument();
  }

  void _handleTagTap(WeftTagRegion region) {
    final action = _tagActions[region.nodeId];
    if (action == null) return;
    switch (action.kind) {
      case _TagActionKind.vote:
        final option = action.value;
        if (option != null) _vote(option);
      case _TagActionKind.clap:
        _clap();
    }
  }

  void _handleLink(WeftLinkRegion link) {
    final uri = Uri.tryParse(link.href);
    if (uri != null && uri.scheme == 'weft') {
      switch (uri.host) {
        case 'section':
          if (uri.pathSegments.isNotEmpty) {
            unawaited(_goToSection(uri.pathSegments.first));
          }
          return;
        case 'top':
          unawaited(_goTop());
          return;
        case 'about':
          _showAbout();
          return;
      }
      return;
    }
    _showMessage('演示已拦截外链：${link.href}');
  }

  Future<void> _goToSection(String id) async {
    final nodeId = _anchors[id];
    final view = _viewKey.currentState;
    if (nodeId != null && view != null) {
      final resolved = await view.scrollToNodeAsync(nodeId, alignment: 0.02);
      if (resolved) return;
    }
    if (!mounted || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    final fraction = switch (id) {
      'signal' => 0.2,
      'stream' => 0.36,
      'agenda' => 0.64,
      'poll' => 0.8,
      'echo' => 0.88,
      _ => 0.0,
    };
    await _scrollController.animateTo(
      (position.maxScrollExtent * fraction)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble(),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _goTop() async {
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  void _applyDeepLink() {
    final queryTarget = Uri.base.queryParameters['section'];
    final target = queryTarget?.replaceFirst('/', '') ??
        Uri.base.fragment.replaceFirst('/', '');
    if (target.isEmpty || !_anchors.containsKey(target)) return;
    unawaited(_goToSection(target));
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showAbout() {
    final palette = _palette;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.surface,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '关于 Weft Live',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  '这是一张由 Weft 原生渲染的实时专题页。HTML 快照、'
                  '自定义图表、投票与滚动都发生在同一张渲染表面上。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: palette.muted,
                        height: 1.6,
                      ),
                ),
                const SizedBox(height: 18),
                const _AboutRow(
                  label: '渲染',
                  value: '单个 RenderWeftSurface，无 WebView、无 DOM',
                ),
                const _AboutRow(
                  label: '动态',
                  value: '宿主重建受控 HTML 快照，Weft 复用未变内容',
                ),
                const _AboutRow(
                  label: '扩展',
                  value: '自定义标签负责主视觉、数据脉冲、投票与鼓掌',
                ),
                const _AboutRow(
                  label: '边界',
                  value: '演示数据为虚构；外链与导航均由宿主决策',
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('知道了'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Map<String, NodeId> _collectAnchors(WeftElement? body) {
    final anchors = <String, NodeId>{};
    void visit(WeftNode node) {
      if (node is! WeftElement) return;
      final htmlId = node.idAttribute;
      if (htmlId != null) anchors[htmlId] = node.id;
      for (final child in node.children) {
        visit(child);
      }
    }

    if (body != null) visit(body);
    return anchors;
  }

  Map<NodeId, _TagAction> _collectTagActions(WeftElement? body) {
    final actions = <NodeId, _TagAction>{};
    void visit(WeftNode node) {
      if (node is! WeftElement) return;
      if (liveCustomTags.contains(node.tag)) {
        final action = node.attribute('data-action');
        if (action == 'vote') {
          final value = node.attribute('data-value');
          if (value != null) {
            actions[node.id] = _TagAction(_TagActionKind.vote, value);
          }
        } else if (action == 'clap') {
          actions[node.id] = const _TagAction(_TagActionKind.clap, null);
        }
      }
      for (final child in node.children) {
        visit(child);
      }
    }

    if (body != null) visit(body);
    return actions;
  }

  @override
  Widget build(BuildContext context) {
    final palette = _palette;
    final wide = MediaQuery.sizeOf(context).width >= 820;
    return Scaffold(
      backgroundColor: palette.page,
      body: SafeArea(
        child: Column(
          children: [
            _header(context, palette, wide),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = math.min(constraints.maxWidth, 980.0);
                  return Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: width,
                      height: constraints.maxHeight,
                      child: Scrollbar(
                        controller: _scrollController,
                        thumbVisibility: wide,
                        thickness: 6,
                        radius: const Radius.circular(3),
                        child: WeftView(
                          key: _viewKey,
                          controller: _controller,
                          scrollController: _scrollController,
                          tagRenderers: liveTagRenderers,
                          onTagTap: _handleTagTap,
                          onLinkTap: _handleLink,
                          lazyOverscan: 280,
                          fallbackBuilder: (context, report) {
                            return _FallbackCard(report: report);
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(
    BuildContext context,
    LivePalette palette,
    bool wide,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.page,
        border: Border(bottom: BorderSide(color: palette.line)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 64,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: wide ? 30 : 16),
              child: Row(
                children: [
                  _Wordmark(palette: palette),
                  const SizedBox(width: 10),
                  _LiveBadge(live: _live, palette: palette),
                  if (wide) ...[
                    const SizedBox(width: 42),
                    for (final section in _sections)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: TextButton(
                          key: ValueKey<String>('nav-${section.id}'),
                          onPressed: () => unawaited(_goToSection(section.id)),
                          style: TextButton.styleFrom(
                            foregroundColor: palette.muted,
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                          child: Text(section.label),
                        ),
                      ),
                  ],
                  const Spacer(),
                  IconButton(
                    key: const ValueKey<String>('live-toggle'),
                    tooltip: _live ? '暂停直播' : '继续直播',
                    onPressed: _toggleLive,
                    icon: Icon(
                      _live
                          ? Icons.pause_circle_outline
                          : Icons.play_circle_outline,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey<String>('theme-toggle'),
                    tooltip: widget.isDark ? '切换浅色' : '切换深色',
                    onPressed: widget.onToggleTheme,
                    icon: Icon(
                      widget.isDark
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey<String>('about'),
                    tooltip: '关于这个页面',
                    onPressed: _showAbout,
                    icon: const Icon(Icons.info_outline),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 46,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: wide ? 30 : 16),
              child: Row(
                children: [
                  if (wide)
                    Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: Text(
                        'CHANNEL',
                        style: TextStyle(
                          color: palette.muted,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final filter in LiveFilter.values)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _FilterChipButton(
                                key: ValueKey<String>(
                                  'filter-${filter.name}',
                                ),
                                label: filter.label,
                                selected: _filter == filter,
                                palette: palette,
                                onTap: () => _setFilter(filter),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (wide)
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Text(
                        '${_live ? 'LIVE' : 'PAUSED'}  $_updatedAt',
                        style: TextStyle(
                          color: _live ? palette.teal : palette.muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          ValueListenableBuilder<double>(
            valueListenable: _progress,
            builder: (context, value, _) {
              return LinearProgressIndicator(
                value: value,
                minHeight: 2,
                backgroundColor: palette.line.withValues(alpha: 0.45),
                valueColor: AlwaysStoppedAnimation<Color>(palette.accent),
              );
            },
          ),
        ],
      ),
    );
  }

  String _formatClock(int totalSeconds) {
    final hours = (totalSeconds ~/ 3600) % 24;
    final minutes = (totalSeconds ~/ 60) % 60;
    final seconds = totalSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  static List<double> _seedPulse() {
    return List<double>.generate(48, (index) {
      final wave = (math.sin(index * 0.42) + 1) / 2;
      final detail = (math.sin(index * 1.73) + 1) / 2;
      return (0.18 + wave * 0.58 + detail * 0.1).clamp(0.1, 0.96).toDouble();
    }, growable: false);
  }
}

class _SectionTarget {
  const _SectionTarget({required this.id, required this.label});

  final String id;
  final String label;
}

enum _TagActionKind { vote, clap }

class _TagAction {
  const _TagAction(this.kind, this.value);

  final _TagActionKind kind;
  final String? value;
}

class _IncomingUpdate {
  const _IncomingUpdate({
    required this.topic,
    required this.title,
    required this.body,
    this.quote,
  });

  final LiveTopic topic;
  final String title;
  final String body;
  final String? quote;
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.palette});

  final LivePalette palette;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'WEFT',
            style: TextStyle(
              color: palette.ink,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.6,
            ),
          ),
          TextSpan(
            text: '.',
            style: TextStyle(
              color: palette.accent,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    super.key,
    required this.label,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final LivePalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? palette.accentWash : Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(color: selected ? palette.accent : palette.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? palette.accent : palette.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.live, required this.palette});

  final bool live;
  final LivePalette palette;

  @override
  Widget build(BuildContext context) {
    final color = live ? palette.accent : palette.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            live ? 'LIVE' : 'PAUSED',
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).brightness == Brightness.dark
        ? LivePalette.dark
        : LivePalette.light;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: TextStyle(
                color: palette.accent,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: palette.ink,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FallbackCard extends StatelessWidget {
  const _FallbackCard({required this.report});

  final SupportReport report;

  @override
  Widget build(BuildContext context) {
    final message =
        report.issues.isEmpty ? '内容触发了回退策略。' : report.issues.first.message;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text('Weft 无法渲染当前快照：$message'),
      ),
    );
  }
}

const _initialUpdates = <LiveUpdate>[
  LiveUpdate(
    time: '10:42',
    topic: LiveTopic.keynote,
    title: '主舞台：内容开始自己呼吸',
    body: '开场演示把同一篇长文放进三种阅读场景：通勤、桌面与投屏。'
        '版心、行高和图像比例在快照之间平滑切换，而选区仍然停留在原来的句子。',
    quote: '「我们不是让页面变轻，而是让内容更有弹性。」',
    fresh: true,
  ),
  LiveUpdate(
    time: '10:37',
    topic: LiveTopic.lab,
    title: '实验 01：一篇稿件，七种呼吸',
    body: '现场把 12,000 个文本节点分发到同一张渲染表面。'
        '未变化的顶层块保留绘制命令，只有新到达的段落参与布局。',
  ),
  LiveUpdate(
    time: '10:31',
    topic: LiveTopic.qa,
    title: '观众提问：动态刷新会打断阅读吗？',
    body: '不会。滚动位置由宿主持有，文本选区基于逻辑锚点重建；'
        '暂停直播后，眼前的内容会冻结成一个可以慢慢阅读的文档。',
  ),
  LiveUpdate(
    time: '10:24',
    topic: LiveTopic.keynote,
    title: '把 60fps 留给内容，而不是重建页面',
    body: '同一张表面意味着命中、选区、语义与绘制共享一次布局结果。'
        '页面没有成百上千个 Widget，只有一条可被裁剪的块流。',
  ),
  LiveUpdate(
    time: '10:16',
    topic: LiveTopic.lab,
    title: '实验 00：零 Widget 的首屏',
    body: '渐进式布局只物化可见的顶层块。滚出窗口的文本绘制资源会释放，'
        '重新进入时再从保守区间索引物化。',
  ),
];

const _incomingUpdates = <_IncomingUpdate>[
  _IncomingUpdate(
    topic: LiveTopic.lab,
    title: '实验 03：同一帧里的两次重排',
    body: '讲者把窗口宽度从 980px 拖到 420px，快照、选区与阅读位置同时迁移。'
        '现场大屏上的折线没有中断。',
  ),
  _IncomingUpdate(
    topic: LiveTopic.qa,
    title: '观众提问：离线阅读如何保证一致？',
    body: '宿主可以先规范化一次，再用 WeftDocumentJson 把快照送到客户端；'
        '格式与版本门禁会拒绝不兼容的包。',
    quote: '「动态不是刷新，而是不要抛下正在阅读的人。」',
  ),
  _IncomingUpdate(
    topic: LiveTopic.keynote,
    title: '圆桌开始：边界比能力更重要',
    body: '下一场讨论聚焦受控内容：哪些动态可以进入引擎，哪些必须交给宿主和 WebView。',
  ),
  _IncomingUpdate(
    topic: LiveTopic.lab,
    title: '快照之外的资源预算',
    body: '一张页面可以持续更新，但脚本、图片和网络始终需要宿主明确授权。'
        '现场把这条边界写进了演示的页脚。',
  ),
];
