// This is the entry point for the Firebase Functions
import tipperFunctions = require("./services/legacy_service");
import msgFunctionPrune =
    require("./services/messaging_service_prune_devicetokens");
import msgFunctionNotTipped =
    require("./services/messaging_service_send_nottipped_reminders");

import * as admin from "firebase-admin";

exports.submitLegacyTips = tipperFunctions.submitLegacyTips;
exports.pruneTokens = msgFunctionPrune.pruneTokens;
exports.sendReminders = msgFunctionNotTipped.sendReminders;

//admin.initializeApp();

if (process.env.FUNCTIONS_EMULATOR) {
  admin.database().useEmulator("localhost", 8000);
}


