import 'package:flutter/material.dart';

import '../../domain/crm_service.dart';
import '../../domain/models.dart';
import '../export/history_export_service.dart';
import '../interactions/interaction_editor.dart';

class PartyHistoryScreen extends StatefulWidget {
  const PartyHistoryScreen({
    super.key,
    required this.service,
    required this.party,
  });
  final CrmService service;
  final Party party;
  @override
  State<PartyHistoryScreen> createState() => _PartyHistoryScreenState();
}

class _PartyHistoryScreenState extends State<PartyHistoryScreen> {
  CrmService get service => widget.service;
  Party get party => widget.party;
  Future<void> _export(BuildContext context, String format) async {
    final exporter = HistoryExportService(service);
    try {
      final document = format == 'PDF'
          ? await exporter.exportPdf(party.id)
          : await exporter.exportJson(party.id);
      final saved = await exporter.save(document);
      if (context.mounted && saved) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('History exported')));
      }
    } catch (error) {
      if (context.mounted) {
        final message =
            error is StateError &&
                error.message == HistoryExportService.unsupportedPdfTextMessage
            ? HistoryExportService.unsupportedPdfTextMessage
            : 'Could not export history. Please try again.';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(party.name),
      actions: [
        PopupMenuButton<String>(
          tooltip: 'Export history',
          onSelected: (format) => _export(context, format),
          itemBuilder: (_) => [
            for (final format in ['PDF', 'JSON'])
              PopupMenuItem(value: format, child: Text('Export $format')),
          ],
        ),
      ],
    ),
    body: FutureBuilder<List<Interaction>>(
      future: service.partyHistory(party.id),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          children: [
            for (final item in snapshot.data!)
              ListTile(
                onTap: () async {
                  await editInteraction(
                    context,
                    service,
                    existing: item,
                    partyName: party.name,
                  );
                  if (mounted) setState(() {});
                },
                title: Text(item.summary),
                subtitle: Text(
                  '${item.timestamp.toLocal()} · ${item.method.name}\n${[if (item.contactName != null) item.contactName!, ...item.referenceNumbers, if (item.commitment != null) item.commitment!, if (item.followUp != null) 'Follow-up ${item.followUp!.dueAt.toLocal()}: ${item.followUp!.status.name}'].join('\n')}',
                ),
                trailing: item.followUp?.status == FollowUpStatus.completed
                    ? const Icon(Icons.check_circle)
                    : const Icon(Icons.edit_outlined),
              ),
          ],
        );
      },
    ),
  );
}
