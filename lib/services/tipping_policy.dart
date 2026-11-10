const String tipGracePeriodSecondsKey = 'tipGracePeriodSeconds';
const int defaultTipGracePeriodSeconds = 120;

/// Invalid or absent configuration uses the same two-minute default as R2 rules.
int parseTipGracePeriodSeconds(Object? value) =>
    value is num && value.isFinite && value >= 0 && value % 1 == 0
        ? value.toInt()
        : defaultTipGracePeriodSeconds;
