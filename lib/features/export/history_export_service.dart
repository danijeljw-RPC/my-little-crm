import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart' show PdfTooBigPageException;
import 'package:pdf/widgets.dart' as pw;

import '../../core/clock.dart';
import '../../core/date_format.dart';
import '../../domain/crm_service.dart';
import '../../domain/models.dart';

class ExportDocument {
  const ExportDocument(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
  String get content => utf8.decode(bytes);
}

class HistoryExportService {
  const HistoryExportService(
    this.service, {
    this.clock = const SystemClock(),
    this.dateFormat,
  });

  /// Formats dates in PDF reports; without one, ISO 8601 UTC is used.
  final AppDateFormat? dateFormat;

  /// A date and time for the PDF, in the user's locale when the bundled font
  /// can draw it, otherwise in en_US (e.g. Japanese 年/月/日 have no glyphs).
  @visibleForTesting
  String pdfDateTime(DateTime value) => _pdfSafe(
    (format) => format.fullDateTime(value),
    () => value.toUtc().toIso8601String(),
  );

  /// A day-only date for the PDF, with the same font fallback.
  @visibleForTesting
  String pdfDate(DateTime value) => _pdfSafe(
    (format) => format.fullDate(value),
    () => value.toUtc().toIso8601String(),
  );

  String _pdfSafe(
    String Function(AppDateFormat format) render,
    String Function() noFormat,
  ) {
    final format = dateFormat;
    if (format == null) return noFormat();
    final localized = render(format);
    if (_isPdfTextSupported(localized)) return localized;
    return render(
      AppDateFormat(
        locale: 'en_US',
        use24HourFormat: format.use24HourFormat,
        now: format.now,
      ),
    );
  }

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
    final section = partySection(party, await _history(partyId));
    _ensurePdfTextIsSupported([section]);
    final bytes = await renderPdf(
      font: await _loadFont(),
      sections: [section],
      generatedAt: clock.now().toUtc().toIso8601String(),
      contents: false,
    );
    return ExportDocument('party-history.pdf', bytes);
  }

  /// Every party (ordered by name) with its full history, each starting on a
  /// new page, behind a short contents section (#52). A readable report only:
  /// it is not encrypted and cannot be imported.
  ///
  /// The text is prepared here (dates need the locale), and the PDF is laid
  /// out on a background isolate so a large ledger does not freeze the UI.
  Future<ExportDocument> exportLedgerPdf() async {
    final snapshot = await service.snapshot();
    final sections = ledgerSections(snapshot.parties, snapshot.interactions);
    _ensurePdfTextIsSupported(sections, nameParties: true);
    final generatedAt = snapshot.generatedAt.toUtc().toIso8601String();
    final bytes = await _renderOffThread(
      await _loadFont(),
      sections,
      generatedAt,
    );
    return ExportDocument(
      'my-little-crm-report-${generatedAt.substring(0, 10)}.pdf',
      bytes,
    );
  }

  // Static so the isolate closure captures only these arguments.
  static Future<Uint8List> _renderOffThread(
    ByteData font,
    List<PdfPartySection> sections,
    String generatedAt,
  ) => Isolate.run(
    () => renderPdf(
      font: font,
      sections: sections,
      generatedAt: generatedAt,
      contents: true,
    ),
    debugName: 'ledger-pdf',
  );

