import * as admin from "firebase-admin";
//import * as functions from "firebase-functions";

/**
 * Sends reminders.
 * This function sends Firebase Cloud Messaging notifications
 * to tippers that have registered tokens and have not yet tipped
 * within 3 hours of game start time
 */
//  export const sendReminders = functions.pubsub
//    .schedule("every 1 hour").onRun(async () => {
  export async function sendReminders() {
    const now = admin.firestore.Timestamp.now();
    const twoHoursFromNow = now.toMillis() + 2 * 60 * 60 * 1000;
    const threeHoursFromNow = now.toMillis() + 3 * 60 * 60 * 1000;

    const gamesRef = admin.database()
      .ref("/DAUCompsGames/[currentDAUComp key from above]/…");
    const gamesSnapshot = await gamesRef
      .orderByChild("DateUtc")
      .startAt(twoHoursFromNow)
      .endAt(threeHoursFromNow)
      .once("value");

    if (!gamesSnapshot.exists()) {
      return null;
    }

    const games = gamesSnapshot.val();
    const gameKeys = Object.keys(games);

    const tokensRef = admin.database().ref("/AllTipperTokens");
    const tokensSnapshot = await tokensRef.once("value");
    const tippers = tokensSnapshot.val();

    const currentDAUCompRef = admin.database().ref("/AppConfig/currentDAUComp");
    const currentDAUCompSnapshot = await currentDAUCompRef.once("value");
    const currentDAUComp = currentDAUCompSnapshot.val();

    const reminders = [];

    for (const tipperId in tippers) {
      if (Object.prototype.hasOwnProperty.call(tippers, tipperId)) {
        const tipperRef = admin.database().ref(`/AllTippers/${tipperId}`);
        const tipperSnapshot = await tipperRef.once("value");
        const tipper = tipperSnapshot.val();

        if (!tipper.active) {
          continue;
        }

        for (const gameKey of gameKeys) {
          const tipRef = admin.database()
            .ref(`/AllTips/${currentDAUComp}/${tipperId}/${gameKey}`);
          const tipSnapshot = await tipRef.once("value");

          if (!tipSnapshot.exists()) {
            reminders.push(tipperId);
            break;
          }
        }
      }
    }

    for (const tipperId of reminders) {
      const message = {
        notification: {
          title: "TEST!! Don't forget to tip!",
          body: "This is a test - ignore!",
        },
        token: tipperId,
      };

      await admin.messaging().send(message);
    }

    return null;
  };
