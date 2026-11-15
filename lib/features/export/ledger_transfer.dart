import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/date_format.dart';
import '../../domain/crm_service.dart';
import '../../domain/ledger.dart';
import 'history_export_service.dart';

/// "Export everything" and its matching import (#37): a stopgap for moving to
/// a new device until encrypted backup arrives.
class LedgerTransfer {
  const LedgerTransfer(this.service);
  final CrmService service;

  static const notEncryptedWarning =
      'The file contains every party and interaction as plain, readable '
      'JSON. It is NOT encrypted: anyone who can open the file can read '
      'your records. Keep it somewhere you trust.';

  Future<ExportedLedger> build() async {
    final snapshot = await service.snapshot();
    final day = snapshot.generatedAt.toUtc().toIso8601String().substring(0, 10);
    return ExportedLedger(
      'my-little-crm-export-$day.json',
      Uint8List.fromList(utf8.encode(snapshot.toJson())),
      parties: snapshot.parties.length,
      interactions: snapshot.interactions.length,
    );
  }

  Future<void> exportEverything(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.lock_open_outlined),
        title: const Text('Export everything?'),
        content: const Text(notEncryptedWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Export unencrypted file'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await build();
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Save unencrypted export',
        fileName: file.name,
        bytes: file.bytes,
        mimeType: 'application/json',
      );
      if (saved != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Exported ${file.parties} parties and '
              '${file.interactions} interactions (not encrypted)',
            ),
          ),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not export. Please try again.')),
      );
    }
  }

  /// "Export everything" as a readable PDF report (#52). It is not encrypted
  /// and cannot be imported; only the JSON export can.
  Future<void> exportEverythingPdf(BuildContext context) async {
    final exporter = HistoryExportService(
      service,
      clock: service.clock,
      dateFormat: AppDateFormat.of(context),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.picture_as_pdf_outlined),
        title: const Text('Export everything as PDF?'),
        content: const Text(HistoryExportService.reportNotice),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Create PDF report'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    void say(String text) =>
        messenger.showSnackBar(SnackBar(content: Text(text)));
    // A large ledger takes a while; the layout itself runs off the UI thread.
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 24),
                Expanded(child: Text('Creating PDF report…')),
              ],
            ),
          ),
        ),
      ),
    );
    ExportDocument? file;
    try {
      file = await exporter.exportLedgerPdf();
    } on StateError catch (error) {
      say(error.message);
    } on PdfPageLimitException catch (error) {
      say(error.message);
    } catch (_) {
      say('Could not create the PDF. Please try again.');
    } finally {
      navigator.pop();
    }
    if (file == null) return;
    try {
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Save PDF report',
        fileName: file.name,
        bytes: file.bytes,
        mimeType: 'application/pdf',
      );
      if (saved != null) {
        say('Saved PDF report (not encrypted, not importable)');
      }
    } catch (_) {
      say('Could not save the PDF. Please try again.');
    }
  }

  Future<void> importExport(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    void say(String text) =>
        messenger.showSnackBar(SnackBar(content: Text(text)));
    try {
      if ((await service.parties.list()).isNotEmpty) {
        say(CrmService.ledgerNotEmptyMessage);
        return;
      }
      final picked = await FilePicker.pickFile(
        dialogTitle: 'Choose an "Export everything" file',
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final ledger = LedgerSnapshot.fromJson(utf8.decode(bytes));
      if (!context.mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Import this export?'),
          content: Text(
            'Add ${ledger.parties.length} parties and '
            '${ledger.interactions.length} interactions to this empty ledger?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Import'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      await service.importLedger(ledger);
      say('Imported ${ledger.interactions.length} interactions');
    } on FormatException catch (error) {
      say(error.message);
    } on StateError catch (error) {
      say(
        error.message == CrmService.ledgerNotEmptyMessage
            ? error.message
            : 'Could not import. Please try again.',
      );
    } catch (_) {
      say('Could not import. Please try again.');
    }
  }
}

class ExportedLedger {
  const ExportedLedger(
    this.name,
    this.bytes, {
    required this.parties,
    required this.interactions,
  });
  final String name;
  final Uint8List bytes;
  final int parties;
  final int interactions;
}
