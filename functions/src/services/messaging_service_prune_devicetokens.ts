import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

// 30 days in milliseconds for production
// const EXPIRATION_TIME = 30 * 24 * 60 * 60 * 1000;

// 1 hour for testing
const EXPIRATION_TIME = 60 * 60 * 1000;

// Firebase function to prune device tokens
// that are older than the expiration time
export const pruneTokens = functions.pubsub
  .schedule("every 24 hours").onRun(async () => {
    // Get all tippers
    const tippersSnapshot = await admin
      .database().ref("AllTippers").once("value");
    const tippers = tippersSnapshot.val();

    const msg = `Cheching device tokens for
     ${Object.keys(tippers).length} tippers`;
    functions.logger.info(msg);

    // Iterate over each tipper
    for (const tipperKey in tippers) {
      if (Object.prototype.hasOwnProperty.call(tippers, tipperKey)) {
        const tipper = tippers[tipperKey];

        // Check if the tipper has any device tokens
        if (tipper.deviceTokens) {
          // Filter out any device tokens that
          // are older than the expiration time
          const prunedDeviceTokens = tipper.deviceTokens.filter((token:
            { timestamp: string | number | Date; }) => {
            // Ensure timestamp is a string before calling split
            if (typeof token.timestamp === "string") {
              const timestampWithoutFractionalSeconds = token.timestamp
                .split(".")[0];
              const tokenTimestamp = new Date(timestampWithoutFractionalSeconds)
                .getTime();
              return Date.now() - tokenTimestamp < EXPIRATION_TIME;
            } else {
              throw new Error("Timestamp is not a string");
            }
          });

          // If the pruned device tokens are different then the original
          // device tokens, update the tipper's device tokens in the database
          if (prunedDeviceTokens.length !== tipper.deviceTokens.length) {
            await admin.database().ref(`AllTippers/${tipperKey}/deviceTokens`)
              .set(prunedDeviceTokens);
            const msg = `Pruned ${tipper.deviceTokens.length -
              prunedDeviceTokens.length} device tokens for tipper ${tipperKey}`;
            functions.logger.info(msg);
          } else {
            const msg = `No device tokens to prune for tipper ${tipperKey}`;
            functions.logger.info(msg);
          }
        }
      }
    }
  });
