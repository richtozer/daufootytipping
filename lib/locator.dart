import 'package:daufootytipping/pages/admin_teams/admin_teams_viewmodel.dart';
import 'package:get_it/get_it.dart';

final locator = GetIt.I;

void setupLocator() {
  locator.registerSingleton<TeamsViewModel>(TeamsViewModel());
}
