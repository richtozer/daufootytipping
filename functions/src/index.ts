// This is the entry point for the Firebase Functions
import tipperFunctions = require("./services/legacy_service");
import msgFunctionPrune =
    require("./services/messaging_service_prune_devicetokens");

exports.submitLegacyTips = tipperFunctions.submitLegacyTips;
exports.pruneTokens = msgFunctionPrune.pruneTokens;
