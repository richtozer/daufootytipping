# Flutter Tipping App - One-Time Cleanup Exercise

## Current Task
- [ ] Fix 18 failing tests

## Week 1 Priority - Testing Focus

### High Priority Testing Tasks
- [ ] Fix 18 failing tests
- [ ] Add widget tests for critical user flows
- [ ] Create integration test framework
- [ ] Add missing unit tests for models

### Critical User Flows for Widget Testing
- [ ] User authentication flow (login/signup/logout)
- [ ] Tipping workflow (select game → make tip → submit)
- [ ] Statistics viewing (navigate to stats, view leaderboards)
- [ ] Profile management widgets

### Integration Test Framework Setup
- [ ] Create integration_test directory structure
- [ ] Set up basic integration test configuration
- [ ] Create test helpers for common flows
- [ ] Add CI/CD integration test pipeline

### Missing Unit Tests for Models
- [ ] daucomp.dart - Complex business model
- [ ] game.dart - Core game logic and state management
- [ ] team.dart - Team-related operations
- [ ] tip.dart - Tipping logic
- [ ] tipper.dart - User management
- [ ] league.dart - League-specific rules
- [ ] fixture.dart - Fixture management

## Later (Post Week 1)

### Critical Issues (Week 2)
- [ ] Move assets from /lib/pages/images/ to /assets/
- [ ] Remove all TODO comments from production code
- [ ] Replace dynamic types with concrete types (26 files)
- [ ] Create /lib/widgets/ directory structure

### Major Issues (Week 3)
- [ ] Convert unnecessary StatefulWidgets to StatelessWidget (24 files)
- [ ] Add const constructors to 30+ widgets
- [ ] Extract expensive operations from build methods
- [ ] Implement proper null safety patterns (52 files with ! operator)

### Widget Design Issues (Week 4)
- [ ] Break down large complex widgets (650+ lines)
- [ ] Convert function-based widgets to proper StatelessWidget classes
- [ ] Add missing dispose() methods in StatefulWidgets
- [ ] Implement proper key usage in list widgets

### Files Requiring Immediate Attention (Later)
- [ ] tippers_viewmodel.dart - Dynamic usage + TODO comments
- [ ] user_home_tips_gamelistitem.dart - 652 lines, complex state
- [ ] user_auth.dart - 577 lines, navigation patterns + TODO
- [ ] stats_viewmodel.dart - Heavy dynamic usage
- [ ] user_home_tips_tipchoice.dart - Unnecessary StatefulWidget

## Completed
- [x] Analyzed main Flutter app structure and identified deviations
- [x] Reviewed state management patterns and StatefulWidget usage
- [x] Checked for forbidden patterns (dynamic, setState in loops, missing null safety)
- [x] Analyzed widget design patterns and const constructor usage
- [x] Reviewed test coverage and testing patterns

## Next Steps
Focus on getting the test suite healthy first before tackling structural and performance improvements. A solid test foundation will make refactoring safer and more confident.