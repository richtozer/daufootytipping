import 'package:daufootytipping/firebase_options.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/services/firebase_remoteconfig_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await dotenv.load(fileName: "./dotenv");

    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    FirebaseDatabase database = FirebaseDatabase.instance;
    database.useDatabaseEmulator('localhost', 8000);

    RemoteConfigService remoteConfigService = RemoteConfigService();
    String configDAUCompDbkey =
        await remoteConfigService.getConfigCurrentDAUComp();

    group('DAUCompsViewModel', () {
//     test('init should initialize the view model', () async {
//       final viewModel = DAUCompsViewModel(configDAUCompDbkey);
//       await viewModel.init();

//       // Add your assertions here
//     });

//     test('changeSelectedDAUComp should change the selected DAUComp', () async {
//       final viewModel = DAUCompsViewModel(configDAUCompDbkey);
//       await viewModel.changeSelectedDAUComp();

//       // Add your assertions here
//     });

//     test('selectedTipperChanged should update the selected tipper', () async {
//       final viewModel = DAUCompsViewModel(configDAUCompDbkey);
//       await viewModel.selectedTipperChanged();

//       // Add your assertions here
//     });

//     test('isSelectedCompActiveComp should return true if the selected comp is active', () {
//       final viewModel = DAUCompsViewModel(configDAUCompDbkey);
//       final isActive = viewModel.isSelectedCompActiveComp();

//       // Add your assertions here
//     });

//     test('_initializeAndResetViewModels should initialize and reset the view models', () async {
//       final viewModel = DAUCompsViewModel(configDAUCompDbkey);
//       await viewModel._initializeAndResetViewModels();

//       // Add your assertions here
//     });

//     test('_listenToDAUComps should start listening to DAU comps', () {
//       final viewModel = DAUCompsViewModel(configDAUCompDbkey);
//       viewModel._listenToDAUComps();

//       // Add your assertions here
//     });

//     test('_handleEvent should handle database events', () async {
//       final viewModel = DAUCompsViewModel(configDAUCompDbkey);
//       final event = DatabaseEvent();

//       await viewModel._handleEvent(event);

//       // Add your assertions here
//     });

//     test('_initRoundState should initialize the round state', () {
//       final viewModel = DAUCompsViewModel(configDAUCompDbkey);
//       final round = DAURound();

//       viewModel._initRoundState(round);

//       // Add your assertions here
//     });

//     test('_fixtureUpdateTriggerDelay should return the correct delay', () {
//       final lastUpdate = DateTime.utc(2023, 3, 11, 20, 41, 59);
//       final delay = DAUCompsViewModel._fixtureUpdateTriggerDelay(lastUpdate);

//       // Add your assertions here
//     });

//     test('_fixtureUpdateTrigger should trigger the fixture update', () async {
//       final viewModel = DAUCompsViewModel(configDAUCompDbkey);
//       await viewModel._fixtureUpdateTrigger();

//       // Add your assertions here
//     });

//     test('getNetworkFixtureData should fetch and process fixture data', () async {
//       final viewModel = DAUCompsViewModel(configDAUCompDbkey);
//       final daucompToUpdate = DAUComp();

//       final result = await viewModel.getNetworkFixtureData(daucompToUpdate);

//       // Add your assertions here
//     });

//     test('syncTipsWithLegacy should sync tips with legacy system', () async {
//       final viewModel = DAUCompsViewModel(configDAUCompDbkey);
//       final daucompToUpdate = DAUComp();
//       final onlySyncThisTipper = Tipper();

//       final result = await viewModel.syncTipsWithLegacy(daucompToUpdate, onlySyncThisTipper);

//       // Add your assertions here
//     });

//     test('_updateRoundStartEndTimesBasedOnFixture should update round start and end times', () async {
//       final viewModel = DAUCompsViewModel(configDAUCompDbkey);
//       final daucomp = DAUComp();
//       final gamesViewModel = GamesViewModel();
//       final rawGames = [];

//       await viewModel._updateRoundStartEndTimesBasedOnFixture(daucomp, gamesViewModel, rawGames);

//       // Add your assertions here
//     });

//     test('_groupGamesByLeagueAndRound should group games by league and round', () {
//       final viewModel = DAUCompsViewModel(configDAUCompDbkey);
//       final games = [];

//       final result = viewModel._groupGamesByLeagueAndRound(games);

//       // Add your assertions here
//     });

//     test('_calculateStartEndTimes should calculate the start and end times', () {
//       final viewModel = DAUCompsViewModel(configDAUCompDbkey);
//       final rawGames = [];

//       final result = viewModel._calculateStartEndTimes(rawGames);

//       // Add your assertions here
//     });

//     test('_sortGameGroupsByStartTimeThenMatchNumber should sort game groups by start time and match number', () {
//       final viewModel = DAUCompsViewModel(configDAUCompDbkey);
//       final groups = {};

//       final result = viewModel._sortGameGroupsByStartTimeThenMatchNumber(groups);

//       // Add your assertions here
//     });

//     test('_combineGameGroupsIntoRounds should combine game groups into rounds', () {
//       final viewModel = DAUCompsViewModel(configDAUCompDbkey);
//       final sortedGameGroups = [];

//       final result = viewModel._combineGameGroupsIntoRounds(sortedGameGroups);

//       // Add your assertions here
//     });

//     test('_updateDatabaseWithCombinedRounds should update the database with combined rounds', () async {
//       final viewModel = DAUCompsViewModel(configDAUCompDbkey);
//       final combinedRounds = [];
//       final daucomp = DAUComp();

//       await viewModel._updateDatabaseWithCombinedRounds(combinedRounds, daucomp);

//       // Add your assertions here
//     });

//     test('linkGameWithRounds should link games with rounds', () async {
//       final viewModel = DAUCompsViewModel(configDAUCompDbkey);
//       final daucompToUpdate = DAUComp();
//       final gamesViewModel = GamesViewModel();

//       await viewModel.linkGameWithRounds(daucompToUpdate, gamesViewModel);

//       // Add your assertions here
//     });

//     test('findComp should find the DAUComp with the given db key', () async {
//       final viewModel = DAUCompsViewModel(configDAUCompDbkey);
//       final compDbKey = '';

//       final result = await viewModel.findComp(compDbKey);

//       // Add your assertions here
//     });

//     test('updateCompAttribute should update the specified attribute of a DAUComp', () {
//       final viewModel = DAUCompsViewModel(configDAUCompDbkey);
//       final dauCompDbKey = '';
//       final attributeName = '';
//       final attributeValue = '';

//       viewModel.updateCompAttribute(dauCompDbKey, attributeName, attributeValue);

//       // Add your assertions here
//     });

      test('newDAUComp should add a new DAUComp record if dbkey is null',
          () async {
        final viewModel = DAUCompsViewModel(configDAUCompDbkey);
        final newDAUComp = DAUComp(
            name: 'Test Comp',
            dbkey: null,
            aflFixtureJsonURL: Uri.parse('http://localhost:3000/afl'),
            nrlFixtureJsonURL: Uri.parse('http://localhost:3000/nrl'),
            daurounds: []);

        await viewModel.newDAUComp(newDAUComp);

        // Add your assertions here
      });

//     test('saveBatchOfCompAttributes should save a batch of DAUComp attributes', () async {
//       final viewModel = DAUCompsViewModel(configDAUCompDbkey);

//       await viewModel.saveBatchOfCompAttributes();

//       // Add your assertions here
//     });

//     test('getDAUcomps should return a list of DAUComps', () async {
//       final viewModel = DAUCompsViewModel(configDAUCompDbkey);

//       final result = await viewModel.getDAUcomps();

//       // Add your assertions here
//     });

//     test('getCombinedRounds should return a list of combined rounds', () async {
//       final viewModel = DAUCompsViewModel(configDAUCompDbkey);

//       final result = await viewModel.getCombinedRounds();

//       // Add your assertions here
//     });

//     test('sortGamesIntoLeagues should sort games into leagues', () async {
//       final viewModel = DAUCompsViewModel(configDAUCompDbkey);
//       final combinedRound = DAURound();

//       final result = await viewModel.sortGamesIntoLeagues(combinedRound);

//       // Add your assertions here
//     });

//     test('getDefaultTipsForCombinedRoundNumber should return the default tips for a combined round number', () async {
//       final viewModel = DAUCompsViewModel(configDAUCompDbkey);
//       final combinedRound = DAURound();

//       final result = await viewModel.getDefaultTipsForCombinedRoundNumber(combinedRound);

//       // Add your assertions here
//     });

//     // Add more tests as needed
//   });
// }import 'package:flutter_test/flutter_test.dart';
// import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';

// void main() {
//   group('DAUCompsViewModel', () {
//     late DAUCompsViewModel dauCompsViewModel;

//     setUp(() {
//       dauCompsViewModel = DAUCompsViewModel(configDAUCompDbkey);
//     });

//     test('init() should initialize the view model', () async {
//       await dauCompsViewModel.init();

//       // Add your assertions here
//     });

//     test('changeSelectedDAUComp() should change the selected DAUComp', () async {
//       await dauCompsViewModel.changeSelectedDAUComp();

//       // Add your assertions here
//     });

//     test('selectedTipperChanged() should update the selected tipper', () async {
//       await dauCompsViewModel.selectedTipperChanged();

//       // Add your assertions here
//     });

//     test('isSelectedCompActiveComp() should return whether the selected comp is active', () {
//       final isActive = dauCompsViewModel.isSelectedCompActiveComp();

//       // Add your assertions here
//     });

//     test('_initializeAndResetViewModels() should initialize and reset the view models', () async {
//       await dauCompsViewModel._initializeAndResetViewModels();

//       // Add your assertions here
//     });

//     test('_listenToDAUComps() should listen to DAU comps', () {
//       dauCompsViewModel._listenToDAUComps();

//       // Add your assertions here
//     });

//     test('_handleEvent() should handle a database event', () async {
//       final event = DatabaseEvent();

//       await dauCompsViewModel._handleEvent(event);

//       // Add your assertions here
//     });

//     test('_initRoundState() should initialize the round state', () {
//       final round = DAURound();

//       dauCompsViewModel._initRoundState(round);

//       // Add your assertions here
//     });

//     test('_fixtureUpdateTriggerDelay() should calculate the delay for the fixture update', () {
//       final lastUpdate = DateTime.now();

//       final delay = dauCompsViewModel._fixtureUpdateTriggerDelay(lastUpdate);

//       // Add your assertions here
//     });

//     test('_fixtureUpdateTrigger() should trigger the fixture update', () async {
//       await dauCompsViewModel._fixtureUpdateTrigger();

//       // Add your assertions here
//     });

//     test('getNetworkFixtureData() should fetch and process the fixture data', () async {
//       final daucompToUpdate = DAUComp();

//       final result = await dauCompsViewModel.getNetworkFixtureData(daucompToUpdate);

//       // Add your assertions here
//     });

//     test('syncTipsWithLegacy() should sync tips with the legacy system', () async {
//       final daucompToUpdate = DAUComp();
//       final onlySyncThisTipper = Tipper();

//       final result = await dauCompsViewModel.syncTipsWithLegacy(daucompToUpdate, onlySyncThisTipper);

//       // Add your assertions here
//     });

//     test('_updateRoundStartEndTimesBasedOnFixture() should update the round start and end times based on the fixture', () async {
//       final daucomp = DAUComp();
//       final gamesViewModel = GamesViewModel();
//       final rawGames = [];

//       await dauCompsViewModel._updateRoundStartEndTimesBasedOnFixture(daucomp, gamesViewModel, rawGames);

//       // Add your assertions here
//     });

//     test('_groupGamesByLeagueAndRound() should group games by league and round', () {
//       final games = [];

//       final result = dauCompsViewModel._groupGamesByLeagueAndRound(games);

//       // Add your assertions here
//     });

//     test('_calculateStartEndTimes() should calculate the start and end times for a list of games', () {
//       final rawGames = [];

//       final result = dauCompsViewModel._calculateStartEndTimes(rawGames);

//       // Add your assertions here
//     });

//     test('_sortGameGroupsByStartTimeThenMatchNumber() should sort game groups by start time then match number', () {
//       final groups = {};

//       final result = dauCompsViewModel._sortGameGroupsByStartTimeThenMatchNumber(groups);

//       // Add your assertions here
//     });

//     test('_combineGameGroupsIntoRounds() should combine game groups into rounds', () {
//       final sortedGameGroups = [];

//       final result = dauCompsViewModel._combineGameGroupsIntoRounds(sortedGameGroups);

//       // Add your assertions here
//     });

//     test('_updateDatabaseWithCombinedRounds() should update the database with combined rounds', () async {
//       final combinedRounds = [];
//       final daucomp = DAUComp();

//       await dauCompsViewModel._updateDatabaseWithCombinedRounds(combinedRounds, daucomp);

//       // Add your assertions here
//     });

//     test('linkGameWithRounds() should link games with rounds', () async {
//       final daucompToUpdate = DAUComp();
//       final gamesViewModel = GamesViewModel();

//       await dauCompsViewModel.linkGameWithRounds(daucompToUpdate, gamesViewModel);

//       // Add your assertions here
//     });

//     test('findComp() should find a DAUComp by its database key', () async {
//       final compDbKey = '';

//       final result = await dauCompsViewModel.findComp(compDbKey);

//       // Add your assertions here
//     });

//     test('updateCompAttribute() should update a DAUComp attribute', () {
//       final dauCompDbKey = '';
//       final attributeName = '';
//       final attributeValue = '';

//       dauCompsViewModel.updateCompAttribute(dauCompDbKey, attributeName, attributeValue);

//       // Add your assertions here
//     });

//     test('newDAUComp() should create a new DAUComp', () async {
//       final newDAUComp = DAUComp();

//       await dauCompsViewModel.newDAUComp(newDAUComp);

//       // Add your assertions here
//     });

//     test('saveBatchOfCompAttributes() should save a batch of DAUComp attributes', () async {
//       await dauCompsViewModel.saveBatchOfCompAttributes();

//       // Add your assertions here
//     });

//     test('getDAUcomps() should return a list of DAU comps', () async {
//       final result = await dauCompsViewModel.getDAUcomps();

//       // Add your assertions here
//     });

//     test('getCombinedRounds() should return a list of combined rounds', () async {
//       final result = await dauCompsViewModel.getCombinedRounds();

//       // Add your assertions here
//     });

//     test('sortGamesIntoLeagues() should sort games into leagues', () async {
//       final combinedRound = DAURound();

//       final result = await dauCompsViewModel.sortGamesIntoLeagues(combinedRound);

//       // Add your assertions here
//     });

//     test('getDefaultTipsForCombinedRoundNumber() should return the default tips for a combined round number', () async {
//       final combinedRound = DAURound();

//       final result = await dauCompsViewModel.getDefaultTipsForCombinedRoundNumber(combinedRound);

//       // Add your assertions here
//     });

//     // Add more test cases as needed
    });
  });
}
