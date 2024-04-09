import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

// this function will send a reminder to all users who have not tipped
// for the current round
export const sendNotTippedReminders = functions.pubsub
  .schedule("every 3 hours").onRun(async () => {
    // grab the current comp id from firebase remote config
    // const remote = admin.remoteConfig();
    // Then in your cloud function we use it to fetch our remote config values.
    // const remoteConfigTemplate = await remote.getTemplate().catch((e) => {
    //   functions.logger.error("Error fetching remote config template", e);
    //   return;
    // });

    // const parameters = remoteConfigTemplate?.parameters;
    // const currentDAUComp = parameters?.currentDAUComp;
    // const defaultValue = currentDAUComp?.defaultValue as any;
    // const compId = defaultValue?.value;
    const compId = "-Nq1-KbsS7lX9C7-oeq6";

    // find all games in database /DAUCompsGames/[compId] that have a DateUtc
    // timestamp in a window that is between 2 hours from now and 5
    // hours from now. If there are no games exit processing
    const db = admin.database();
    const gamesRef = db.ref("DAUCompsGames/" + compId);
    const now = Date.now();
    const twoHoursFromNow = now + 2 * 60 * 60 * 1000;
    const fiveHoursFromNow = now + 5 * 60 * 60 * 1000;
    const snapshot = await gamesRef.orderByChild("DateUtc")
      .startAt(twoHoursFromNow).endAt(fiveHoursFromNow).once("value");
    const games = snapshot.val();
    if (!games) {
      functions.logger.log(
        "No games found starting in the next 2-5 hours in comp id: " + compId);
      functions.logger.log("window starts at: " + twoHoursFromNow);
      functions.logger.log("window ends at: " + fiveHoursFromNow);
      return;
    }

    // get the comp id for the games found
    const compIds = Object.keys(games);
    functions.logger.log(
      `Found ${compIds.length} games starting in the next 2-5 hours`);
    functions.logger.log(`Comp ids: ${compIds.join(", ")}`);

    // for the games found, loop through all tippers
    //  and check if the tipper has tipped
    // if they have not, send a reminder
    //
    // tips are stored in database location
    // /AllTips/[comp id]/[tipper id]/[game id]
    // The [comp id] is in the path of the game i/e.
    // /DAUCompsGames/[comp id]/[game id]
    // For the [tipper id] we can get all tipper ids from /AllTippers
    // ignore tippers where their [compsParticipatedIn] list
    // does not contain the [comp id]

    // const tipsRef = db.ref("AllTips");
    // const dauCompsGamesRef = db.ref("DAUCompsGames");
    // const allTippersRef = db.ref("AllTippers");
    // Get a reference to the tokens in the database
    const tokensRef = db.ref("AllTippersTokens");

    // Get all tokens
    const snapshotTokens = await tokensRef.once("value");
    const tokens = snapshotTokens.val();
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
    // const notTippedTokensPromises = notTippedTokens.map((token) => {
    //   functions.logger.log(
    //     `Sending reminder to token ending in: ..${token.slice(-5)}`);
    //   return sendReminderMessage(token);
    // });

    // await Promise.all(notTippedTokensPromises);
    // const msg = `Processed reminders for ${notTippedTokens.length} devices`;
    // functions.logger.log(msg);
    // return notTippedTokens.length;
  });

/**
 * Sends a reminder message to a specific token path.
 *
 * @param {string} token - FCM token to send the reminder to.
 * @return {Promise<void>}
 *   - A Promise that resolves when the reminder has been sent.
 */
// async function sendReminderMessage(token: string): Promise<void> {
//   // Send a reminder message to the user
//   const message = {
//     notification: {
//       title: "TEST!! Don't forget to tip!",
//       body: "This is a test - ignore!",
//     },
//     token: token,
//   };

//   try {
//     await admin.messaging().send(message);
//   } catch (error) {
//     if ((error as Error).message === "Requested entity was not found.") {
//       functions.logger.log(
//         `Token ending in: ${token.slice(-5)}, not valid or does not exist.`);
//       // Handle the error here, e.g., remove the token from your database
//     } else {
//       // If the error is something else, you might want to re-throw it
//       throw error;
//     }
//   }
// }
