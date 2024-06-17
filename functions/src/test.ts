import * as admin from 'firebase-admin';

async function callPubSubFunction() {
  // Initialize Firebase Admin SDK


    admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    // if in debug use local database
    databaseURL: 'http://127.0.0.1:8000/?ns=dau-footy-tipping-f8a42',});

    // admin.initializeApp({
    //     credential: admin.credential.applicationDefault(),
    // });

  //export async function sendReminders() {

   const now = admin.firestore.Timestamp.now();
    
   const twoHoursFromNow = now.toMillis() + 2 * 60 * 60 * 1000;
   const threeHoursFromNow = now.toMillis() + 3 * 60 * 60 * 1000;

   // grab the current comp dbkey from /AppConfig/currentDAUComp
   const compRef = admin.database().ref("/AppConfig/currentDAUComp");
   const compSnapshot = await compRef.once("value");
   const comp = compSnapshot.val();

   const gamesRef = admin.database()
     .ref(`/DAUCompsGames/${comp}`);

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
}

callPubSubFunction();