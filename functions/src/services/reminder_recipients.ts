/**
 * The name a reminder greets a tipper by. It reads only the public `name`, so
 * it gives the same answer for a legacy record and for one whose private fields
 * have been moved to /TipperPrivate. A tipper with no usable record or name is
 * greeted by their id.
 * @param {unknown} tippers The value of /AllTippers, keyed by tipper id.
 * @param {string} tipperId The tipper to greet.
 * @return {string} The name to use in the reminder.
 */
export function reminderRecipientName(
  tippers: unknown,
  tipperId: string,
): string {
  if (typeof tippers !== "object" || tippers === null) return tipperId;
  const tipper = (tippers as Record<string, unknown>)[tipperId];
  if (typeof tipper !== "object" || tipper === null) return tipperId;
  const name = (tipper as Record<string, unknown>).name;
  return typeof name === "string" && name !== "" ? name : tipperId;
}
