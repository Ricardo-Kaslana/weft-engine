import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weft/weft.dart';
import 'package:weft_live/live_document.dart';
import 'package:weft_live/live_tag_renderers.dart';

void main() {
  late LivePageModel model;

  setUp(() {
    model = const LivePageModel(
      palette: LivePalette.light,
      filter: LiveFilter.all,
      updates: const <LiveUpdate>[
        LiveUpdate(
          time: '10:42',
          topic: LiveTopic.keynote,
          title: '主舞台：内容开始自己呼吸',
          body: '同一张表面完成排版与命中。',
          fresh: true,
        ),
        LiveUpdate(
          time: '10:31',
          topic: LiveTopic.qa,
          title: '观众提问：动态刷新会打断阅读吗？',
          body: '滚动位置与逻辑锚点保持稳定。',
        ),
      ],
      stageIndex: 1,
      pollOptions: const <PollOption>[
        PollOption(id: 'layout', label: '让长文按场景重排', votes: 12),
        PollOption(id: 'data', label: '让数据拥有叙事', votes: 7),
      ],
      votedOption: null,
      isLive: true,
      viewers: 12480,
      interactions: 38240,
      questions: 216,
      claps: 1284,
      pulse: const <double>[0.2, 0.4, 0.72, 0.61],
      phase: 3,
      updatedAt: '10:42:06',
      voteNote: null,
    );
  });

  test('document normalizes with custom tags and no fallback', () {
    final snapshot = const WeftNormalizer(customTags: liveCustomTags).normalize(
      buildLiveDocument(model),
      id: 'live-doc-test',
    );

    expect(snapshot.supportReport.canRender, isTrue);
    expect(snapshot.supportReport.requiresWebView, isFalse);
    expect(snapshot.normalizedHtml, contains('weft-cover'));
    expect(snapshot.normalizedHtml, contains('weft-pulse'));
    expect(snapshot.normalizedHtml, contains('weft-vote'));
    expect(snapshot.normalizedHtml, contains('weft-clap'));
    expect(snapshot.normalizedHtml, contains('界面'));
    expect(snapshot.normalizedHtml, contains('主舞台：内容开始自己呼吸'));
  });

  test('filter changes the visible stream without dropping the live shell', () {
    final qaModel = LivePageModel(
      palette: LivePalette.dark,
      filter: LiveFilter.qa,
      updates: model.updates,
      stageIndex: 2,
      pollOptions: model.pollOptions,
      votedOption: 'data',
      isLive: false,
      viewers: 12480,
      interactions: 38240,
      questions: 216,
      claps: 1284,
      pulse: model.pulse,
      phase: 4,
      updatedAt: '10:42:08',
      voteNote: '已记录你的选择。',
    );
    final snapshot = const WeftNormalizer(customTags: liveCustomTags).normalize(
      buildLiveDocument(qaModel),
      id: 'live-doc-filter-test',
    );

    expect(snapshot.supportReport.canRender, isTrue);
    expect(snapshot.normalizedHtml, contains('观众提问：动态刷新会打断阅读吗'));
    expect(snapshot.normalizedHtml, isNot(contains('主舞台：内容开始自己呼吸')));
    expect(snapshot.normalizedHtml, contains('直播已暂停'));
  });

  test('all custom tag renderers produce bounded layouts', () {
    const scaler = TextScaler.noScaling;
    final cover = const LiveCoverRenderer().layout(
      WeftTagLayoutContext(
        element: WeftElement(
          id: 1,
          tag: 'weft-cover',
          attributes: const <String, String>{'data-phase': '3'},
        ),
        contentWidth: 620,
        textScaler: scaler,
      ),
    );
    final chart = const LivePulseRenderer().layout(
      WeftTagLayoutContext(
        element: WeftElement(
          id: 2,
          tag: 'weft-pulse',
          attributes: const <String, String>{
            'data-values': '0.2,0.5,0.8,0.6',
          },
        ),
        contentWidth: 620,
        textScaler: scaler,
      ),
    );
    final vote = const LiveVoteRenderer().layout(
      WeftTagLayoutContext(
        element: WeftElement(
          id: 3,
          tag: 'weft-vote',
          attributes: const <String, String>{
            'data-label': '让数据拥有叙事',
            'data-percent': '42',
            'data-votes': '1,024',
            'data-selected': 'true',
          },
        ),
        contentWidth: 620,
        textScaler: scaler,
      ),
    );

    expect(cover.height, greaterThan(170));
    expect(cover.ops, isNotEmpty);
    expect(chart.height, greaterThan(140));
    expect(chart.semanticsLabel, contains('60%'));
    expect(vote.semanticsLabel, contains('42%'));
    expect(vote.ops, isNotEmpty);
  });
}
