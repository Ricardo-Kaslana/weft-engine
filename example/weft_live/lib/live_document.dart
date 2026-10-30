import 'package:flutter/painting.dart';

/// Custom elements the host allowlists and renders for this page.
const Set<String> liveCustomTags = <String>{
  'weft-cover',
  'weft-live-band',
  'weft-pulse',
  'weft-vote',
  'weft-clap',
};

enum LiveFilter {
  all('全部'),
  keynote('主舞台'),
  lab('实验室'),
  qa('问答');

  const LiveFilter(this.label);

  final String label;

  bool matches(LiveUpdate update) {
    return switch (this) {
      LiveFilter.all => true,
      LiveFilter.keynote => update.topic == LiveTopic.keynote,
      LiveFilter.lab => update.topic == LiveTopic.lab,
      LiveFilter.qa => update.topic == LiveTopic.qa,
    };
  }
}

enum LiveTopic {
  keynote('主舞台', 'keynote'),
  lab('现场实验', 'lab'),
  qa('观众问答', 'qa');

  const LiveTopic(this.label, this.cssClass);

  final String label;
  final String cssClass;
}

final class LiveUpdate {
  const LiveUpdate({
    required this.time,
    required this.topic,
    required this.title,
    required this.body,
    this.quote,
    this.fresh = false,
  });

  final String time;
  final LiveTopic topic;
  final String title;
  final String body;
  final String? quote;
  final bool fresh;

  LiveUpdate withFresh(bool value) {
    return LiveUpdate(
      time: time,
      topic: topic,
      title: title,
      body: body,
      quote: quote,
      fresh: value,
    );
  }
}

final class PollOption {
  const PollOption(
      {required this.id, required this.label, required this.votes});

  final String id;
  final String label;
  final int votes;

  PollOption withVotes(int value) {
    return PollOption(id: id, label: label, votes: value);
  }
}

final class LiveAgendaItem {
  const LiveAgendaItem({
    required this.time,
    required this.title,
    required this.speaker,
  });

  final String time;
  final String title;
  final String speaker;
}

const List<LiveAgendaItem> liveAgenda = <LiveAgendaItem>[
  LiveAgendaItem(
    time: '10:00',
    title: '开场：页面为什么需要呼吸',
    speaker: '林未 / Weft Studio',
  ),
  LiveAgendaItem(
    time: '10:25',
    title: '自适应内容管线现场拆解',
    speaker: '陈屿 / 排版工程',
  ),
  LiveAgendaItem(
    time: '10:50',
    title: '实验室：零 Widget 的一张页面',
    speaker: 'Mina Zhou / 渲染实验室',
  ),
  LiveAgendaItem(
    time: '11:20',
    title: '圆桌：动态内容的边界',
    speaker: '全体讲者',
  ),
];

/// Every color the document and the tag renderers need for one theme.
final class LivePalette {
  const LivePalette({
    required this.isDark,
    required this.page,
    required this.surface,
    required this.surfaceAlt,
    required this.ink,
    required this.muted,
    required this.line,
    required this.accent,
    required this.teal,
    required this.lime,
    required this.hero,
    required this.heroInk,
    required this.heroMuted,
  });

  static const light = LivePalette(
    isDark: false,
    page: Color(0xFFF3EFE6),
    surface: Color(0xFFFFFCF5),
    surfaceAlt: Color(0xFFE9E2D5),
    ink: Color(0xFF161A20),
    muted: Color(0xFF6C685F),
    line: Color(0xFFD7CFC0),
    accent: Color(0xFFF2552C),
    teal: Color(0xFF137D79),
    lime: Color(0xFFD7FF63),
    hero: Color(0xFF12161D),
    heroInk: Color(0xFFF7F2E8),
    heroMuted: Color(0xFFB7B1A5),
  );

  static const dark = LivePalette(
    isDark: true,
    page: Color(0xFF0B0E13),
    surface: Color(0xFF141922),
    surfaceAlt: Color(0xFF1D232E),
    ink: Color(0xFFF3EFE7),
    muted: Color(0xFF969BA6),
    line: Color(0xFF2C333F),
    accent: Color(0xFFFF6B4A),
    teal: Color(0xFF5ED8C8),
    lime: Color(0xFFD7FF63),
    hero: Color(0xFF171C25),
    heroInk: Color(0xFFF7F2E8),
    heroMuted: Color(0xFFAEB4BE),
  );

