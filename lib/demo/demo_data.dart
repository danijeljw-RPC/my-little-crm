import 'package:uuid/uuid.dart';

import '../domain/crm_service.dart';
import '../domain/ledger.dart';
import '../domain/models.dart';

/// Loads realistic, fictional sample records into an empty ledger (#30).
///
/// Dates are relative to the service clock, so the follow-ups always show a
/// mix of overdue, due today, upcoming and completed whenever the demo opens.
Future<void> seedDemoLedger(CrmService service) =>
    service.importLedger(demoLedger(service.clock.now()));

LedgerSnapshot demoLedger(DateTime now) {
  const uuid = Uuid();
  final local = now.toLocal();
  final today = DateTime(local.year, local.month, local.day);
  DateTime daysAgo(int days, int hour, [int minute = 0]) =>
      DateTime(today.year, today.month, today.day - days, hour, minute).toUtc();
  DateTime day(int offset) =>
      DateTime(today.year, today.month, today.day + offset).toUtc();
  DateTime at(int offset, int hour, [int minute = 0]) => DateTime(
    today.year,
    today.month,
    today.day + offset,
    hour,
    minute,
  ).toUtc();

  final parties = <String, Party>{
    for (final name in [
      'Harbourside Bank',
      'Northwind Energy',
      'Brightline Mobile',
      'Kestrel Home Insurance',
      'Maple Street Dental',
      'Riverbend City Council',
      'Oakridge Property Management',
      'Summit Internet',
    ])
      name: Party(id: uuid.v4(), name: name),
  };

  final interactions = <Interaction>[];
  void add(
    String party,
    DateTime when,
    String summary, {
    CommunicationMethod method = CommunicationMethod.phone,
    String? contact,
    List<String> references = const [],
    String? commitment,
    FollowUp? followUp,
  }) => interactions.add(
    Interaction(
      id: uuid.v4(),
      partyId: parties[party]!.id,
      summary: summary,
      timestamp: when,
      createdAt: when,
      method: method,
      contactName: contact,
      referenceNumbers: references,
      commitment: commitment,
      followUp: followUp,
    ),
  );

  // Harbourside Bank: a disputed card charge, still open.
  add(
    'Harbourside Bank',
    daysAgo(21, 9, 40),
    'Reported an unrecognised card charge of \$84.20 from "QPX Online". '
        'Card frozen while they investigate.',
    contact: 'Priya (fraud team)',
    references: ['DSP-448210'],
    commitment: 'Provisional credit within 5 business days',
  );
  add(
    'Harbourside Bank',
    daysAgo(14, 11, 5),
    'Provisional credit has not appeared. Escalated to a supervisor.',
    contact: 'Marcus',
    references: ['DSP-448210', 'ESC-90311'],
    commitment: 'Supervisor to call back with an outcome',
    followUp: FollowUp(dueAt: day(-3)),
  );
  add(
    'Harbourside Bank',
    daysAgo(40, 15, 30),
    'Asked for the home loan statement for the tax return.',
    method: CommunicationMethod.email,
    references: ['HL-2207-118'],
    followUp: FollowUp(dueAt: day(-30), status: FollowUpStatus.completed),
  );

  // Northwind Energy: a billing error with a promised refund.
  add(
    'Northwind Energy',
    daysAgo(10, 14, 15),
    'Bill estimated at 1,240 kWh instead of the actual meter read of 610 '
        'kWh. Sent a photo of the meter.',
    method: CommunicationMethod.email,
    contact: 'Billing team',
    references: ['ACC 5502 1187', 'CASE-77120'],
    commitment: 'Re-issue the bill from the actual read',
  );
  add(
    'Northwind Energy',
    daysAgo(3, 10, 20),
    'Bill re-issued correctly. Refund of \$131.55 approved for the '
        'overpayment.',
    contact: 'Hannah',
    references: ['CASE-77120'],
    commitment: 'Refund to the bank account within 10 days',
    followUp: FollowUp(dueAt: day(7)),
  );

  // Brightline Mobile: plan change and a callback booked for today.
  add(
    'Brightline Mobile',
    daysAgo(6, 17, 45),
    'Chatted about moving to the 40 GB plan. They offered 3 months at half '
        'price if I recontract for 12 months.',
    method: CommunicationMethod.chat,
    contact: 'Leo (online chat)',
    references: ['CHAT-3392045'],
    commitment: 'Retention team to call with the written offer',
    followUp: FollowUp(dueAt: at(0, 16, 30), hasTime: true),
  );
  add(
    'Brightline Mobile',
    daysAgo(32, 12),
    'Roaming charges on last bill reversed as a goodwill gesture.',
    method: CommunicationMethod.sms,
    references: ['INV-0098812'],
  );

  // Kestrel Home Insurance: a storm claim.
  add(
    'Kestrel Home Insurance',
    daysAgo(18, 8, 55),
    'Lodged a claim for storm damage to the back fence. Uploaded six '
        'photos and the quote from the fencer.',
    contact: 'Claims line',
    references: ['CLM-2025-66410'],
    commitment: 'Assessor to visit within 10 business days',
  );
  add(
    'Kestrel Home Insurance',
    daysAgo(8, 13, 10),
    'Assessor visited. Claim approved less the \$500 excess.',
    method: CommunicationMethod.letter,
    contact: 'Daniel Okafor (assessor)',
    references: ['CLM-2025-66410'],
    commitment: 'Payment of \$2,180 to be sent once the invoice is received',
    followUp: FollowUp(dueAt: day(-1)),
  );

  // Maple Street Dental: appointment and a pre-approval.
  add(
    'Maple Street Dental',
    daysAgo(4, 9, 15),
    'Booked a check-up and clean. Asked them to send the crown quote to '
        'the health fund for pre-approval.',
    contact: 'Reception (Sofia)',
    commitment: 'Practice will email the item numbers',
    followUp: FollowUp(dueAt: at(2, 10, 0), hasTime: true),
  );

  // Riverbend City Council: rates and a hard-rubbish booking.
  add(
    'Riverbend City Council',
    daysAgo(25, 11, 30),
    'Asked about the rates instalment plan. Signed up for quarterly '
        'direct debit.',
    references: ['RATES 004-2291-7'],
  );
  add(
    'Riverbend City Council',
    daysAgo(2, 15, 0),
    'Booked a hard-rubbish collection for the old sofa and bookcase.',
    method: CommunicationMethod.other,
    references: ['HR-58831'],
    commitment: 'Items out on the kerb the night before',
    followUp: FollowUp(dueAt: day(12)),
  );

  // Oakridge Property Management: a maintenance request.
  add(
    'Oakridge Property Management',
    daysAgo(12, 18, 5),
    'Reported the leaking kitchen tap and the dishwasher not draining.',
    method: CommunicationMethod.email,
    contact: 'Jess Turner (property manager)',
    references: ['MR-1044'],
    commitment: 'Plumber to be booked this week',
  );
  add(
    'Oakridge Property Management',
    daysAgo(5, 9, 0),
    'Plumber fixed the tap. Dishwasher needs a part on order.',
    contact: 'Jess Turner',
    references: ['MR-1044'],
    followUp: FollowUp(dueAt: day(4)),
  );
  add(
    'Oakridge Property Management',
    daysAgo(55, 10, 0),
    'Lease renewal signed for another 12 months; rent unchanged.',
    method: CommunicationMethod.letter,
    references: ['LEASE-17B'],
    followUp: FollowUp(dueAt: day(-50), status: FollowUpStatus.completed),
  );

  // Summit Internet: an outage credit.
  add(
    'Summit Internet',
    daysAgo(1, 20, 10),
    'Internet down for most of the weekend. Fault confirmed in the street '
        'cabinet; asked for a credit for the outage.',
    contact: 'Ahmed (tech support)',
    references: ['FLT-662019'],
    commitment: 'Credit of two days applied to the next bill',
    followUp: FollowUp(dueAt: day(20)),
  );

  return LedgerSnapshot(
    generatedAt: now,
    parties: parties.values.toList(),
    interactions: interactions,
  );
}
