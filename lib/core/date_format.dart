import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'clock.dart';

/// The one place dates and times are turned into text (#38).
///
/// Uses the device locale for date order and month names, the device's
/// 12/24-hour preference for times, and relative labels ("Today",
/// "Yesterday", "Tomorrow") for nearby days. "Now" comes from the injectable
/// [Clock], so tests can check output at fixed times.
class AppDateFormat {
  AppDateFormat({
    required String locale,
    required this.use24HourFormat,
    required this.now,
  }) : locale = _supported(locale);

  final String locale;
  final bool use24HourFormat;
  final DateTime now;

  static bool _initialized = false;

  static String _supported(String locale) {
    if (!_initialized) {
      // The bundled locale data initializes synchronously.
      initializeDateFormatting();
      _initialized = true;
    }
    final canonical = Intl.canonicalizedLocale(locale);
    if (DateFormat.localeExists(canonical)) return canonical;
    final language = canonical.split('_').first;
    return DateFormat.localeExists(language) ? language : 'en_US';
  }

  /// The formatter for [context]: the nearest [DateFormatScope], or the device
  /// locale and system clock when there is none.
  static AppDateFormat of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<DateFormatScope>();
    final locale =
        scope?.locale ??
        WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag();
    return AppDateFormat(
      locale: locale,
      use24HourFormat:
          MediaQuery.maybeAlwaysUse24HourFormatOf(context) ?? false,
      now: (scope?.clock ?? const SystemClock()).now(),
    );
  }

  /// A time of day, e.g. "14:05" or "2:05 PM".
  String time(DateTime value) =>
      (use24HourFormat ? DateFormat.Hm(locale) : DateFormat.jm(locale)).format(
        value.toLocal(),
      );

  /// A calendar day: "Today", "Yesterday", "Tomorrow", a weekday and date in
  /// this year ("Tue, 17 Nov"), or a full date ("17 Nov 2025").
  String date(DateTime value) {
    final local = value.toLocal();
    final days = _dayDifference(local);
    if (days == 0) return 'Today';
    if (days == -1) return 'Yesterday';
    if (days == 1) return 'Tomorrow';
    final today = now.toLocal();
    return local.year == today.year
        ? DateFormat.MMMEd(locale).format(local)
        : DateFormat.yMMMd(locale).format(local);
  }

  /// A moment: "Today 14:05", "Yesterday 9:30 AM", "Tue, 17 Nov 14:05".
  String dateTime(DateTime value) => '${date(value)} ${time(value)}';

  /// A day with no relative wording, for documents read later (PDF reports).
  String fullDate(DateTime value) =>
      DateFormat.yMMMEd(locale).format(value.toLocal());

  /// A moment with no relative wording, e.g. "Tue, 17 Nov 2026 14:05".
  String fullDateTime(DateTime value) => '${fullDate(value)} ${time(value)}';

  int _dayDifference(DateTime local) {
    final today = now.toLocal();
    // Compare calendar days in UTC so daylight-saving changes cannot skew it.
    return DateTime.utc(
      local.year,
      local.month,
      local.day,
    ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
  }
}

/// Supplies the clock and an optional fixed locale to [AppDateFormat.of].
class DateFormatScope extends InheritedWidget {
  const DateFormatScope({
    super.key,
    required this.clock,
    this.locale,
    required super.child,
  });
  final Clock clock;

  /// A BCP-47 tag such as `en-AU`. Null uses the device locale.
  final String? locale;

  @override
  bool updateShouldNotify(DateFormatScope oldWidget) =>
      clock != oldWidget.clock || locale != oldWidget.locale;
}