  final bool isDark;
  final Color page;
  final Color surface;
  final Color surfaceAlt;
  final Color ink;
  final Color muted;
  final Color line;
  final Color accent;
  final Color teal;
  final Color lime;
  final Color hero;
  final Color heroInk;
  final Color heroMuted;

  Color get accentWash =>
      Color.alphaBlend(accent.withValues(alpha: 0.12), surface);
  Color get tealWash => Color.alphaBlend(teal.withValues(alpha: 0.12), surface);
}

final class LivePageModel {
  const LivePageModel({
    required this.palette,
    required this.filter,
    required this.updates,
    required this.stageIndex,
    required this.pollOptions,
    required this.votedOption,
    required this.viewers,
    required this.interactions,
    required this.questions,
    required this.claps,
    required this.pulse,
    required this.phase,
    required this.updatedAt,
    required this.voteNote,
    required this.isLive,
  });

  final LivePalette palette;
  final LiveFilter filter;
  final List<LiveUpdate> updates;
  final int stageIndex;
  final List<PollOption> pollOptions;
  final String? votedOption;
  final bool isLive;
  final int viewers;
  final int interactions;
  final int questions;
  final int claps;
  final List<double> pulse;
  final int phase;
  final String updatedAt;
  final String? voteNote;

  int get pollTotal => pollOptions.fold(0, (sum, option) => sum + option.votes);
  double get activity => pulse.isEmpty ? 0 : pulse.last;
}

