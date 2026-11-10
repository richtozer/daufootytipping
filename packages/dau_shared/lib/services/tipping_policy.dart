/// When tipping closes, shared by the app and the backend so that both read the
/// administrator's setting the same way the database rules do.
///
/// A tip may be made or changed until the game's kickoff plus a grace period, and
/// what other tippers chose stays hidden until then.
library;

/// Where the grace period is kept, under `/AppConfig`.
const String tipGracePeriodSecondsKey = 'tipGracePeriodSeconds';

/// Used when the setting is absent or not valid.
const int defaultTipGracePeriodSeconds = 120;

/// The longest grace period accepted. A larger value is treated as a mistake (a
/// typo in the console would otherwise keep tipping open, and everyone's tips
/// hidden, for hours), so it is ignored in favour of the default.
const int maxTipGracePeriodSeconds = 900;

/// The grace period in [value], or the default when it is not a whole number of
/// seconds from 0 to [maxTipGracePeriodSeconds]. The database rules apply the same
/// test.
int parseTipGracePeriodSeconds(Object? value) =>
    value is num &&
        value.isFinite &&
        value >= 0 &&
        value <= maxTipGracePeriodSeconds &&
        value % 1 == 0
    ? value.toInt()
    : defaultTipGracePeriodSeconds;

/// The moment tipping closes for a game that kicks off at [kickoff].
DateTime tipDeadlineFor(DateTime kickoff, int graceSeconds) =>
    kickoff.add(Duration(seconds: graceSeconds));

/// Whether tipping has closed at [now] for a game that kicks off at [kickoff].
bool tippingHasClosed(DateTime kickoff, DateTime now, int graceSeconds) =>
    !now.isBefore(tipDeadlineFor(kickoff, graceSeconds));
