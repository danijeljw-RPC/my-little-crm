import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/clock.dart';
import '../../domain/crm_service.dart';
import '../../domain/models.dart';

class ExportDocument {
  const ExportDocument(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
  String get content => utf8.decode(bytes);
}

class HistoryExportService {
  const HistoryExportService(this.service, {this.clock = const SystemClock()});
  static const unsupportedPdfTextMessage =
      'PDF export cannot safely display every character in this history. '
      'Choose JSON instead.';
  final CrmService service;
  final Clock clock;

  Future<ExportDocument> exportJson(PartyId partyId) async {
    final party = await _party(partyId);
    final items = await _history(partyId);
    final content = const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': 1,
      'generatedAt': clock.now().toUtc().toIso8601String(),
      'party': {'id': party.id, 'name': party.name},
      'interactions': items
          .map(
            (i) => {
              'id': i.id,
              'partyId': i.partyId,
              'timestamp': i.timestamp.toUtc().toIso8601String(),
              'createdAt': i.createdAt.toUtc().toIso8601String(),
              'method': i.method.name,
              'contactName': i.contactName,
              'summary': i.summary,
              'referenceNumbers': i.referenceNumbers,
              'commitment': i.commitment,
              'followUp': i.followUp == null
                  ? null
                  : {
                      'dueAt': i.followUp!.dueAt.toUtc().toIso8601String(),
                      'status': i.followUp!.status.name,
                    },
            },
          )
          .toList(),
    });
    return ExportDocument(
      'party-history.json',
      Uint8List.fromList(utf8.encode(content)),
    );
  }

  Future<ExportDocument> exportPdf(PartyId partyId) async {
    final party = await _party(partyId);
    final items = await _history(partyId);
    _ensurePdfTextIsSupported(party, items);
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: font, bold: font),
    );
    document.addPage(
      pw.MultiPage(
        maxPages: 10000,
        build: (_) => [
          pw.Header(level: 0, text: party.name),
          pw.Paragraph(
            text: 'Generated ${clock.now().toUtc().toIso8601String()}',
          ),
          if (items.isEmpty) pw.Paragraph(text: 'No interactions recorded.'),
          for (final i in items) ...[
            pw.Header(
              level: 1,
              text: '${i.timestamp.toLocal()} - ${i.method.name}',
            ),
            pw.Text(i.summary, overflow: pw.TextOverflow.span),
            if (i.contactName != null)
              pw.Text(
                'Contact: ${i.contactName}',
                overflow: pw.TextOverflow.span,
              ),
            if (i.referenceNumbers.isNotEmpty)
              pw.Text(
                'References: ${i.referenceNumbers.join(', ')}',
                overflow: pw.TextOverflow.span,
              ),
            if (i.commitment != null)
              pw.Text(
                'Commitment: ${i.commitment}',
                overflow: pw.TextOverflow.span,
              ),
            if (i.followUp != null)
              pw.Paragraph(
                text:
                    'Follow-up: ${i.followUp!.dueAt.toLocal()} (${i.followUp!.status.name})',
              ),
            pw.Paragraph(
              text:
                  'Record: ${i.id}\nCreated: ${i.createdAt.toUtc().toIso8601String()}',
            ),
          ],
        ],
      ),
    );
    return ExportDocument('party-history.pdf', await document.save());
  }

  Future<Party> _party(PartyId id) async =>
      await service.parties.get(id) ??
      (throw StateError('Party no longer exists'));
  Future<List<Interaction>> _history(PartyId id) async =>
      (await service.partyHistory(id)).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  void _ensurePdfTextIsSupported(Party party, List<Interaction> items) {
    final text = [
      party.name,
      for (final item in items) ...[
        item.id,
        item.summary,
        if (item.contactName != null) item.contactName!,
        ...item.referenceNumbers,
        if (item.commitment != null) item.commitment!,
      ],
    ];
    if (text.any(
      (value) =>
          value.runes.any((codePoint) => !_isPdfCodePointSupported(codePoint)),
    )) {
      throw StateError(unsupportedPdfTextMessage);
    }
  }

  bool _isPdfCodePointSupported(int codePoint) =>
      codePoint == 0x09 ||
      codePoint == 0x0a ||
      (codePoint >= 0x20 && codePoint <= 0x7e) ||
      (codePoint >= 0xa0 && codePoint <= 0x377) ||
      (codePoint >= 0x37a && codePoint <= 0x37f) ||
      (codePoint >= 0x384 && codePoint <= 0x38a) ||
      codePoint == 0x38c ||
      (codePoint >= 0x38e && codePoint <= 0x3a1) ||
      (codePoint >= 0x3a3 && codePoint <= 0x3e1) ||
      (codePoint >= 0x3f0 && codePoint <= 0x52f) ||
      (codePoint >= 0x2000 && codePoint <= 0x2064);

  Future<bool> save(ExportDocument document) async =>
      await FilePicker.saveFile(
        dialogTitle: 'Save communication history',
        fileName: document.name,
        bytes: document.bytes,
        mimeType: document.name.endsWith('.pdf')
            ? 'application/pdf'
            : 'application/json',
      ) !=
      null;
}