String buildLiveDocument(LivePageModel model) {
  final palette = model.palette;
  final visibleUpdates =
      model.updates.where(model.filter.matches).toList(growable: false);
  final stage =
      liveAgenda[model.stageIndex.clamp(0, liveAgenda.length - 1).toInt()];
  final total = model.pollTotal;

  return '''
<style>
  body {
    background-color: ${_css(palette.page)};
    color: ${_css(palette.ink)};
    font-family: sans-serif;
    font-size: 16px;
    line-height: 1.6;
  }
  .hero { background-color: ${_css(palette.hero)}; }
  .hero-inner {
    max-width: 760px;
    margin: 0 auto;
    padding: 40px 36px 30px;
  }
  .kicker {
    color: ${_css(palette.lime)};
    font-size: 11px;
    font-weight: 700;
    line-height: 1.3;
    margin: 0 0 18px;
  }
  .hero h1 {
    color: ${_css(palette.heroInk)};
    font-size: 54px;
    font-weight: 700;
    line-height: 1.06;
    margin: 0 0 18px;
  }
  .hero h1 .mark {
    background-color: ${_css(palette.lime)};
    color: ${_css(palette.hero)};
  }
  .hero .deck {
    color: ${_css(palette.heroMuted)};
    font-size: 18px;
    line-height: 1.55;
    margin: 0 0 20px;
  }
  .hero .meta {
    color: ${_css(palette.heroMuted)};
    font-size: 12px;
    line-height: 1.5;
    margin: 0;
  }
  .content {
    max-width: 760px;
    margin: 0 auto;
    padding: 0 36px 64px;
  }
  .lead {
    color: ${_css(palette.ink)};
    font-size: 19px;
    line-height: 1.65;
    margin: 24px 0;
  }
  h2 {
    color: ${_css(palette.ink)};
    font-size: 30px;
    font-weight: 700;
    line-height: 1.2;
    margin: 42px 0 12px;
  }
  h3 {
    color: ${_css(palette.ink)};
    font-size: 18px;
    font-weight: 700;
    line-height: 1.35;
    margin: 0 0 8px;
  }
  p {
    color: ${_css(palette.ink)};
    font-size: 16px;
    line-height: 1.65;
    margin: 0 0 14px;
  }
  .eyebrow {
    color: ${_css(palette.accent)};
    font-size: 10px;
    font-weight: 700;
    line-height: 1.4;
    margin: 0 0 4px;
  }
  .section-note {
    color: ${_css(palette.muted)};
    font-size: 13px;
    line-height: 1.6;
    margin: 0 0 16px;
  }
  .caption {
    color: ${_css(palette.muted)};
    font-size: 11px;
    line-height: 1.5;
    margin: 8px 0 0;
  }
  a {
    color: ${_css(palette.accent)};
    text-decoration: underline;
  }
  .mono { font-family: monospace; }
  .accent { color: ${_css(palette.accent)}; }
  .teal { color: ${_css(palette.teal)}; }
  .muted { color: ${_css(palette.muted)}; }
  /* Weft resolves percentage table widths as auto; a px width clamps to the
     content box, so 760px means "full width at every viewport". */
  table { border-collapse: collapse; width: 760px; }
  .stats { margin: 26px 0 6px; }
  .stats td {
    width: 33%;
    border-top: 1px solid ${_css(palette.ink)};
    border-bottom: 1px solid ${_css(palette.line)};
    padding: 14px 14px 14px 0;
    vertical-align: top;
  }
  .stat-value {
    color: ${_css(palette.ink)};
    font-family: monospace;
    font-size: 30px;
    font-weight: 700;
    line-height: 1.1;
    margin: 0 0 4px;
  }
  .stat-label {
    color: ${_css(palette.muted)};
    font-size: 11px;
    line-height: 1.4;
    margin: 0;
  }
  .stat-delta {
    color: ${_css(palette.teal)};
    font-size: 11px;
    line-height: 1.4;
    margin: 4px 0 0;
  }
  .update {
    background-color: ${_css(palette.surface)};
    border-left: 3px solid ${_css(palette.teal)};
    padding: 16px 18px 8px;
    margin: 0 0 12px;
  }
  .update.fresh {
    background-color: ${_css(palette.accentWash)};
    border-left: 3px solid ${_css(palette.accent)};
  }
  .update.keynote { border-left: 3px solid ${_css(palette.accent)}; }
  .update.lab { border-left: 3px solid ${_css(palette.teal)}; }
  .update.qa { border-left: 3px solid ${_css(palette.muted)}; }
  .update-meta {
    color: ${_css(palette.muted)};
    font-family: monospace;
    font-size: 11px;
    line-height: 1.4;
    margin: 0 0 8px;
  }
  .new {
    background-color: ${_css(palette.accent)};
    color: ${_css(palette.surface)};
    font-size: 9px;
    font-weight: 700;
  }
  .update p { margin-bottom: 8px; }
  .empty {
    background-color: ${_css(palette.surfaceAlt)};
    color: ${_css(palette.muted)};
    padding: 18px;
  }
  .agenda { margin: 12px 0 24px; }
  .agenda th {
    color: ${_css(palette.muted)};
    font-size: 10px;
    font-weight: 700;
    line-height: 1.4;
    padding: 0 12px 8px 0;
    text-align: left;
    vertical-align: bottom;
  }
  .agenda td {
    border-top: 1px solid ${_css(palette.line)};
    padding: 12px 12px 12px 0;
    vertical-align: top;
  }
  .agenda .now { background-color: ${_css(palette.accentWash)}; }
  .agenda .time {
    color: ${_css(palette.muted)};
    font-family: monospace;
    font-size: 12px;
    margin: 0;
  }
  .agenda .title {
    font-size: 14px;
    font-weight: 700;
    line-height: 1.35;
    margin: 0 0 2px;
  }
  .agenda .speaker {
    color: ${_css(palette.muted)};
    font-size: 11px;
    line-height: 1.4;
    margin: 0;
  }
  .agenda .state {
    font-size: 10px;
    font-weight: 700;
    line-height: 1.4;
    margin: 0;
  }
  blockquote {
    background-color: ${_css(palette.surface)};
    border-left: 3px solid ${_css(palette.accent)};
    color: ${_css(palette.ink)};
    font-size: 18px;
    line-height: 1.6;
    margin: 18px 0;
    padding: 16px 20px 8px;
  }
  blockquote p { font-size: 18px; }
  .author {
    color: ${_css(palette.muted)};
    font-size: 11px;
    font-style: normal;
    line-height: 1.5;
  }
  .poll-count {
    color: ${_css(palette.muted)};
    font-family: monospace;
    font-size: 11px;
    margin: 0 0 8px;
  }
  .vote-note {
    color: ${_css(palette.teal)};
    font-size: 12px;
    line-height: 1.5;
    margin: 10px 0 0;
  }
  weft-cover { margin: 24px 0 0; }
  weft-live-band { margin: 24px 0 0; }
  weft-pulse { margin: 6px 0 0; }
  weft-vote { margin: 8px 0 0; }
  weft-clap { margin: 10px 0 0; }
  .clap-section {
    border-top: 1px solid ${_css(palette.line)};
    margin-top: 30px;
    padding-top: 22px;
  }
  .related { margin: 12px 0 0; padding: 0 0 0 20px; }
  .related li {
    color: ${_css(palette.ink)};
    font-size: 14px;
    line-height: 1.6;
    margin: 0 0 8px;
  }
  .footer {
    border-top: 1px solid ${_css(palette.line)};
    margin-top: 42px;
    padding-top: 20px;
  }
  .footer p {
    color: ${_css(palette.muted)};
    font-size: 11px;
    line-height: 1.6;
  }
  .footer .wordmark {
    color: ${_css(palette.ink)};
    font-size: 13px;
    font-weight: 700;
  }
</style>
<div class="hero">
  <div class="hero-inner">
    <p class="kicker">WEFT LIVE / TRANSMISSION 026 / SHANGHAI</p>
    <h1>界面，<br><span class="mark">开始自己呼吸。</span></h1>
    <p class="deck">
      当内容不再等待页面刷新，而是像布料一样实时编织。
      我们记录一场关于自适应排版、实时数据与内容边界的公开实验。
    </p>
    <p class="meta mono">
      2026.10.30 &nbsp;·&nbsp; 10:00–12:00 &nbsp;·&nbsp; 现场与线上同步
    </p>
    ${_cover(model)}
  </div>
</div>
<div class="content">
  ${_liveBand(model, stage)}
  <p class="lead">
    这不是一段预先录好的页面。你看到的数字、脉冲和现场记录，
    由宿主在每次更新时重新生成受控 HTML 快照，再交给同一张 Weft
    表面完成排版、绘制、命中与无障碍语义。
  </p>
  <table class="stats">
    <colgroup>
      <col width="33%"><col width="33%"><col width="34%">
    </colgroup>
    <tr>
      <td>
        <p class="stat-value">${_grouped(model.viewers)}</p>
        <p class="stat-label">在线观众</p>
        <p class="stat-delta">较开场 +18.4%</p>
      </td>
      <td>
        <p class="stat-value">${_compact(model.interactions)}</p>
        <p class="stat-label">实时互动</p>
        <p class="stat-delta">刚刚 +${24 + model.phase}</p>
      </td>
      <td>
        <p class="stat-value">${model.questions}</p>
        <p class="stat-label">待答提问</p>
        <p class="stat-delta">主持人已筛选 61%</p>
      </td>
    </tr>
  </table>
  <p class="caption mono">数据流 · ${model.updatedAt} · ${model.isLive ? '自动刷新 2s' : '直播已暂停'}</p>

  <p class="eyebrow" style="margin-top: 38px">01 / SIGNAL</p>
  <h2 id="signal">现场脉冲</h2>
  <p>
    过去 90 秒的观众活跃度。刷新只交换不可变快照，滚动锚点、
    文本选区与语义树继续复用同一张渲染表面。
  </p>
  ${_pulseChart(model)}
  <p class="caption">
    WEAVELET INDEX / 采样窗口 90s / 峰值 ${(model.activity * 100).round()}%
  </p>
  <blockquote>
    <p>「页面不应该追赶内容，它应该成为内容的一部分。」</p>
    <p class="author">— 林未，开场演讲，10:21</p>
  </blockquote>

  <p class="eyebrow" style="margin-top: 38px">02 / LIVE STREAM</p>
  <h2 id="stream">直播流</h2>
  <p class="section-note">
    ${_streamNote(model, visibleUpdates.length)}
  </p>
  ${_updates(visibleUpdates)}

  <p class="eyebrow" style="margin-top: 38px">03 / RUN OF SHOW</p>
  <h2 id="agenda">现场议程</h2>
  ${_agenda(model.stageIndex)}

  <p class="eyebrow" style="margin-top: 38px">04 / OPEN QUESTION</p>
  <h2 id="poll">现场投票</h2>
  <p>
    如果自适应界面只能先改变一件事，你希望是哪一件？
    投票会立即写入当前快照，并重算每一条结果条。
  </p>
  <p class="poll-count">${_grouped(total)} 人已参与</p>
  ${_poll(model)}
  <p class="vote-note">${_escape(model.voteNote ?? '一人一票。结果仅用于现场演示。')}</p>

  <div class="clap-section">
    <p class="eyebrow">05 / AUDIENCE</p>
    <h2 style="margin-top: 4px">给现场一点回声</h2>
    <p>
      一个由自定义标签渲染的可点击区域。点击后，宿主更新状态，
      整页在下一帧获得新的快照。
    </p>
    ${_clap(model)}
    <p class="caption">最多可连续点击；计数会随每次重排保持。</p>
  </div>

  <p class="eyebrow" style="margin-top: 38px">06 / ECHO</p>
  <h2 id="echo">读者回声</h2>
  <blockquote>
    <p>“第一次看到长文、图表和投票活在同一张画布上，而不是一堆 iframe。”</p>
    <p class="author">— 周壹，前端工程师</p>
  </blockquote>
  <blockquote>
    <p>“暂停直播之后，页面被冻结成一个可选择的文档。这个边界感很重要。”</p>
    <p class="author">— Mina，内容设计师</p>
  </blockquote>

  <p class="eyebrow" style="margin-top: 38px">07 / MORE</p>
  <h2>继续探索</h2>
  <ul class="related">
    <li><a href="weft://about">这个页面如何被 Weft 渲染</a></li>
    <li><a href="weft://section/agenda">跳到现场议程</a></li>
    <li><a href="weft://section/poll">参与现场投票</a></li>
  </ul>

  <div class="footer">
    <p class="wordmark">WEFT / LIVE</p>
    <p>
      本页由 Weft 的受控 HTML/CSS 子集渲染，不使用 WebView、DOM
      或第三方脚本。人物、数据与活动均为演示内容。
    </p>
    <p><a href="weft://top">回到顶部 ↑</a></p>
  </div>
</div>
''';
}

