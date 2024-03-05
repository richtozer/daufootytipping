/* import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

// 1 hour for testing
const EXPIRATION_TIME = 60 * 60 * 1000;

export const pruneTokens = functions.pubsub
  .schedule("every 24 hours").onRun(async () => {

    // Get a reference to the tokens in the database
    const db = admin.database();
    const tokensRef = db.ref("AllTippersTokens");

    // Get all tokens
    const snapshot = await tokensRef.once("value");
    const tokens = snapshot.val();
    const now = Date.now();
    const prunedTokens: string[] = [];

    // Iterate through all tokens
    for (const tipperId in tokens) {
      if (tokens.hasOwnProperty(tipperId)) {
        const tipperTokens = tokens[tipperId];
        for (const tokenId in tipperTokens) {
          if (tipperTokens.hasOwnProperty(tokenId)) {
            const tokenTimestamp = tipperTokens[tokenId].timestamp;
            if (now - tokenTimestamp > EXPIRATION_TIME) {
              prunedTokens.push(`${tipperId}/${tokenId}`);}
            else {
              functions.logger.log(`Token ${tokenId} is still valid`);
            }
          }
        } // Add this closing brace
      }
    }

    // Delete all pruned tokens
    const prunedTokensPromises = prunedTokens.map((tokenPath) => {
      return tokensRef.child(tokenPath).remove();
    });

    await Promise.all(prunedTokensPromises);
    const msg = `Pruned ${prunedTokens.length} tokens`;
    functions.logger.log(msg);
    return prunedTokens.length;
  });
 */
