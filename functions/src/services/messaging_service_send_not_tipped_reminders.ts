import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

// this function will send a reminder to all users who have not tipped
// for the current round
export const sendNotTippedReminders = functions.pubsub
  .schedule("every 24 hours").onRun(async () => {
    // Get a reference to the tokens in the database
    const db = admin.database();
    const tokensRef = db.ref("AllTippersTokens");

    // Get all tokens
    const snapshot = await tokensRef.once("value");
    const tokens = snapshot.val();
    const notTippedTokens: string[] = [];

    // Iterate through all tokens

    for (const tipperId in tokens) {
      if (Object.prototype.hasOwnProperty.call(tokens, tipperId)) {
        const tipperTokens = tokens[tipperId];
        for (const tokenId in tipperTokens) {
          if (Object.prototype.hasOwnProperty.call(tipperTokens, tokenId)) {
            notTippedTokens.push(`${tokenId}`);
          }
        }
      }
    }

    // Send reminders to all users who have not tipped
    const notTippedTokensPromises = notTippedTokens.map((token) => {
      functions.logger.log(
        `Sending reminder to token ending in: ..${token.slice(-5)}`);
      return sendReminderMessage(token);
    });

    await Promise.all(notTippedTokensPromises);
    const msg = `Processed reminders for ${notTippedTokens.length} devices`;
    functions.logger.log(msg);
    return notTippedTokens.length;
  });

/**
 * Sends a reminder message to a specific token path.
 *
 * @param {string} token - FCM token to send the reminder to.
 * @return {Promise<void>}
 *   - A Promise that resolves when the reminder has been sent.
 */
async function sendReminderMessage(token: string): Promise<void> {
  // Send a reminder message to the user
  const message = {
    notification: {
      title: "TEST!! Don't forget to tip!",
      body: "This is a test - ignore!",
    },
    token: token,
  };

  try {
    await admin.messaging().send(message);
  } catch (error) {
    if ((error as Error).message === "Requested entity was not found.") {
      functions.logger.log(
        `Token ending in: ${token.slice(-5)}, not valid or does not exist.`);
      // Handle the error here, e.g., remove the token from your database
    } else {
      // If the error is something else, you might want to re-throw it
      throw error;
    }
  }
}