String _cover(LivePageModel model) {
  final p = model.palette;
  return '''
<weft-cover
  data-bg="${_css(p.hero)}"
  data-ink="${_css(p.heroInk)}"
  data-muted="${_css(p.heroMuted)}"
  data-accent="${_css(p.accent)}"
  data-teal="${_css(p.teal)}"
  data-lime="${_css(p.lime)}"
  data-phase="${model.phase}"
  aria-label="WEFT LIVE 主视觉"></weft-cover>''';
}

String _liveBand(LivePageModel model, LiveAgendaItem stage) {
  final p = model.palette;
  return '''
<weft-live-band
  data-stage="${_escape(stage.title)}"
  data-viewers="${_grouped(model.viewers)}"
  data-bg="${_css(p.surfaceAlt)}"
  data-ink="${_css(p.ink)}"
  data-muted="${_css(p.muted)}"
  data-accent="${_css(p.accent)}"
  data-live="${model.isLive}"
  data-phase="${model.phase}"
  aria-label="${model.isLive ? '直播进行中' : '直播已暂停'}，${_escape(stage.title)}"></weft-live-band>''';
}

String _pulseChart(LivePageModel model) {
  final p = model.palette;
  final values = model.pulse.map((value) => value.toStringAsFixed(3)).join(',');
  return '''
<weft-pulse
  data-values="$values"
  data-bg="${_css(p.surface)}"
  data-grid="${_css(p.line)}"
  data-ink="${_css(p.ink)}"
  data-muted="${_css(p.muted)}"
  data-accent="${_css(p.accent)}"
  data-teal="${_css(p.teal)}"
  aria-label="现场脉冲，当前活跃度 ${(model.activity * 100).round()}%"></weft-pulse>''';
}

