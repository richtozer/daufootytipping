import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();

export const submitLegacyTips = functions
  .region("us-central1", "asia-southeast1")
  .https.onRequest(
    async (request, response) => {
      try {
        const {dauCompDbKey, tipperID, dauRound, tips} = request.body;
        // Validate parameters
        if (!tipperID || !dauRound || !tips || !dauCompDbKey) {
          const msg = "Missing required parameters!!";
          functions.logger.error(msg);
          response.status(400).send(msg);
          return;
        }

        // Search for tipperID in Firebase Realtime Database
        const tippersRef = admin.database().ref("AllTippers");
        const snapshot = await tippersRef.once("value");

        const matchingKey = Object.keys(snapshot.val()).find(
          (key) => snapshot.val()[key].tipperID === tipperID
        );

        if (!matchingKey) {
          const msg = `Error, tipper ID ${tipperID} not found in the database`;
          functions.logger.error(msg);
          throw new Error(msg);
        } else {
          functions.logger.info(
            `Found Tipper with dbkey ${matchingKey} using tipper ID ${tipperID}`
          );
        }

        // Get a list of gameDbKey's by searching realtime db location
        // /DAUCompsGames/${dauCompDbKey} and finding all records where
        // the combinedRoundNumber=dauRound
        const gamesRef = admin.database().ref(`DAUCompsGames/${dauCompDbKey}`);
        const gamesSnapshot = await gamesRef.once("value");

        if (!gamesSnapshot.exists()) {
          const msg = `Error, no games found for dauCompDbKey ${dauCompDbKey}`;
          functions.logger.error(msg);
          throw new Error(msg);
        }

        const gameData = Object.keys(gamesSnapshot.val())
          .filter(
            (key) => gamesSnapshot.val()[key].combinedRoundNumber === dauRound
          )
          .map((key) => ({
            dbKey: key,
            league: gamesSnapshot.val()[key].league,
            matchNumber: gamesSnapshot.val()[key].matchNumber,
          }));

        // check if gameData is empty, if so throw an error
        if (gameData.length === 0) {
          const msg = `Error, no games found for dauRound ${dauRound}`;
          functions.logger.error(msg);
          throw new Error(msg);
        }

        // Loop through the round games and create a tip as needed
        for (const game of gameData) {
          const tipsRef = admin.database().ref(
            `AllTips/${dauCompDbKey}/${matchingKey}/${game.dbKey}`
          );
          const tipIndex =
            game.league === "afl" ? game.matchNumber + 8 - 1 :
              game.matchNumber - 1;

          // Update/set the tip in the database for this game
          if (tips[tipIndex] !== "z" && tips[tipIndex] !== "D") {
            await tipsRef.update({
              gameResult: tips[tipIndex],
              submittedTimeUTC: new Date().toISOString(),
            });

            functions.logger.info(
              `Successfully processed tip [${tips[tipIndex]}] at ` +
              `index ${tipIndex} for game ${tipsRef}`
            );
          } else {
            functions.logger.info(
              `Ignored 'z' or 'D' tip [${tips[tipIndex]}] at ` +
              `index ${tipIndex} for game ${tipsRef}`
            );
          }
        }
        response.status(200).send(
          `Legacy tips successfully submitted to Firebase for ${matchingKey}`);
      } catch (error) {
        functions.logger.error(error);
        response.status(500).send(`Error submitting tips ${error}`);
      }
    }
  );
