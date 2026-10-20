import assert from "node:assert/strict";
import test from "node:test";
import {reminderRecipientName} from "./reminder_recipients";

const legacy = {
  name: "Pat",
  photoURL: "https://example.com/pat.png",
  compsParticipatedIn: ["comp-1"],
  authuid: "auth-pat",
  tipperRole: "tipper",
  email: "pat@example.com",
  logon: "pat@example.com",
  isAnonymous: false,
  acctCreatedUTC: "2025-02-01T03:04:05.000Z",
  acctLoggedOnUTC: "2026-03-01T04:05:06.000Z",
};
const purged = {
  name: "Pat",
  photoURL: "https://example.com/pat.png",
  compsParticipatedIn: ["comp-1"],
};

test("the reminder greets a tipper by the same name before and after the purge", () => {
  assert.equal(reminderRecipientName({pat: legacy}, "pat"), "Pat");
  assert.equal(reminderRecipientName({pat: purged}, "pat"), "Pat");
});

test("a tipper with no record or no name is greeted by id", () => {
  assert.equal(reminderRecipientName({pat: purged}, "other"), "other");
  assert.equal(reminderRecipientName({pat: {}}, "pat"), "pat");
  assert.equal(reminderRecipientName({pat: {name: ""}}, "pat"), "pat");
  assert.equal(reminderRecipientName({pat: {name: 7}}, "pat"), "pat");
  assert.equal(reminderRecipientName({pat: "not a record"}, "pat"), "pat");
});

test("an empty or missing /AllTippers does not stop the reminders", () => {
  assert.equal(reminderRecipientName(null, "pat"), "pat");
  assert.equal(reminderRecipientName(undefined, "pat"), "pat");
});