String _poll(LivePageModel model) {
  final p = model.palette;
  final total = model.pollTotal;
  final buffer = StringBuffer();
  for (final option in model.pollOptions) {
    final percent = total == 0 ? 0 : (option.votes * 100 / total).round();
    final selected = option.id == model.votedOption;
    buffer.writeln('''
<weft-vote
  data-action="vote"
  data-value="${_escape(option.id)}"
  data-label="${_escape(option.label)}"
  data-percent="$percent"
  data-votes="${_grouped(option.votes)}"
  data-selected="$selected"
  data-bg="${_css(p.surface)}"
  data-ink="${_css(p.ink)}"
  data-muted="${_css(p.muted)}"
  data-accent="${_css(p.accent)}"
  data-line="${_css(p.line)}"
  aria-label="投票：${_escape(option.label)}，$percent%"></weft-vote>''');
  }
  return buffer.toString();
}

String _clap(LivePageModel model) {
  final p = model.palette;
  return '''
<weft-clap
  data-action="clap"
  data-count="${_grouped(model.claps)}"
  data-bg="${_css(p.accent)}"
  data-on-accent="${_css(p.hero)}"
  data-phase="${model.phase}"
  aria-label="为现场鼓掌，当前 ${_grouped(model.claps)} 次"></weft-clap>''';
}

