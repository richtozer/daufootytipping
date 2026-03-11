import 'dart:async';

import 'package:data_table_2/data_table_2.dart';
import 'package:daufootytipping/models/daucomp.dart';
import 'package:daufootytipping/models/league.dart';
import 'package:daufootytipping/models/scoring.dart';
import 'package:daufootytipping/models/tip_history_entry.dart';
import 'package:daufootytipping/models/tipper.dart';
import 'package:daufootytipping/pages/user_home/user_home_avatar.dart';
import 'package:daufootytipping/pages/user_home/user_home_header.dart';
import 'package:daufootytipping/repositories/tip_history_repository.dart';
import 'package:daufootytipping/view_models/daucomps_viewmodel.dart';
import 'package:daufootytipping/view_models/teams_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:watch_it/watch_it.dart';

class TipperTipHistoryPage extends StatefulWidget {
  final Tipper tipper;
  final TipHistoryRepository? repository;

  const TipperTipHistoryPage({
    super.key,
    required this.tipper,
    this.repository,
  });

  @override
  State<TipperTipHistoryPage> createState() => _TipperTipHistoryPageState();
}

class _TipperTipHistoryPageState extends State<TipperTipHistoryPage> {
  final DateFormat _submittedFormat = DateFormat('dd MMM yy HH:mm');
  List<TipHistoryEntry> _tipHistoryEntries = const <TipHistoryEntry>[];
  bool _isLoading = false;
  bool _isLoadingHistory = false;
  String? _errorMessage;
  TeamsViewModel? _ownedTeamsViewModel;

  @override
  void initState() {
    super.initState();
    _loadTipHistory();
  }

  @override
  void dispose() {
    _ownedTeamsViewModel?.dispose();
    super.dispose();
  }

  Future<void> _loadTipHistory() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final TipHistoryRepository repository =
          widget.repository ?? await _buildDefaultRepository();
      final List<TipHistoryEntry> tipHistory = await repository.fetchCurrentTipHistory(
        widget.tipper,
      );
      tipHistory.sort(
        (TipHistoryEntry a, TipHistoryEntry b) =>
            b.tipSubmittedUTC.compareTo(a.tipSubmittedUTC),
      );

