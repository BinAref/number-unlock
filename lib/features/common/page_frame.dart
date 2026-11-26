import 'package:flutter/material.dart';

import '../../ui/kit/widgets.dart';
import 'navigation.dart';

/// Inner pages: a title plaque, the content, and the fixed home gate at the
/// bottom centre (no separate back button).
class PageFrame extends StatelessWidget {
  const PageFrame({super.key, required this.title, required this.child, this.scroll = true});

  final String title;
  final Widget child;
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(children: [
          const SizedBox(height: 10),
          Plaque(title, size: 22),
          const SizedBox(height: 12),
          Expanded(
            child: scroll
                ? SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 16),
                    child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: child)),
                  )
                : child,
          ),
          Padding(padding: const EdgeInsets.only(bottom: 8), child: HomeGate(onTap: () => openHome(context))),
        ]),
      ),
    );
  }
}
