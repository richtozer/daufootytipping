import {onSchedule} from "firebase-functions/v2/scheduler";
import {database} from "firebase-admin";
import {getMessaging} from "firebase-admin/messaging";

export const sendHourlyReminders =
  onSchedule("every hour", async () => {
    const zeroHoursFromNow = new Date(new Date()
      .getTime()).toISOString();
    const threeHoursFromNow = new Date(new Date()
      .getTime() + 3 * 60 * 60 * 1000).toISOString();

    const compRef = database().ref("/AppConfig/currentDAUComp");
    const compSnapshot = await compRef.once("value");
    const compDBKey = compSnapshot.val();

    // get all the short team names from /Teams
    const teamsRef = database().ref("/Teams");
    const teamsSnapshot = await teamsRef.once("value");
    const teams = teamsSnapshot.val();

    const gamesRef = database().ref(`/DAUCompsGames/${compDBKey}`);
    const gamesSnapshot = await gamesRef
      .orderByChild("DateUtc").startAt(zeroHoursFromNow)
      .endAt(threeHoursFromNow).once("value");

    if (!gamesSnapshot.exists()) {
      console.log("No games found in the specified time range. Ending processing.");
      // terminate the function early
      return;
    }

    const games = gamesSnapshot.val();
    const gameKeys = Object.keys(games);

    const tokensRef = database().ref("/AllTippersTokens");
    const tokensSnapshot = await tokensRef.once("value");
    const tippersWithTokens = tokensSnapshot.val();

    const reminders: Reminder[] = [];

    for (const tipperId in tippersWithTokens) {
      if (Object.prototype.hasOwnProperty.call(tippersWithTokens, tipperId)) {
        const tokens = tippersWithTokens[tipperId];

        // check if this tipper with a token has not tipped upcoming games
        for (const gameKey of gameKeys) {
          const tipRef = database()
            .ref(`/AllTips/${compDBKey}/${tipperId}/${gameKey}`);
          const tipSnapshot = await tipRef.once("value");

          if (!tipSnapshot.exists()) {
            // log tipper has not tipped game
            console.log(`Tipper ${tipperId} has not tipped game ${gameKey}.`);
            // send a reminder to all their tokens
            for (const tokenKey in tokens) {
              if (Object.prototype.hasOwnProperty.call(tokens, tokenKey)) {
                // use the short team names to get the team names
                // use team key [league]-[long team name] to find
                // the team record. use the team record name element
                // for the short team name

                const homeTeamLongName = games[gameKey].HomeTeam;
                const awayTeamLongName = games[gameKey].AwayTeam;

                const shortHomeTeam = teams[`${gameKey.substring(0, 3)
                }-${homeTeamLongName}`]?.name || homeTeamLongName;
                const shortAwayTeam = teams[`${gameKey.substring(0, 3)
                }-${awayTeamLongName}`]?.name || awayTeamLongName;

                reminders.push({
                  tipperId: tipperId,
                  token: tokenKey,
                  homeTeam: shortHomeTeam,
                  awayTeam: shortAwayTeam,
                });
              }
            }
          }
        }
      }
    }

    if (reminders.length > 0) {
      console.log("Sending reminders to: ", reminders.length, "devices.");
      for (const reminder of reminders) {
        const message = {
          notification: {
            title: "Tipping closing soon!",
            body: "Game " + reminder.homeTeam + " v " + reminder.awayTeam +
                  " starts soon. You have not yet tipped. Get your tip in now.",
          },
          token: reminder.token,
        };

        try {
          await getMessaging().send(message);
          console.log("Message sent to:", reminder.token);
        } catch (error: any) {
          console.error("Error sending message to:", reminder.token, error);
          if (error.code === "messaging/registration-token-not-registered") {
            // Handle the invalid token, e.g., remove it from your database
            console.log("Removing invalid token:", reminder.token);
            // remove the token from the database location:
            // /AllTippersTokens/{tipperId}/{tokenKey}
            await tokensRef
              .child(`/${reminder.tipperId}/${reminder.token}`).remove();
          }
        }
      }
    } else {
      console.log("No reminders to send.");
    }
  });

interface Reminder {
  tipperId: string;
  token: string;
  homeTeam: string;
  awayTeam: string;
}
