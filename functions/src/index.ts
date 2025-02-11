// This is the entry point for the Firebase Functions
import msgFunctionNotTipped =
    require("./services/messaging_service_send_not_tipped_reminders");

import * as admin from "firebase-admin";

exports.sendReminders = msgFunctionNotTipped.sendHourlyReminders;

admin.initializeApp();

if (process.env.FUNCTIONS_EMULATOR) {
  admin.database().useEmulator("localhost", 8000);
}


