import 'package:flutter/material.dart';

import 'core/clock.dart';
import 'core/date_format.dart';
import 'demo/demo_banner.dart';
import 'domain/crm_service.dart';
import 'domain/models.dart';
import 'features/export/ledger_transfer.dart';
import 'features/follow_ups/follow_ups_screen.dart';
import 'features/interactions/interaction_editor.dart';
import 'features/interactions/recent_interactions_list.dart';
import 'features/parties/party_history_screen.dart';
import 'features/parties/party_list_screen.dart';
import 'features/search/search_screen.dart';

/// Material 3 window-size breakpoints (#31).
const compactMaxWidth = 600.0;
const expandedMinWidth = 840.0;

class MyLittleCrmApp extends StatefulWidget {
  const MyLittleCrmApp({
    super.key,
    this.service,
    this.dateLocale,
    this.demo = false,
  });
  final CrmService? service;

  /// Shows the demo banner: the data is sample data and is thrown away (#30).
  final bool demo;

  /// Fixes the locale used for dates (tests); null follows the device.
  final String? dateLocale;
  @override
  State<MyLittleCrmApp> createState() => _MyLittleCrmAppState();
}

class _MyLittleCrmAppState extends State<MyLittleCrmApp> {
  late final CrmService _fallback = CrmService.inMemory(
    clock: const SystemClock(),
  );
  CrmService get service => widget.service ?? _fallback;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'My Little CRM',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff315dce)),
      useMaterial3: true,
    ),
    builder: (context, child) => DateFormatScope(
      clock: service.clock,
      locale: widget.dateLocale,
      child: widget.demo ? DemoBanner(child: child!) : child!,
    ),
    home: InteractionHome(service: service),
  );
}

class InteractionHome extends StatefulWidget {
  const InteractionHome({super.key, required this.service});
  final CrmService service;
  @override
  State<InteractionHome> createState() => _InteractionHomeState();
}

class _InteractionHomeState extends State<InteractionHome> {
  CrmService get service => widget.service;
  var _selectedIndex = 0;
  int _overdue = 0;

  /// Two-pane selections (expanded widths only).
  Party? _interactionParty;
  InteractionId? _selectedInteraction;
  Party? _selectedParty;

  @override
  void initState() {
    super.initState();
    service.revision.addListener(_refreshOverdue);
    _refreshOverdue();
  }

  @override
  void dispose() {
    service.revision.removeListener(_refreshOverdue);
    super.dispose();
  }

  Future<void> _refreshOverdue() async {
    try {
      final count = await service.overdueFollowUpCount();
      if (mounted && count != _overdue) setState(() => _overdue = count);
    } catch (_) {
      // The badge is a hint; the follow-ups screen reports load failures.
    }
  }

  Future<void> _openHistory(Party party) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => PartyHistoryScreen(service: service, party: party),
    ),
  );

  Widget _twoPane({
    required Widget list,
    required Widget? detail,
    required String placeholder,
  }) => Row(
    children: [
      SizedBox(width: 400, child: list),
      const VerticalDivider(width: 1),
      Expanded(
        child:
            detail ??
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(placeholder, textAlign: TextAlign.center),
              ),
            ),
      ),
    ],
  );

  Widget _content(bool expanded) {
    switch (_selectedIndex) {
      case 1:
        return FollowUpsScreen(service: service);
      case 2:
        final list = PartyListScreen(
          service: service,
          selectedId: expanded ? _selectedParty?.id : null,
          onSelect: expanded
              ? (party) => setState(() => _selectedParty = party)
              : null,
        );
        if (!expanded) return list;
        return _twoPane(
          list: list,
          placeholder: 'Select a party to see its history',
          detail: _selectedParty == null
              ? null
              : PartyHistoryScreen(
                  key: ValueKey(_selectedParty!.id),
                  service: service,
                  party: _selectedParty!,
                  embedded: true,
                  onPartyChanged: (next) =>
                      setState(() => _selectedParty = next),
                ),
        );
      case 3:
        return SearchScreen(service: service);
      default:
        final list = RecentInteractionsList(
          service: service,
          selectedId: expanded ? _selectedInteraction : null,
          onOpen: (entry) {
            if (expanded) {
              setState(() {
                _interactionParty = entry.party;
                _selectedInteraction = entry.interaction.id;
              });
            } else {
              _openHistory(entry.party);
            }
          },
        );
        if (!expanded) return list;
        return _twoPane(
          list: list,
          placeholder: 'Select an interaction to see it in its party history',
          detail: _interactionParty == null
              ? null
              : PartyHistoryScreen(
                  key: ValueKey(_interactionParty!.id),
                  service: service,
                  party: _interactionParty!,
                  embedded: true,
                  highlight: _selectedInteraction,
                  onPartyChanged: (next) =>
                      setState(() => _interactionParty = next),
                ),
        );
    }
  }

  Widget _followUpIcon(IconData icon) => _overdue == 0
      ? Icon(icon)
      : Semantics(
          label: '$_overdue overdue',
          child: ExcludeSemantics(
            child: Badge(label: Text('$_overdue'), child: Icon(icon)),
          ),
        );

  List<({Widget icon, String label})> get _destinations => [
    (icon: const Icon(Icons.forum_outlined), label: 'Interactions'),
    (icon: _followUpIcon(Icons.checklist_outlined), label: 'Follow-ups'),
    (icon: const Icon(Icons.people_outline), label: 'Parties'),
    (icon: const Icon(Icons.search), label: 'Search'),
  ];

  void _select(int index) => setState(() => _selectedIndex = index);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < compactMaxWidth;
    final expanded = width >= expandedMinWidth;
    final transfer = LedgerTransfer(service);
    final content = _content(expanded);
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Little CRM'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More options',
            onSelected: (value) => switch (value) {
              'export' => transfer.exportEverything(context),
              'export-pdf' => transfer.exportEverythingPdf(context),
              _ => transfer.importExport(context),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.download_outlined),
                  title: Text('Export everything (JSON)'),
                  subtitle: Text('Not encrypted'),
                ),
              ),
              PopupMenuItem(
                value: 'export-pdf',
                child: ListTile(
                  leading: Icon(Icons.picture_as_pdf_outlined),
                  title: Text('Export everything (PDF)'),
                  subtitle: Text(
                    'Readable report · not encrypted or importable',
                  ),
                ),
              ),
              PopupMenuItem(
                value: 'import',
                child: ListTile(
                  leading: Icon(Icons.upload_outlined),
                  title: Text('Import an export'),
                  subtitle: Text('Into an empty ledger only'),
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => editInteraction(context, service),
        icon: const Icon(Icons.add),
        label: const Text('Add interaction'),
      ),
      body: compact
          ? content
          : Row(
              children: [
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _select,
                  extended: expanded,
                  labelType: expanded
                      ? NavigationRailLabelType.none
                      : NavigationRailLabelType.all,
                  destinations: [
                    for (final d in _destinations)
                      NavigationRailDestination(
                        icon: d.icon,
                        label: Text(d.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            ),
      bottomNavigationBar: compact
          ? NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _select,
              destinations: [
                for (final d in _destinations)
                  NavigationDestination(icon: d.icon, label: d.label),
              ],
            )
          : null,
    );
  }
}
