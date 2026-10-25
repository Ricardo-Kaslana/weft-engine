import 'package:flutter/widgets.dart';
import 'package:weft_document/weft_document.dart';
import 'package:weft_engine/weft_engine.dart';

import 'weft_controller.dart';

typedef WeftFallbackBuilder = Widget Function(
  BuildContext context,
  SupportReport report,
);

class WeftView extends StatelessWidget {
  const WeftView({
    super.key,
    required this.controller,
    this.fallbackBuilder,
    this.onLinkTap,
    this.imageResolver,
  });

  final WeftController controller;
  final WeftFallbackBuilder? fallbackBuilder;
  final ValueChanged<WeftLinkRegion>? onLinkTap;
  final WeftImageResolver? imageResolver;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final document = controller.document;
        if (document == null) return const SizedBox.shrink();

        if (!document.supportReport.canRender) {
          final fallback = fallbackBuilder;
          if (fallback != null) {
            return fallback(context, document.supportReport);
          }
          throw FlutterError(
            'Weft cannot render this document. '
            'Provide WeftView.fallbackBuilder for unsupported content.',
          );
        }

        final textScaler =
            MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
        return SingleChildScrollView(
          primary: false,
          child: WeftSurface(
            document: document,
            selection: controller.selection,
            textScaler: textScaler,
            imageResolver: imageResolver,
            onLinkTap: onLinkTap,
          ),
        );
      },
    );
  }
}