  /// One section per party, ordered by name; each history oldest first.
  @visibleForTesting
  List<PdfPartySection> ledgerSections(
    List<Party> parties,
    List<Interaction> interactions,
  ) {
    final byParty = <PartyId, List<Interaction>>{};
    for (final item in interactions) {
      (byParty[item.partyId] ??= []).add(item);
    }
    final ordered = parties.toList()
      ..sort((a, b) {
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return byName != 0 ? byName : a.name.compareTo(b.name);
      });
    return [
      for (final party in ordered)
        partySection(
          party,
          (byParty[party.id] ?? [])
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp)),
        ),
    ];
  }

  /// Most pages one party's history may fill before the export stops with a
  /// [PdfPageLimitException] instead of writing a truncated file.
  static const maxPagesPerParty = 10000;

  Future<ByteData> _loadFont() =>
      rootBundle.load('assets/fonts/NotoSans-Regular.ttf');

  /// The text of one party's history, exactly as the PDF prints it.
  @visibleForTesting
  PdfPartySection partySection(
    Party party,
    List<Interaction> items,
  ) => PdfPartySection(party.name, [
    for (final i in items)
      PdfEntry(
        heading: '${pdfDateTime(i.timestamp)} - ${i.method.name}',
        summary: i.summary,
        contact: i.contactName == null ? null : 'Contact: ${i.contactName}',
        references: i.referenceNumbers.isEmpty
            ? null
            : 'References: ${i.referenceNumbers.join(', ')}',
        commitment: i.commitment == null ? null : 'Commitment: ${i.commitment}',
        followUp: i.followUp == null
            ? null
            : 'Follow-up: ${i.followUp!.hasTime ? pdfDateTime(i.followUp!.dueAt) : pdfDate(i.followUp!.dueAt)} (${i.followUp!.status.name})',
        record:
            'Record: ${i.id}\nCreated: ${i.createdAt.toUtc().toIso8601String()}',
      ),
  ]);

  /// Lays out [sections] as a PDF. Pure Dart, so it can run on an isolate.
  ///
  /// With [contents], a contents section comes first and links to each
  /// party. Every party is its own [pw.MultiPage], so it starts on a new page
  /// and [maxPagesPerParty] limits one party's history, not the ledger.
  @visibleForTesting
  static Future<Uint8List> renderPdf({
    required ByteData font,
    required List<PdfPartySection> sections,
    required String generatedAt,
    required bool contents,
    int maxPages = maxPagesPerParty,
  }) async {
    final ttf = pw.Font.ttf(font);
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: ttf, bold: ttf),
    );
    if (contents) {
      document.addPage(
        pw.MultiPage(
          maxPages: maxPages,
          build: (_) => contentsWidgets(sections, generatedAt),
        ),
      );
    }
    // pdf's own MultiPage.maxPages is only checked in debug builds (inside an
    // assert) and only for one widget, so count each party's pages here.
    int pageCount() => document.document.pdfPageList.pages.length;
    for (final (index, section) in sections.indexed) {
      final before = pageCount();
      try {
        document.addPage(
          pw.MultiPage(
            maxPages: maxPages,
            build: (_) => sectionWidgets(
              section,
              generatedAt,
              anchor: contents ? 'party-$index' : null,
            ),
          ),
        );
      } on PdfTooBigPageException {
        throw PdfPageLimitException(section.name, maxPages);
      }
      if (pageCount() - before > maxPages) {
        throw PdfPageLimitException(section.name, maxPages);
      }
    }
    return document.save();
  }

  static List<pw.Widget> contentsWidgets(
    List<PdfPartySection> sections,
    String generatedAt,
  ) {
    final total = sections.fold(0, (sum, s) => sum + s.entries.length);
    return [
      pw.Header(level: 0, text: 'My Little CRM - ledger report'),
      pw.Paragraph(text: 'Generated $generatedAt'),
      pw.Paragraph(text: reportNotice),
      pw.Paragraph(
        text:
            '${sections.length} ${sections.length == 1 ? 'party' : 'parties'}, '
            '$total ${total == 1 ? 'interaction' : 'interactions'}',
      ),
      pw.Header(level: 1, text: 'Contents'),
      for (final (index, section) in sections.indexed)
        pw.Link(
          destination: 'party-$index',
          child: pw.Text(
            '${section.name} (${section.entries.length})',
            overflow: pw.TextOverflow.span,
          ),
        ),
    ];
  }

  /// The per-party layout shared by the party and ledger exports.
  static List<pw.Widget> sectionWidgets(
    PdfPartySection section,
    String generatedAt, {
    String? anchor,
  }) => [
    anchor == null
        ? pw.Header(level: 0, text: section.name)
        : pw.Header(
            level: 0,
            title: section.name,
            child: pw.Anchor(name: anchor, child: pw.Text(section.name)),
          ),
    pw.Paragraph(text: 'Generated $generatedAt'),
    if (section.entries.isEmpty)
      pw.Paragraph(text: 'No interactions recorded.'),
    for (final e in section.entries) ...[
      pw.Header(level: 1, text: e.heading),
      pw.Text(e.summary, overflow: pw.TextOverflow.span),
      for (final line in [e.contact, e.references, e.commitment])
        if (line != null) pw.Text(line, overflow: pw.TextOverflow.span),
      if (e.followUp != null) pw.Paragraph(text: e.followUp),
      pw.Paragraph(text: e.record),
    ],
  ];

  /// Shown before a ledger PDF export and printed on its first page.
  static const reportNotice =
      'This PDF is a readable report. It is NOT encrypted: anyone who can '
      'open the file can read your records. It cannot be imported; only the '
      'JSON "Export everything" file can be imported.';

  Future<Party> _party(PartyId id) async =>
      await service.parties.get(id) ??
      (throw StateError('Party no longer exists'));
  Future<List<Interaction>> _history(PartyId id) async =>
      (await service.partyHistory(id)).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  /// Refuses the export when the bundled font cannot draw some text. With
  /// [nameParties] (the whole ledger), the message names the affected parties
  /// so the user can find the record (#52).
  void _ensurePdfTextIsSupported(
    List<PdfPartySection> sections, {
    bool nameParties = false,
  }) {
    final affected = [
      for (final s in sections)
        if (!s.text.every(_isPdfTextSupported)) s.name,
    ];
    if (affected.isEmpty) return;
    if (!nameParties) throw StateError(unsupportedPdfTextMessage);
    const shown = 3;
    final names = affected.take(shown).map((n) => '"$n"').join(', ');
    final more = affected.length > shown
        ? ' and ${affected.length - shown} more'
        : '';
    throw StateError(
      '$unsupportedPdfTextMessage Affected '
      '${affected.length == 1 ? 'party' : 'parties'}: $names$more.',
    );
  }

  static bool _isPdfTextSupported(String value) =>
      value.runes.every(_isPdfCodePointSupported);

  static bool _isPdfCodePointSupported(int codePoint) =>
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

/// One party's history as the PDF prints it.
class PdfPartySection {
  const PdfPartySection(this.name, this.entries);
  final String name;
  final List<PdfEntry> entries;

  /// Every string drawn for this party, for the glyph check.
  Iterable<String> get text sync* {
    yield name;
    for (final e in entries) {
      yield* e.lines;
    }
  }
}

/// One interaction as the PDF prints it; optional lines are null when absent.
class PdfEntry {
  const PdfEntry({
    required this.heading,
    required this.summary,
    required this.record,
    this.contact,
    this.references,
    this.commitment,
    this.followUp,
  });
  final String heading, summary, record;
  final String? contact, references, commitment, followUp;

  List<String> get lines => [
    heading,
    summary,
    ?contact,
    ?references,
    ?commitment,
    ?followUp,
    record,
  ];
}

/// One party's history needs more than [maxPages] pages, so the export
/// stopped rather than write a truncated file.
class PdfPageLimitException implements Exception {
  const PdfPageLimitException(this.partyName, this.maxPages);
  final String partyName;
  final int maxPages;

  String get message =>
      'The history of "$partyName" needs more than $maxPages PDF pages, so '
      'no file was saved. Choose JSON instead.';

  @override
  String toString() => message;
}