String _updates(List<LiveUpdate> updates) {
  if (updates.isEmpty) {
    return '<p class="empty">这个频道暂时没有新记录。切换筛选，或者恢复直播。</p>';
  }
  final buffer = StringBuffer();
  for (final update in updates) {
    final classes = <String>[
      'update',
      update.topic.cssClass,
      if (update.fresh) 'fresh',
    ].join(' ');
    final quote = update.quote == null
        ? ''
        : '<blockquote><p>${_escape(update.quote!)}</p></blockquote>';
    buffer.writeln('''
<div class="$classes">
  <p class="update-meta">${_escape(update.time)} · ${update.topic.label}${update.fresh ? ' <span class="new">NEW</span>' : ''}</p>
  <h3>${_escape(update.title)}</h3>
  <p>${_escape(update.body)}</p>
  $quote
</div>''');
  }
  return buffer.toString();
}

String _agenda(int stageIndex) {
  final current = stageIndex.clamp(0, liveAgenda.length - 1).toInt();
  final buffer = StringBuffer('''
<table class="agenda">
  <colgroup>
    <col width="16%"><col width="64%"><col width="20%">
  </colgroup>
  <thead>
    <tr><th>时间</th><th>环节</th><th>状态</th></tr>
  </thead>
  <tbody>''');
  for (var index = 0; index < liveAgenda.length; index++) {
    final item = liveAgenda[index];
    final isNow = index == current;
    final state = index < current ? '已结束' : (isNow ? 'LIVE' : '即将开始');
    final stateClass = isNow ? 'accent' : (index < current ? 'muted' : 'teal');
    buffer.writeln('''
<tr>
  <td${isNow ? ' class="now"' : ''}><p class="time">${item.time}</p></td>
  <td${isNow ? ' class="now"' : ''}>
    <p class="title">${_escape(item.title)}</p>
    <p class="speaker">${_escape(item.speaker)}</p>
  </td>
  <td${isNow ? ' class="now"' : ''}><p class="state $stateClass">$state</p></td>
</tr>''');
  }
  buffer.writeln('</tbody></table>');
  return buffer.toString();
}

String _streamNote(LivePageModel model, int count) {
  final scope = model.filter == LiveFilter.all ? '全部频道' : model.filter.label;
  final mode = model.isLive ? '自动刷新开启时，新记录会从顶部进入。' : '直播已暂停，当前内容保持冻结。';
  return '当前筛选：$scope · $count 条记录。$mode';
}

String _grouped(int value) {
  final text = value.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < text.length; index++) {
    if (index > 0 && (text.length - index) % 3 == 0) buffer.write(',');
    buffer.write(text[index]);
  }
  return buffer.toString();
}

String _compact(int value) {
  if (value < 1000) return '$value';
  final thousands = value / 1000;
  return '${thousands.toStringAsFixed(thousands >= 100 ? 0 : 1)}k';
}

String _escape(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

String _css(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0')}';
}