      if (!mounted) return;
      setState(() {
        _tipHistoryEntries = tipHistory;
        _isLoading = false;
        _isLoadingHistory = true;
      });
      unawaited(_loadDetailedTipHistory(repository));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not load tip history: $e';
        _isLoading = false;
        _isLoadingHistory = false;
      });
    }
  }

  Future<void> _loadDetailedTipHistory(TipHistoryRepository repository) async {
    try {
      final List<TipHistoryEntry> tipHistory = await repository.fetchTipHistory(
        widget.tipper,
      );
      tipHistory.sort(
        (TipHistoryEntry a, TipHistoryEntry b) =>
            b.tipSubmittedUTC.compareTo(a.tipSubmittedUTC),
      );

      if (!mounted) return;
      setState(() {
        _tipHistoryEntries = tipHistory;
        _isLoadingHistory = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingHistory = false;
      });
    }
  }

  Future<TipHistoryRepository> _buildDefaultRepository() async {
    final DAUCompsViewModel dauCompsViewModel = di<DAUCompsViewModel>();
    await dauCompsViewModel.initialDAUCompLoadComplete;

    final TeamsViewModel teamsViewModel =
        dauCompsViewModel.gamesViewModel?.teamsViewModel ??
        _ownedTeamsViewModel ??
        (_ownedTeamsViewModel = TeamsViewModel());

    return FirestoreTipHistoryRepository(
      dauComps: List<DAUComp>.from(dauCompsViewModel.daucomps),
      teamsViewModel: teamsViewModel,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.lightGreen[200],
        foregroundColor: Colors.white70,
        onPressed: () {
          Navigator.pop(context);
        },
        child: const Icon(Icons.arrow_back),
      ),
      body: Center(
        child: Column(
          children: <Widget>[
            HeaderWidget(
              text: 'Tip History\n${widget.tipper.name}',
              leadingIconAvatar: avatarPic(widget.tipper),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Default [Away] tips are not shown in this list, only actual tips.',
                style: TextStyle(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
            if (_isLoadingHistory && !_isLoading)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('Loading tip change history...'),
                  ],
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: _buildBody(context),
              ),
            ),
            const SizedBox(height: 90),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Text(
          _errorMessage!,
          textAlign: TextAlign.center,
        ),
      );
    }
    if (_tipHistoryEntries.isEmpty) {
      return const Center(
        child: Text(
          'No tip history available for this tipper.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return DataTable2(
      border: TableBorder.all(
        width: 1.0,
        color: Colors.grey.shade300,
      ),
      columnSpacing: 8,
      horizontalMargin: 8,
      minWidth: 444,
      fixedTopRows: 1,
      showCheckboxColumn: false,
      isHorizontalScrollBarVisible: true,
      isVerticalScrollBarVisible: true,
      headingRowHeight: 38,
      dataRowHeight: 44,
      columns: const <DataColumn>[
        DataColumn2(
          fixedWidth: 118,
          label: Text(
            'Submitted',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        DataColumn2(
          fixedWidth: 100,
          label: Text(
            'Matchup',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        DataColumn2(
          fixedWidth: 58,
          label: Text(
            'Tip',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        DataColumn2(
          fixedWidth: 78,
          label: Text(
            'Round',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
      rows: _tipHistoryEntries
          .map(
            (TipHistoryEntry entry) => DataRow(
              cells: <DataCell>[
                DataCell(Text(_submittedFormat.format(entry.tipSubmittedUTC.toLocal()))),
                DataCell(
                  Tooltip(
                    message: '${entry.homeTeamName} v ${entry.awayTeamName}',
                    child: _buildMatchupCell(entry),
                  ),
                ),
                DataCell(
                  Tooltip(
                    message: _buildTipTooltip(entry),
                    child: _buildTipCell(entry),
                  ),
                ),
                DataCell(
                  Text('${entry.year} R${entry.roundNumber}'),
                ),
              ],
            ),
          )
          .toList(),
    );
  }

  Widget _buildMatchupCell(TipHistoryEntry entry) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          _buildTeamLogo(entry.homeTeamLogoUri, entry.league),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text('v'),
          ),
          _buildTeamLogo(entry.awayTeamLogoUri, entry.league),
        ],
      ),
    );
  }

  Widget _buildTipCell(TipHistoryEntry entry) {
    if (entry.tip == GameResult.c) {
      return const Text('Draw');
    }

    final bool isHomeTip =
        entry.tip == GameResult.a || entry.tip == GameResult.b;
    final bool isMarginTip =
        entry.tip == GameResult.a || entry.tip == GameResult.e;

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          _buildTeamLogo(
            isHomeTip ? entry.homeTeamLogoUri : entry.awayTeamLogoUri,
            entry.league,
          ),
          if (isMarginTip)
            Container(
              margin: const EdgeInsets.only(left: 4),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'M',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

  String _buildTipTooltip(TipHistoryEntry entry) {
    switch (entry.tip) {
      case GameResult.a:
        return '${entry.homeTeamName} by margin';
      case GameResult.b:
        return entry.homeTeamName;
      case GameResult.d:
        return entry.awayTeamName;
      case GameResult.e:
        return '${entry.awayTeamName} by margin';
      case GameResult.c:
        return 'Draw';
      case GameResult.z:
        return 'No Result';
    }
  }

  Widget _buildTeamLogo(String? logoUri, League league) {
    return SvgPicture.asset(
      logoUri ?? league.logo,
      width: 20,
      height: 20,
    );
  }

  Widget avatarPic(Tipper tipper) {
    return Hero(
      tag: 'tip-history-${tipper.dbkey ?? tipper.authuid}',
      child: circleAvatarWithFallback(
        imageUrl: tipper.photoURL,
        text: tipper.name,
        radius: 30,
      ),
    );
  }
}
