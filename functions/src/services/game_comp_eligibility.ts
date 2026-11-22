export interface GameCompCutoffs {
  aflRegularCompEndDateUTC?: unknown;
  nrlRegularCompEndDateUTC?: unknown;
}

const TIME_ZONE_SUFFIX = /(?:Z|[+-]\d{2}(?::?\d{2})?)$/i;

/**
 * Parses Firebase timestamps as UTC when their stored value has no zone.
 *
 * @param {string} value Firebase timestamp string.
 * @return {number} Milliseconds since the Unix epoch, or NaN when invalid.
 */
export function parseFirebaseUtcTimestamp(value: string): number {
  const trimmed = value.trim();
  const normalized = TIME_ZONE_SUFFIX.test(trimmed) ? trimmed : `${trimmed}Z`;
  return Date.parse(normalized);
}

/**
 * Returns whether a game is within its league's regular-comp cutoff.
 *
 * @param {string} gameKey Firebase game key prefixed with its league.
 * @param {string} gameStartTimeUTC Game kickoff timestamp.
 * @param {GameCompCutoffs} cutoffs Competition cutoffs by league.
 * @return {boolean} Whether the game is within its competition cutoff.
 */
export function isGameWithinCompCutoff(
  gameKey: string,
  gameStartTimeUTC: string,
  cutoffs: GameCompCutoffs,
): boolean {
  const league = gameKey.substring(0, 3).toLowerCase();
  const cutoffValue = league === "afl" ?
    cutoffs.aflRegularCompEndDateUTC :
    league === "nrl" ? cutoffs.nrlRegularCompEndDateUTC : null;

  if (typeof cutoffValue !== "string" || cutoffValue.trim() === "") {
    return true;
  }

  const gameStartMilliseconds = parseFirebaseUtcTimestamp(gameStartTimeUTC);
  const cutoffMilliseconds = parseFirebaseUtcTimestamp(cutoffValue);
  if (Number.isNaN(gameStartMilliseconds) ||
      Number.isNaN(cutoffMilliseconds)) {
    return true;
  }

  return gameStartMilliseconds <= cutoffMilliseconds;
}
