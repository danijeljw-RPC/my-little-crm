import 'package:flutter/material.dart';

import 'demo_mode.dart';

/// A permanent strip above the app that says the data is temporary (#30).
class DemoBanner extends StatelessWidget {
  const DemoBanner({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Material(
          color: scheme.tertiaryContainer,
          child: SafeArea(
            bottom: false,
            child: Semantics(
              container: true,
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.science_outlined,
                      size: 20,
                      color: scheme.onTertiaryContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        demoBannerText,
                        style: TextStyle(color: scheme.onTertiaryContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // The app below must not pad for the status bar a second time.
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: child,
          ),
        ),
      ],
    );
  }
}
