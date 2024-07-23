import {onSchedule} from "firebase-functions/v2/scheduler";
import {database} from "firebase-admin";
import {getMessaging} from "firebase-admin/messaging";

export const sendHourlyReminders =
  onSchedule("every hour", async () => {
    const isTestingMode = false; // Set to false for production
    const testTipperId = "-NoGNrrChbi0sETPpJNq";

    // Format the current date to match the database format:
    // "YYYY-MM-DD HH:MM:SSZ"
    const now = new Date().toISOString()
      .replace("T", " ")
      .slice(0, -5) + "Z";
    // Calculate three hours from now and format it
    const threeHoursFromNow = new Date(new Date()
      .getTime() + 3 * 60 * 60 * 1000).toISOString()
      .replace("T", " ")
      .slice(0, -5) + "Z";

    console
      .log("Checking for games between: ", now, " and ", threeHoursFromNow);

    const compRef = database().ref("/AppConfig/currentDAUComp");
    const compSnapshot = await compRef.once("value");
    const compDBKey = compSnapshot.val();

    const teamsRef = database().ref("/Teams");
    const teamsSnapshot = await teamsRef.once("value");
    const teams = teamsSnapshot.val();

    const gamesRef = database().ref(`/DAUCompsGames/${compDBKey}`);
    const gamesSnapshot = await gamesRef
      .orderByChild("DateUtc")
      .startAt(now)
      .endAt(threeHoursFromNow)
      .once("value");

    if (!gamesSnapshot.exists()) {
      console.log("No games in the specified time range " +
        "found at " + gamesRef + ". Ending processing.");
      return;
    } else {
      console.log("Found the following games in the specified time range:");
      gamesSnapshot.forEach((game) => {
        console.log("game: %s v %s, startDate: %s", game.val().HomeTeam,
          game.val().AwayTeam, game.val().DateUtc);
      });
    }

    const games = gamesSnapshot.val();
    const gameKeys = Object.keys(games);

    const tokensRef = database().ref("/AllTippersTokens");
    let tippersWithTokens;
    if (isTestingMode) {
      const tokensSnapshot = await tokensRef.child(testTipperId).once("value");
      tippersWithTokens = {[testTipperId]: tokensSnapshot.val()};
    } else {
      const tokensSnapshot = await tokensRef.once("value");
      tippersWithTokens = tokensSnapshot.val();
    }

    const reminders: Reminder[] = [];

    for (const tipperId in tippersWithTokens) {
      if (Object.prototype.hasOwnProperty.call(tippersWithTokens, tipperId)) {
        const tokens = tippersWithTokens[tipperId];

        for (const gameKey of gameKeys) {
          const tipRef = database()
            .ref(`/AllTips/${compDBKey}/${tipperId}/${gameKey}`);
          const tipSnapshot = await tipRef.once("value");

          if (!tipSnapshot.exists()) {
            const homeTeamLongName = games[gameKey].HomeTeam;
            const awayTeamLongName = games[gameKey].AwayTeam;

            const homeTeam = teams[`${gameKey
              .substring(0, 3)}-${homeTeamLongName}`]?.name ||
              homeTeamLongName;
            const awayTeam = teams[`${gameKey
              .substring(0, 3)}-${awayTeamLongName}`]?.name ||
              awayTeamLongName;
            console
              .log(`Tipper ${tipperId} no tip: ${homeTeam} v ${awayTeam}.`);

            for (const tokenKey in tokens) {
              if (Object.prototype.hasOwnProperty.call(tokens, tokenKey)) {
                reminders.push({
                  tipperId: tipperId,
                  token: tokenKey,
                  homeTeam: homeTeam,
                  awayTeam: awayTeam,
                  gameStartTimeUTC: new Date(games[gameKey].DateUtc),
                });
              }
            }
          }
        }
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
            "You have not yet tipped. Get your tip in now.",
          },
          token: reminder.token,
          apns: {
            headers: {
              "apns-expiration": `${Math
                .floor(new Date(reminder.gameStartTimeUTC).getTime() / 1000)}`,
            },
          },
          android: {
            ttl: Math.floor(new Date(reminder.gameStartTimeUTC)
              .getTime() / 1000) - Math.floor(Date.now() / 1000),
          },
        };

        try {
          await getMessaging().send(message);
          console.log("Reminder sent to:", reminder.tipperId);
        } catch (error: any) {
          console.error("Error sending reminder to:", reminder.token, error);
          if (error.code === "messaging/registration-token-not-registered") {
            console.log("Removing invalid token:", reminder.token);
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
  gameStartTimeUTC: Date;
}
