import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:weft/weft.dart';

const Map<String, WeftTagRenderer> liveTagRenderers = <String, WeftTagRenderer>{
  'weft-cover': LiveCoverRenderer(),
  'weft-live-band': LiveBandRenderer(),
  'weft-pulse': LivePulseRenderer(),
  'weft-vote': LiveVoteRenderer(),
  'weft-clap': LiveClapRenderer(),
};

final class LiveCoverRenderer implements WeftTagRenderer {
  const LiveCoverRenderer();

  @override
  WeftTagLayout layout(WeftTagLayoutContext context) {
    final width = context.contentWidth;
    if (width <= 0) return const WeftTagLayout(height: 0);

    final height = (width * 0.38).clamp(176.0, 286.0).toDouble();
    final phase = _intAttr(context.element, 'data-phase') ?? 0;
    final background =
        _colorAttr(context.element, 'data-bg', const Color(0xFF11151C));
    final ink =
        _colorAttr(context.element, 'data-ink', const Color(0xFFF5F0E6));
    final muted =
        _colorAttr(context.element, 'data-muted', const Color(0xFFB7B1A5));
    final accent =
        _colorAttr(context.element, 'data-accent', const Color(0xFFF2552C));
    final teal =
        _colorAttr(context.element, 'data-teal', const Color(0xFF137D79));
    final lime =
        _colorAttr(context.element, 'data-lime', const Color(0xFFD7FF63));
    final ops = <WeftTagOp>[
      WeftTagRectOp(
        rect: Rect.fromLTWH(0, 0, width, height),
        color: background,
      ),
    ];

    for (var x = 0.0; x < width; x += 48) {
      ops.add(WeftTagRectOp(
        rect: Rect.fromLTWH(x, 0, 1, height),
        color: ink.withValues(alpha: 0.055),
      ));
    }
    for (var y = 0.0; y < height; y += 48) {
      ops.add(WeftTagRectOp(
        rect: Rect.fromLTWH(0, y, width, 1),
        color: ink.withValues(alpha: 0.055),
      ));
    }

    final chartTop = height * 0.34;
    final chartBottom = height * 0.86;
    final columns = math.max(24, (width / 18).floor());
    final columnWidth = width / columns;
    for (var index = 0; index < columns; index++) {
      final angle = index * 0.55 + phase * 0.32;
      final wave = (math.sin(angle) + 1) / 2;
      final barHeight = (chartBottom - chartTop) * (0.16 + wave * 0.78);
      final isHot = (index + phase) % 11 == 0;
      final barColor = isHot
          ? lime
          : (index.isEven ? accent : teal).withValues(alpha: 0.2 + wave * 0.7);
      ops.add(WeftTagRectOp(
        rect: Rect.fromLTWH(
          index * columnWidth + 2,
          chartBottom - barHeight,
          math.max(1.5, columnWidth - 5),
          barHeight,
        ),
        color: barColor,
      ));
    }

    for (var pass = 0; pass < 2; pass++) {
      final color = pass == 0 ? accent : teal;
      final lineY = height * (0.46 + pass * 0.13);
      for (var index = 0; index < 88; index++) {
        final x = width * index / 88;
        final y = lineY +
            math.sin(index * 0.2 + phase * 0.4 + pass * 1.7) * height * 0.045;
        ops.add(WeftTagRectOp(
          rect: Rect.fromLTWH(x, y, math.max(2, width / 88 + 1), 2),
          color: color.withValues(alpha: 0.85),
        ));
      }
    }

    final frameSize = math.min(width * 0.18, 72.0);
    final frameRight = width - 22;
    final frameRect = Rect.fromLTWH(
      frameRight - frameSize,
      20,
      frameSize,
      frameSize,
    );
    _outline(ops, frameRect, lime.withValues(alpha: 0.85), 2);
    ops.add(WeftTagRectOp(
      rect: Rect.fromLTWH(
        frameRect.left + frameSize * 0.26,
        frameRect.top + frameSize * 0.26,
        frameSize * 0.48,
        frameSize * 0.48,
      ),
      color: lime.withValues(alpha: 0.18),
    ));
    ops.add(WeftTagTextOp(
      offset: Offset(frameRect.left + 8, frameRect.top + frameSize - 18),
      text: '026',
      style: TextStyle(
        color: lime,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
      maxWidth: frameSize - 12,
    ));

    ops.add(WeftTagRectOp(
      rect: const Rect.fromLTWH(20, 24, 7, 7),
      color: accent,
    ));
    ops.add(WeftTagTextOp(
      offset: const Offset(33, 20),
      text: 'LIVE / TRANSMISSION 026',
      style: TextStyle(
        color: muted,
        fontSize: 9,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.3,
      ),
      maxWidth: math.max(20, width - frameSize - 70),
    ));
    if (width > 380) {
      ops.add(WeftTagTextOp(
        offset: Offset(width - 112, 52),
        text: '31.2N / 121.5E',
        style: TextStyle(
          color: muted,
          fontSize: 8,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.7,
        ),
        maxWidth: 100,
      ));
    }

    final titleSize = math.min(56.0, width * 0.115);
    ops.add(WeftTagTextOp(
      offset: Offset(18, height - titleSize - 38),
      text: 'WEFT',
      style: TextStyle(
        color: ink,
        fontSize: titleSize,
        fontWeight: FontWeight.w800,
        height: 1,
      ),
      maxWidth: width - 36,
    ));
    ops.add(WeftTagTextOp(
      offset: Offset(20, height - 28),
      text: 'REALTIME WEAVE  /  SIGNAL ${(phase % 10) + 1}0',
      style: TextStyle(
        color: muted,
        fontSize: 8,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.1,
      ),
      maxWidth: width - 130,
    ));
    ops.add(WeftTagTextOp(
      offset: Offset(width - 58, height - 28),
      text: '${(76 + phase) % 100}%',
      style: TextStyle(
        color: lime,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
      maxWidth: 44,
    ));

    return WeftTagLayout(
      height: height,
      ops: ops,
      semanticsLabel: 'WEFT LIVE 实时编织主视觉',
    );
  }
}

final class LiveBandRenderer implements WeftTagRenderer {
  const LiveBandRenderer();

  @override
  WeftTagLayout layout(WeftTagLayoutContext context) {
    final width = context.contentWidth;
    if (width <= 0) return const WeftTagLayout(height: 0);
    final stage = context.element.attribute('data-stage') ?? '现场直播';
    final viewers = context.element.attribute('data-viewers') ?? '';
    final phase = _intAttr(context.element, 'data-phase') ?? 0;
    final isLive = context.element.attribute('data-live') == 'true';
    final background =
        _colorAttr(context.element, 'data-bg', const Color(0xFFE9E2D5));
    final ink =
        _colorAttr(context.element, 'data-ink', const Color(0xFF161A20));
    final muted =
        _colorAttr(context.element, 'data-muted', const Color(0xFF6C685F));
    final accent =
        _colorAttr(context.element, 'data-accent', const Color(0xFFF2552C));
    const height = 44.0;
    final ops = <WeftTagOp>[
      WeftTagRectOp(
        rect: Rect.fromLTWH(0, 0, width, height),
        color: background,
      ),
      WeftTagRectOp(
        rect: const Rect.fromLTWH(0, 0, 3, height),
        color: isLive ? accent : muted,
      ),
      WeftTagRectOp(
        rect: Rect.fromLTWH(18, 18, (phase % 3) + 5, (phase % 3) + 5),
        color: isLive ? accent : muted,
      ),
      WeftTagTextOp(
        offset: const Offset(33, 13),
        text: isLive ? 'LIVE' : 'PAUSED',
        style: TextStyle(
          color: isLive ? accent : muted,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
        maxWidth: 60,
      ),
      WeftTagTextOp(
        offset: const Offset(66, 12),
        text: stage,
        style: TextStyle(
          color: ink,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        maxWidth: math.max(20, width - (width > 420 ? 176 : 82)),
      ),
    ];
    if (width > 420) {
      ops.add(WeftTagTextOp(
        offset: Offset(width - 136, 15),
        text: '$viewers 在线',
        style: TextStyle(
          color: muted,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
        maxWidth: 120,
      ));
    }
    return WeftTagLayout(
      height: height,
      ops: ops,
      semanticsLabel: '${isLive ? '直播进行中' : '直播已暂停'}，$stage，$viewers 人在线',
    );
  }
}

final class LivePulseRenderer implements WeftTagRenderer {
  const LivePulseRenderer();

  @override
  WeftTagLayout layout(WeftTagLayoutContext context) {
    final width = context.contentWidth;
    if (width <= 0) return const WeftTagLayout(height: 0);
    final values = _values(context.element.attribute('data-values'));
    final background =
        _colorAttr(context.element, 'data-bg', const Color(0xFFFFFCF5));
    final grid =
        _colorAttr(context.element, 'data-grid', const Color(0xFFD7CFC0));
    final ink =
        _colorAttr(context.element, 'data-ink', const Color(0xFF161A20));
    final muted =
        _colorAttr(context.element, 'data-muted', const Color(0xFF6C685F));
    final accent =
        _colorAttr(context.element, 'data-accent', const Color(0xFFF2552C));
    final teal =
        _colorAttr(context.element, 'data-teal', const Color(0xFF137D79));
    const height = 172.0;
    final ops = <WeftTagOp>[
      WeftTagRectOp(
        rect: Rect.fromLTWH(0, 0, width, height),
        color: background,
      ),
    ];
    for (final fraction in const [0.34, 0.56, 0.78]) {
      ops.add(WeftTagRectOp(
        rect: Rect.fromLTWH(14, height * fraction, width - 28, 1),
        color: grid.withValues(alpha: 0.8),
      ));
    }
    final last = values.isEmpty ? 0.0 : values.last;
    ops.add(WeftTagTextOp(
      offset: const Offset(14, 12),
      text: 'LIVE PULSE / 90S',
      style: TextStyle(
        color: muted,
        fontSize: 9,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
      maxWidth: width * 0.6,
    ));
    ops.add(WeftTagTextOp(
      offset: Offset(math.max(14, width - 84), 8),
      text: '${(last * 100).round()}%',
      style: TextStyle(
        color: ink,
        fontSize: 22,
        fontWeight: FontWeight.w800,
        height: 1,
      ),
      maxWidth: 70,
    ));
    if (values.isNotEmpty) {
      const chartTop = 44.0;
      const baseline = 142.0;
      final slot = (width - 28) / values.length;
      for (var index = 0; index < values.length; index++) {
        final value = values[index].clamp(0.0, 1.0).toDouble();
        final barHeight = 4 + value * (baseline - chartTop);
        final isLast = index == values.length - 1;
        final color = isLast
            ? accent
            : (index.isEven ? accent : teal)
                .withValues(alpha: 0.25 + value * 0.55);
        ops.add(WeftTagRectOp(
          rect: Rect.fromLTWH(
            14 + index * slot,
            baseline - barHeight,
            math.max(2, slot - 2.4),
            barHeight,
          ),
          color: color,
        ));
      }
      ops.add(WeftTagRectOp(
        rect: Rect.fromLTWH(14 + (values.length - 1) * slot, chartTop - 8, 2,
            baseline - chartTop + 8),
        color: accent,
      ));
    }
    ops.add(WeftTagTextOp(
      offset: const Offset(14, 154),
      text: '-90S',
      style: TextStyle(color: muted, fontSize: 8, fontWeight: FontWeight.w500),
      maxWidth: 50,
    ));
    ops.add(WeftTagTextOp(
      offset: Offset(width / 2 - 16, height - 18),
      text: '-45S',
      style: TextStyle(color: muted, fontSize: 8, fontWeight: FontWeight.w500),
      maxWidth: 50,
    ));
    ops.add(WeftTagTextOp(
      offset: Offset(width - 42, height - 18),
      text: 'NOW',
      style: TextStyle(
        color: accent,
        fontSize: 8,
        fontWeight: FontWeight.w700,
      ),
      maxWidth: 40,
    ));
    return WeftTagLayout(
      height: height,
      ops: ops,
      semanticsLabel: '现场脉冲，当前活跃度 ${(last * 100).round()}%',
    );
  }
}

final class LiveVoteRenderer implements WeftTagRenderer {
  const LiveVoteRenderer();

  @override
  WeftTagLayout layout(WeftTagLayoutContext context) {
    final width = context.contentWidth;
    if (width <= 0) return const WeftTagLayout(height: 0);
    final label = context.element.attribute('data-label') ?? '选项';
    final percent = _intAttr(context.element, 'data-percent') ?? 0;
    final votes = context.element.attribute('data-votes') ?? '0';
    final selected = context.element.attribute('data-selected') == 'true';
    final background =
        _colorAttr(context.element, 'data-bg', const Color(0xFFFFFCF5));
    final ink =
        _colorAttr(context.element, 'data-ink', const Color(0xFF161A20));
    final muted =
        _colorAttr(context.element, 'data-muted', const Color(0xFF6C685F));
    final accent =
        _colorAttr(context.element, 'data-accent', const Color(0xFFF2552C));
    final line =
        _colorAttr(context.element, 'data-line', const Color(0xFFD7CFC0));
    const height = 64.0;
    final fillWidth = math.max(0.0, width * percent / 100);
    final ops = <WeftTagOp>[
      WeftTagRectOp(
        rect: Rect.fromLTWH(0, 0, width, height),
        color: selected
            ? Color.alphaBlend(accent.withValues(alpha: 0.12), background)
            : background,
      ),
      WeftTagRectOp(
        rect: Rect.fromLTWH(0, 0, fillWidth, height),
        color: accent.withValues(alpha: selected ? 0.1 : 0.055),
      ),
    ];
    _outline(ops, Rect.fromLTWH(0, 0, width, height), line, 1);
    if (selected) {
      ops.add(WeftTagRectOp(
        rect: const Rect.fromLTWH(0, 0, 3, height),
        color: accent,
      ));
    }
    ops.add(WeftTagRectOp(
      rect: Rect.fromLTWH(0, height - 3, fillWidth, 3),
      color: accent,
    ));
    ops.add(WeftTagTextOp(
      offset: const Offset(14, 12),
      text: label,
      style: TextStyle(
        color: ink,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
      maxWidth: math.max(20, width - 110),
    ));
    ops.add(WeftTagTextOp(
      offset: Offset(math.max(14, width - 60), 10),
      text: '$percent%',
      style: TextStyle(
        color: selected ? accent : ink,
        fontSize: 17,
        fontWeight: FontWeight.w800,
      ),
      maxWidth: 48,
    ));
    ops.add(WeftTagTextOp(
      offset: const Offset(14, 37),
      text: '$votes 票 · ${selected ? '这是你的选择' : '点击投票'}',
      style: TextStyle(
        color: selected ? accent : muted,
        fontSize: 10,
        fontWeight: FontWeight.w500,
      ),
      maxWidth: width - 28,
    ));
    return WeftTagLayout(
      height: height,
      ops: ops,
      semanticsLabel: '投票选项 $label，$percent%，$votes 票${selected ? '，已选中' : ''}',
    );
  }
}

final class LiveClapRenderer implements WeftTagRenderer {
  const LiveClapRenderer();

  @override
  WeftTagLayout layout(WeftTagLayoutContext context) {
    final width = context.contentWidth;
    if (width <= 0) return const WeftTagLayout(height: 0);
    final count = context.element.attribute('data-count') ?? '0';
    final phase = _intAttr(context.element, 'data-phase') ?? 0;
    final background =
        _colorAttr(context.element, 'data-bg', const Color(0xFFF2552C));
    final onAccent =
        _colorAttr(context.element, 'data-on-accent', const Color(0xFF12161D));
    const height = 62.0;
    final ops = <WeftTagOp>[
      WeftTagRectOp(
        rect: Rect.fromLTWH(0, 0, width, height),
        color: background,
      ),
    ];
    for (var index = 0; index < 8; index++) {
      final x = width - 96 + (index % 4) * 14;
      final y = 12.0 + (index ~/ 4) * 14;
      ops.add(WeftTagRectOp(
        rect: Rect.fromLTWH(x, y, (index + phase) % 3 == 0 ? 6.0 : 3.0, 3),
        color: onAccent.withValues(alpha: 0.16),
      ));
    }
    ops.add(WeftTagTextOp(
      offset: const Offset(18, 13),
      text: '为现场鼓掌',
      style: TextStyle(
        color: onAccent,
        fontSize: 16,
        fontWeight: FontWeight.w800,
      ),
      maxWidth: math.max(20, width - 150),
    ));
    ops.add(WeftTagTextOp(
      offset: const Offset(18, 36),
      text: 'TAP TO SEND  /  +1',
      style: TextStyle(
        color: onAccent.withValues(alpha: 0.72),
        fontSize: 9,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
      ),
      maxWidth: math.max(20, width - 160),
    ));
    ops.add(WeftTagTextOp(
      offset: Offset(math.max(18, width - 110), 19),
      text: count,
      style: TextStyle(
        color: onAccent,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
      maxWidth: 92,
    ));
    return WeftTagLayout(
      height: height,
      ops: ops,
      semanticsLabel: '为现场鼓掌，当前 $count 次',
    );
  }
}

void _outline(
  List<WeftTagOp> ops,
  Rect rect,
  Color color,
  double thickness,
) {
  ops
    ..add(WeftTagRectOp(
      rect: Rect.fromLTWH(rect.left, rect.top, rect.width, thickness),
      color: color,
    ))
    ..add(WeftTagRectOp(
      rect: Rect.fromLTWH(
          rect.left, rect.bottom - thickness, rect.width, thickness),
      color: color,
    ))
    ..add(WeftTagRectOp(
      rect: Rect.fromLTWH(rect.left, rect.top, thickness, rect.height),
      color: color,
    ))
    ..add(WeftTagRectOp(
      rect: Rect.fromLTWH(
          rect.right - thickness, rect.top, thickness, rect.height),
      color: color,
    ));
}

List<double> _values(String? raw) {
  if (raw == null || raw.isEmpty) return const <double>[];
  return raw
      .split(',')
      .map((value) => double.tryParse(value.trim()))
      .whereType<double>()
      .map((value) => value.clamp(0.0, 1.0).toDouble())
      .toList(growable: false);
}

int? _intAttr(WeftElement element, String name) {
  return int.tryParse(element.attribute(name) ?? '');
}

Color _colorAttr(WeftElement element, String name, Color fallback) {
  final value = element.attribute(name);
  if (value == null) return fallback;
  if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) return fallback;
  return Color(0xFF000000 | int.parse(value.substring(1), radix: 16));
}
