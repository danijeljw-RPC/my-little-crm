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
  // Ranges from the cmap of assets/fonts/NotoSans-Regular.ttf. Keep this in
  // sync with that bundled asset; PDF text layout accepts tabs and newlines as
  // structural whitespace even though they do not have font glyphs.
  static const _pdfSupportedCodePointRanges = <(int, int)>[
    (0x20, 0x7e),
    (0xa0, 0x377),
    (0x37a, 0x37f),
    (0x384, 0x38a),
    (0x38c, 0x38c),
    (0x38e, 0x3a1),
    (0x3a3, 0x3e1),
    (0x3f0, 0x52f),
    (0x1ab0, 0x1ac0),
    (0x1c80, 0x1c88),
    (0x1d00, 0x1df9),
    (0x1dfb, 0x1f15),
    (0x1f18, 0x1f1d),
    (0x1f20, 0x1f45),
    (0x1f48, 0x1f4d),
    (0x1f50, 0x1f57),
    (0x1f59, 0x1f59),
    (0x1f5b, 0x1f5b),
    (0x1f5d, 0x1f5d),
    (0x1f5f, 0x1f7d),
    (0x1f80, 0x1fb4),
    (0x1fb6, 0x1fc4),
    (0x1fc6, 0x1fd3),
    (0x1fd6, 0x1fdb),
    (0x1fdd, 0x1fef),
    (0x1ff2, 0x1ff4),
    (0x1ff6, 0x1ffe),
    (0x2000, 0x2064),
    (0x2066, 0x2071),
    (0x2074, 0x208e),
    (0x2090, 0x209c),
    (0x20a0, 0x20bf),
    (0x20f0, 0x20f0),
    (0x2100, 0x215f),
    (0x2184, 0x2184),
    (0x2189, 0x2189),
    (0x25cc, 0x25cc),
    (0x2c60, 0x2c7f),
    (0x2de0, 0x2e52),
    (0xa640, 0xa69f),
    (0xa700, 0xa7bf),
    (0xa7c2, 0xa7ca),
    (0xa7f5, 0xa7ff),
    (0xa92e, 0xa92e),
    (0xab30, 0xab6b),
    (0xfb00, 0xfb06),
    (0xfe00, 0xfe00),
    (0xfe20, 0xfe2f),
    (0xfeff, 0xfeff),
    (0xfffc, 0xfffd),
  ];
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
      _pdfSupportedCodePointRanges.any(
        (range) => codePoint >= range.$1 && codePoint <= range.$2,
      );

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
