// This is the entry point for the Firebase Functions
import tipperFunctions = require("./services/legacy_service");
import msgFunctionPrune =
    require("./services/messaging_service_prune_devicetokens");
import sendNotTippedReminders =
    require("./services/messaging_service_send_not_tipped_reminders");

exports.submitLegacyTips = tipperFunctions.submitLegacyTips;
exports.pruneTokens = msgFunctionPrune.pruneTokens;
exports.sendNotTippedReminders = sendNotTippedReminders.sendNotTippedReminders;
