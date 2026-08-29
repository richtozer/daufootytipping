import {onSchedule} from "firebase-functions/v2/scheduler";
import {getDatabase} from "firebase-admin/database";
import {getMessaging} from "firebase-admin/messaging";
import {isReminderGameWithinCompCutoff} from
  "./reminder_game_eligibility";

// Schedule: "20 21-9 * 3-9 *"
// Minute 20 Twenty minutes past the hour
// Hour 21-23,0-9 Every hour from 21:00 UTC to 9:00 UTC
// Day of Month * Every day of the month
// Month 3-9 March to September only
// Day of Week * Every day of the week

export const sendHourlyReminders =
  onSchedule("20 21-23,0-9 * 3-9 *", async () => {
    const isTestingMode = false; // DOES NOT WORK IN TESTING MODE
    const testTipperId = "-NoGNrrChbi0sETPpJNq";

    // Format the current date to match the database format:
    // "YYYY-MM-DD HH:MM:SSZ"
    const now = new Date().toISOString()
      .replace("T", " ")
      .slice(0, -5) + "Z";
    const threeHoursFromNow = new Date(new Date()
      .getTime() + 3 * 60 * 60 * 1000).toISOString()
      .replace("T", " ")
      .slice(0, -5) + "Z";

    console
      .log("Checking for games between: ", now, " and ", threeHoursFromNow);

    const currentCompRef = getDatabase().ref("/AppConfig/currentDAUComp");
    const compSnapshot = await currentCompRef.once("value");
    const compDBKey = compSnapshot.val();

    const teamsRef = getDatabase().ref("/Teams");
    const teamsSnapshot = await teamsRef.once("value");
    const teams = teamsSnapshot.val();

    const gamesRef = getDatabase().ref(`/DAUCompsGames/${compDBKey}`);
    const gamesSnapshot = await gamesRef
      .orderByChild("DateUtc")
      .startAt(now)
      .endAt(threeHoursFromNow)
      .once("value");

    if (!gamesSnapshot.exists()) {
      console.log("No games in the specified time range " +
        "found at " + gamesRef + ". Ending processing.");
      return;
    }

    const games = gamesSnapshot.val();
    const compConfigSnapshot = await getDatabase()
      .ref(`/AllDAUComps/${compDBKey}`)
      .once("value");
    const compCutoffs = compConfigSnapshot.val() ?? {};
    const gameKeys = Object.keys(games).filter((gameKey) =>
      isReminderGameWithinCompCutoff(
        gameKey,
        games[gameKey].DateUtc,
        compCutoffs,
      ),
    );

    if (gameKeys.length === 0) {
      console.log("No games in the specified time range are within the " +
        "competition cutoffs. Ending processing.");
      return;
    }

    console.log("Found the following games in the specified time range " +
      "and competition cutoffs:");
    for (const gameKey of gameKeys) {
      console.log("game: %s v %s, startDate: %s", games[gameKey].HomeTeam,
        games[gameKey].AwayTeam, games[gameKey].DateUtc);
    }

    const tokensRef = getDatabase().ref("/AllTippersTokens");
    let tippersWithTokens;
    if (isTestingMode) {
      const tokensSnapshot = await tokensRef.child(testTipperId).once("value");
      tippersWithTokens = {[testTipperId]: tokensSnapshot.val()};
    } else {
      const tokensSnapshot = await tokensRef.once("value");
      tippersWithTokens = tokensSnapshot.val();
    }

    const tippersRef = getDatabase().ref("/AllTippers");
    const tippersSnapshot = await tippersRef.once("value");
    const tippers = tippersSnapshot.val();

    const reminders: Reminder[] = [];

    for (const tipperId in tippersWithTokens) {
      if (Object.prototype.hasOwnProperty.call(tippersWithTokens, tipperId)) {
        const tipper = tippers[tipperId];
        // if (tipper.compsParticipatedIn && tipper.compsParticipatedIn
        // .includes(compDBKey)) {
        const tipperName = tipper?.name ?? tipperId;
        const tokens = tippersWithTokens[tipperId];
        let gamesNotTipped = 0;

        for (const gameKey of gameKeys) {
          const tipRef = getDatabase()
            .ref(`/AllTips/${compDBKey}/${tipperId}/${gameKey}`);
          const tipSnapshot = await tipRef.once("value");

          if (!tipSnapshot.exists()) {
            gamesNotTipped++;
            const homeTeamLongName = games[gameKey].HomeTeam;
            const awayTeamLongName = games[gameKey].AwayTeam;

            const homeTeam = teams[`${gameKey
              .substring(0, 3)}-${homeTeamLongName}`]?.name ||
              homeTeamLongName;
            const awayTeam = teams[`${gameKey
              .substring(0, 3)}-${awayTeamLongName}`]?.name ||
              awayTeamLongName;
            console
              .log(`Tipper ${tipperName} no tip: ${homeTeam} v ${awayTeam}.`);

            for (const tokenKey in tokens) {
              if (Object.prototype.hasOwnProperty.call(tokens, tokenKey)) {
                reminders.push({
                  tipperId: tipperId,
                  tipperName: tipperName,
                  token: tokenKey,
                  homeTeam: homeTeam,
                  awayTeam: awayTeam,
                  gameStartTimeUTC: new Date(games[gameKey].DateUtc),
                  gamesNotTipped: gamesNotTipped,
                });
              }
            }
          }
        }
        // }
      } else {
        console.log("No tokens found for tipperId: ", tipperId);
      }
    }

    if (reminders.length > 0) {
      console.log("Sending reminders to: ", reminders.length, "devices.");
      for (const reminder of reminders) {
        const message = {
          notification: {
            title: "Tipping closing soon!",
            body:
            `Game ${reminder.homeTeam} v ${reminder.awayTeam} starts soon. ` +
            "You have not yet tipped. " +
            `Get your tip in now, ${reminder.tipperName}.`,
          },
          token: reminder.token,
          apns: {
            headers: {
              "apns-expiration": `${Math
                .floor(new Date(reminder.gameStartTimeUTC).getTime() / 1000)}`,
            },
            payload: {
              aps: {
                "sound": "default",
                "content-available": 0,
              },
            },
          },
          android: {
            ttl: Math.floor(new Date(reminder.gameStartTimeUTC)
              .getTime() / 1000) - Math.floor(Date.now() / 1000),
            notification: {
              channelId: "tipping_reminders_v1",
              icon: "ic_stat_tips",
              sound: "default",
            },
          },
        };

        try {
          await getMessaging().send(message);
          console.log("Reminder sent to:", reminder.tipperId);
        } catch (error: unknown) {
          console.error("Error sending reminder to:", reminder.token, error);
          const messagingError = error as { errorInfo?: { code: string } };
          if (error instanceof Error && messagingError
            .errorInfo?.code ===
              "messaging/registration-token-not-registered") {
            console.log("Removing invalid token:", reminder.token);
            await tokensRef
              .child(`/${reminder.tipperId}/${reminder.token}`).remove();
          }
        }
      }
      console.log("Reminders sent. End of processing.");
    } else {
      console.log("No reminders to send.");
    }
  });

interface Reminder {
  tipperId: string;
  tipperName: string;
  token: string;
  homeTeam: string;
  awayTeam: string;
  gameStartTimeUTC: Date;
  gamesNotTipped?: number;
}
