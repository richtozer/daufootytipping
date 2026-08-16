// This is the entry point for the Firebase Functions
import {sendHourlyReminders} from
  "./services/messaging_service_send_not_tipped_reminders";
import {
  liveScoreWrittenBackendScoring,
  officialScoreWrittenBackendScoring,
  tipWrittenBackendScoring,
} from "./backend_scoring";
import {
  scheduledFixtureDownload as scheduledFixtureDownloadForwarder,
} from "./fixture_download_scheduler";
import {
  kickoffOutstandingTipsAppBadge,
  reconcileOutstandingTipsAppBadge,
  tipperTokenCreatedAppBadge,
  tipperWrittenAppBadge,
  tipWrittenAppBadge,
} from "./app_badge";

import {initializeApp} from "firebase-admin/app";
import {getDatabase} from "firebase-admin/database";

exports.sendReminders = sendHourlyReminders;
exports.tipWrittenBackendScoring = tipWrittenBackendScoring;
exports.officialScoreWrittenBackendScoring = officialScoreWrittenBackendScoring;
exports.liveScoreWrittenBackendScoring = liveScoreWrittenBackendScoring;
exports.scheduledFixtureDownload = scheduledFixtureDownloadForwarder;
exports.tipWrittenAppBadge = tipWrittenAppBadge;
exports.tipperWrittenAppBadge = tipperWrittenAppBadge;
exports.tipperTokenCreatedAppBadge = tipperTokenCreatedAppBadge;
exports.kickoffOutstandingTipsAppBadge = kickoffOutstandingTipsAppBadge;
exports.reconcileOutstandingTipsAppBadge = reconcileOutstandingTipsAppBadge;

initializeApp();

if (process.env.FUNCTIONS_EMULATOR) {
  getDatabase().useEmulator("localhost", 8000);
}
