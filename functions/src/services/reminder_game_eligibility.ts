export interface ReminderCompCutoffs {
  aflRegularCompEndDateUTC?: unknown;
  nrlRegularCompEndDateUTC?: unknown;
}

/**
 * Returns whether a game is eligible for reminders under its league cutoff.
 *
 * @param {string} gameKey Firebase game key prefixed with its league.
 * @param {string} gameStartTimeUTC Game kickoff timestamp.
 * @param {ReminderCompCutoffs} cutoffs Competition cutoffs by league.
 * @return {boolean} Whether reminders may be sent for the game.
 */
export function isReminderGameWithinCompCutoff(
  gameKey: string,
  gameStartTimeUTC: string,
  cutoffs: ReminderCompCutoffs,
): boolean {
  const league = gameKey.substring(0, 3).toLowerCase();
  const cutoffValue = league === "afl" ?
    cutoffs.aflRegularCompEndDateUTC :
    league === "nrl" ? cutoffs.nrlRegularCompEndDateUTC : null;

  if (typeof cutoffValue !== "string" || cutoffValue.trim() === "") {
    return true;
  }

  const gameStartMilliseconds = Date.parse(gameStartTimeUTC);
  const cutoffMilliseconds = Date.parse(cutoffValue);
  if (Number.isNaN(gameStartMilliseconds) ||
      Number.isNaN(cutoffMilliseconds)) {
    return true;
  }

  return gameStartMilliseconds <= cutoffMilliseconds;
}
