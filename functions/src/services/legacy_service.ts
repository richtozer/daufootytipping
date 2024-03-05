import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();

export const submitLegacyTips = functions
  .region("us-central1", "asia-southeast1")
  .https.onRequest(
    async (request, response) => {
      try {
        const {submittime, dauCompDbKey, tipperID, dauRound, tips} =
          request.body;
        // Validate parameters
        if (!submittime || !tipperID || !dauRound || !tips || !dauCompDbKey) {
          const msg = "Missing required parameters!!";
          functions.logger.error(msg);
          response.status(400).send(msg);
          return;
        }

        // Search for tipperID in Firebase Realtime Database
        const tippersRef = admin.database().ref("AllTippers");
        const snapshot = await tippersRef.once("value");

        const tipperKey = Object.keys(snapshot.val()).find(
          (key) => snapshot.val()[key].tipperID === tipperID
        );

        if (!tipperKey) {
          const msg = `Error, tipper ID ${tipperID} not found in the database`;
          functions.logger.error(msg);
          throw new Error(msg);
        } else {
          functions.logger.info(
            `Found Tipper with dbkey ${tipperKey} using tipper ID ${tipperID}`
          );
        }

        // Get a list of gameDbKey's from the new location in the database
        const roundsRef = admin.database()
          .ref(`DAUComps/${dauCompDbKey}/combinedRounds`);
        const roundsSnapshot = await roundsRef.once("value");

        if (!roundsSnapshot.exists()) {
          const msg = `Error, no rounds found for dauCompDbKey ${dauCompDbKey}`;
          functions.logger.error(msg);
          throw new Error(msg);
        }

        // Get the list of game keys for the round
        const gameKeys = roundsSnapshot
          .val()[dauRound - 1]; // Subtract 1 because array indices are 0-based

        if (!gameKeys) {
          const msg = `Error, no games found for dauRound ${dauRound}`;
          functions.logger.error(msg);
          throw new Error(msg);
        }

        // Retrieve the game data for each game key
        const gameData = [];
        for (const gameKey of gameKeys) {
          const gamesRef = admin.database()
            .ref(`DAUCompsGames/${dauCompDbKey}/${gameKey}`);
          const gameSnapshot = await gamesRef.once("value");
          if (gameSnapshot.exists()) {
            gameData.push({
              dbKey: gameKey,
              league: gameKey.substring(0, 3),
              matchNumber: gameSnapshot.val().MatchNumber,
            });
          }
        }

        // check if gameData is empty, if so throw an error
        if (gameData.length === 0) {
          const msg = `Error, no games found for dauRound ${dauRound}`;
          functions.logger.error(msg);
          throw new Error(msg);
        } else {
          const msg = `Found ${gameData.length} games for dauRound ${dauRound}`;
          functions.logger.info(msg);
        }

        // Loop through the round games and create a tip as needed
        // assumes the data is sorted by key i.e. league-round-matchnumber

        // assume the games are sorted by league, afl first, then nrl
        // store index when the league changes
        let leagueChangeIndex = -1;
        for (const [index, game] of gameData.entries()) {
          if (game.league === "nrl" && leagueChangeIndex === -1) {
            leagueChangeIndex = index;
          }
          const tipsRef = admin.database().ref(
            `AllTips/${dauCompDbKey}/${tipperKey}/${game.dbKey}`
          );
          // in the database the records are in afl-round-1, afl-round-2
          // ...nrl-round-1, nrl-round-2...etc
          // so we need to adjust the index to reverse the order
          let tipIndex = index;
          switch (leagueChangeIndex) {
          case -1: // processing afl games
            // adjust the tipindex to start from 8
            tipIndex = index + 8;
            break;
          default: // processing nrl games
            // adjust tipindex to start from 0
            tipIndex = index - leagueChangeIndex;
            break;
          }

          // Update/set the tip in the database for this game
          if (tips[tipIndex] !== "z" && tips[tipIndex] !== "D") {
            functions.logger.info(
              `About to process tip [${tips[tipIndex]}] at ` +
              `index ${tipIndex} for game ${tipsRef}`
            );
            await tipsRef.update({
              gameResult: tips[tipIndex],
              submittedTimeUTC: submittime,
              legacyTip: true,
            });
          } else {
            functions.logger.info(
              `Ignored 'z' or 'D' tip [${tips[tipIndex]}] at ` +
              `index ${tipIndex} for game ${tipsRef}`
            );
          }
        }
        response.status(200).send(
          `Legacy tips successfully submitted to Firebase for ${tipperKey}`);
      } catch (error) {
        functions.logger.error(error);
        response.status(500).send(`Error submitting tips ${error}`);
      }
    }
  );
