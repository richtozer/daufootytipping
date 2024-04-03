import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

// 1 hour for testing
const EXPIRATION_TIME = 60 * 60 * 1000;

export const pruneTokens = functions.pubsub
  .schedule("every 24 hours").onRun(async () => {
    // Get a reference to the tokens in the database
    const db = admin.database();
    const tokensRef = db.ref("AllTippersTokens");

    debugger;

    // Get all tokens
    const snapshot = await tokensRef.once("value");
    const tokens = snapshot.val();
    const now = Date.now();
    const prunedTokens: string[] = [];

    // Iterate through all tokens
    for (const tipperId in tokens) {
      if (Object.prototype.hasOwnProperty.call(tokens, tipperId)) {
        const tipperTokens = tokens[tipperId];
        for (const tokenId in tipperTokens) {
          if (Object.prototype.hasOwnProperty.call(tipperTokens, tokenId)) {
            const tokenTimestamp = tipperTokens[tokenId].timestamp;
            if (now - tokenTimestamp > EXPIRATION_TIME) {
              prunedTokens.push(`${tipperId}/${tokenId}`);
            } else {
              functions.logger.log(`Token ending in  ${tokenId} is still valid`);
            }
          }
        } 
      }
    }

    // Delete all pruned tokens
    const prunedTokensPromises = prunedTokens.map((tokenPath) => {
      return tokensRef.child(tokenPath).remove();
      functions.logger.log(`Pruned token ${tokenPath}`);
    });

    await Promise.all(prunedTokensPromises);
    const msg = `Pruned ${prunedTokens.length} tokens`;
    functions.logger.log(msg);
    return prunedTokens.length;
  });
