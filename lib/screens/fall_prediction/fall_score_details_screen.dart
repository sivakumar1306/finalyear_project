import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/fall_prediction/engine_outputs.dart';
import '../../models/fall_prediction/prediction_result.dart';
import '../../models/fall_prediction/score_breakdown.dart';
import '../../providers/fall_prediction/fall_prediction_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_typography.dart';
import '../../widgets/glass_back_button.dart';
import '../../widgets/glass_card.dart';
import 'fall_prediction_widgets.dart';

/// "How your score is calculated" — walks from the Fall Risk Score down to
/// every measure that feeds it, using the engine's [ScoreBreakdown].
class FallScoreDetailsScreen extends StatelessWidget {
  const FallScoreDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final result = context.watch<FallPredictionProvider>().currentResult;
    return FallScoreDetailsView(result: result);
  }
}

class FallScoreDetailsView extends StatelessWidget {
  final PredictionResult? result;
  const FallScoreDetailsView({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final result = this.result;
    final breakdown = result?.breakdown;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        leading: const GlassBackButton(),
        title: Text(
          'How your score is calculated',
          style: AppTypography.inter(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: result == null
          ? Center(
              child: Text(
                'Calculating your score…',
                style: AppTypography.inter(color: AppTheme.textSec, fontSize: 14),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _ScoreHero(result: result),
                const SizedBox(height: 20),
                if (breakdown == null)
                  const _Note(
                    text: 'This is a simulated score from the demo menu, so there is no '
                        'measure-by-measure breakdown. Choose "Simulate: Clear (auto)" on the '
                        'Fall Risk tab to see the real calculation.',
                  )
                else ...[
                  const SectionLabel('HOW THE SCORE ADDS UP'),
                  const SizedBox(height: 8),
                  _FormulaCard(breakdown: breakdown),
                  const SizedBox(height: 20),
                  const SectionLabel('WHAT GOES INTO EACH PART'),
                  const SizedBox(height: 8),
                  for (final layer in breakdown.layers) ...[
                    _LayerCard(layer: layer),
                    const SizedBox(height: 12),
                  ],
                  _FallHistoryCard(history: breakdown.fallHistory),
                  const SizedBox(height: 12),
                  _WomensHealthCard(
                    detail: breakdown.womensHealth,
                    hsiWeight: breakdown.hsiWeights['wh'] ?? 0,
                  ),
                  const SizedBox(height: 20),
                  const SectionLabel('DATA COVERAGE'),
                  const SizedBox(height: 8),
                  _CoverageCard(breakdown: breakdown),
                ],
                if (result.explainability != null) ...[
                  const SizedBox(height: 20),
                  const SectionLabel('WHAT TO DO'),
                  const SizedBox(height: 8),
                  GlassCard(
                    child: Text(
                      result.explainability!.recommendationAction,
                      style: AppTypography.inter(
                        color: AppTheme.white85,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

// ── Shared helpers ───────────────────────────────────────────────────────────

Color _layerColor(String key) {
  switch (key) {
    case 'p':
      return AppTheme.hrColor;
    case 'rc':
      return AppTheme.sleepColor;
    case 'mo':
      return AppTheme.hrvColor;
    default:
      return AppTheme.stressColor; // fall history
  }
}

Color _measureColor(String key) {
  switch (key) {
    case 'hr':
      return AppTheme.hrColor;
    case 'hrv':
      return AppTheme.hrvColor;
    case 'spo2':
      return AppTheme.spo2Color;
    case 'temp':
      return AppTheme.tempColor;
    case 'bp':
      return AppTheme.bpColor;
    case 'slp':
      return AppTheme.sleepColor;
    case 'slq':
      return AppTheme.sleepLight;
    case 'act':
    case 'wkl':
      return AppTheme.stepsColor;
    case 'str':
      return AppTheme.stressColor;
    default:
      return AppTheme.gold;
  }
}

Color _bandColor(FrsRiskBand band) {
  switch (band) {
    case FrsRiskBand.low:
      return AppTheme.success;
    case FrsRiskBand.moderate:
      return AppTheme.focus;
    case FrsRiskBand.high:
      return AppTheme.danger;
  }
}

String _bandLabel(FrsRiskBand band) {
  switch (band) {
    case FrsRiskBand.low:
      return 'Low risk (0–39)';
    case FrsRiskBand.moderate:
      return 'Moderate risk (40–69)';
    case FrsRiskBand.high:
      return 'High risk (70–100)';
  }
}

String _f(double v, [int digits = 1]) => v.toStringAsFixed(digits);

TextStyle _title() => AppTypography.inter(
      color: Colors.white,
      fontSize: 14,
      fontWeight: FontWeight.w500,
    );

TextStyle _support({Color color = AppTheme.textSec}) =>
    AppTypography.inter(color: color, fontSize: 12, height: 1.4);

TextStyle _caption() =>
    AppTypography.inter(color: AppTheme.textTertiary, fontSize: 11, height: 1.4);

class _Bar extends StatelessWidget {
  final double fraction;
  final Color color;
  final double height;

  const _Bar({required this.fraction, required this.color, this.height = 4});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: AppTheme.white10),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fraction.clamp(0.0, 1.0),
              child: ColoredBox(color: color.withValues(alpha: 0.8)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  final String text;
  const _Note({required this.text});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: AppTheme.textSec, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: _support())),
        ],
      ),
    );
  }
}

// ── Hero ─────────────────────────────────────────────────────────────────────

class _ScoreHero extends StatelessWidget {
  final PredictionResult result;
  const _ScoreHero({required this.result});

  @override
  Widget build(BuildContext context) {
    final frs = result.frs24.value;
    final band = frs.riskBand;
    final color = _bandColor(band);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FALL RISK SCORE · NEXT 24 H',
            style: AppTypography.inter(
              color: AppTheme.gold,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                frs.round().toString(),
                style: AppTypography.inter(
                  color: Colors.white,
                  fontSize: 48,
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('/ 100', style: _support()),
              ),
            ],
          ),
          Text(_bandLabel(band), style: _support(color: color)),
          const SizedBox(height: 4),
          Text('Higher means a higher chance of falling.', style: _caption()),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _Stat(label: '30-day trend', value: result.frs30.value.round().toString()),
              ),
              Expanded(
                child: _Stat(label: 'Stability index', value: result.hsi.value.round().toString()),
              ),
              Expanded(
                child: _Stat(label: 'Data coverage', value: '${result.q.q.round()}%'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: AppTypography.inter(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w300,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _caption()),
      ],
    );
  }
}

// ── Formula ──────────────────────────────────────────────────────────────────

class _FormulaRow {
  final String key;
  final String label;
  final String expression;
  final double points;
  const _FormulaRow(this.key, this.label, this.expression, this.points);
}

class _FormulaCard extends StatelessWidget {
  final ScoreBreakdown breakdown;
  const _FormulaCard({required this.breakdown});

  @override
  Widget build(BuildContext context) {
    LayerDetail layer(String key) => breakdown.layers.firstWhere((l) => l.key == key);
    final mo = layer('mo');
    final rc = layer('rc');
    final p = layer('p');
    final fh = breakdown.fallHistory;
    final rows = [
      _FormulaRow('mo', 'Motion', '${_f(mo.lambda, 3)} × (100 − ${mo.score.round()})', mo.frsPoints),
      _FormulaRow('rc', 'Recovery', '${_f(rc.lambda, 3)} × (100 − ${rc.score.round()})', rc.frsPoints),
      _FormulaRow('p', 'Physiology', '${_f(p.lambda, 3)} × (100 − ${p.score.round()})', p.frsPoints),
      _FormulaRow('fh', 'Fall history', '${_f(fh.lambda, 3)} × ${_f(fh.normalized)}', fh.frsPoints),
    ];

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Each part is scored 0–100 for stability. The less stable it is, the more '
            'risk points it adds, scaled by how strongly it predicts falls.',
            style: _support(),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 10,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final r in rows)
                    if (r.points > 0.05)
                      Expanded(
                        flex: (r.points * 100).round().clamp(1, 10000),
                        child: ColoredBox(color: _layerColor(r.key).withValues(alpha: 0.8)),
                      ),
                  Expanded(
                    flex: ((100 - breakdown.frs24) * 100).round().clamp(1, 10000),
                    child: const ColoredBox(color: AppTheme.white10),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _layerColor(r.key),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.label, style: _title()),
                        Text(r.expression, style: _caption()),
                      ],
                    ),
                  ),
                  Text(
                    '+${_f(r.points)}',
                    style: AppTypography.inter(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          const Divider(color: AppTheme.white10, height: 16),
          Row(
            children: [
              Expanded(child: Text('Fall risk score', style: _title())),
              Text(
                '= ${breakdown.frs24.round()}',
                style: AppTypography.inter(
                  color: AppTheme.gold,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Weights λ = ln(odds ratio) ÷ Σ ln(odds ratio): fall history 0.402, motion 0.290, '
            'physiology 0.214, recovery 0.093. '
            'Women\'s health shapes the stability index but never adds fall points directly.',
            style: _caption(),
          ),
        ],
      ),
    );
  }
}

// ── Layer cards ──────────────────────────────────────────────────────────────

class _LayerCard extends StatelessWidget {
  final LayerDetail layer;
  const _LayerCard({required this.layer});

  @override
  Widget build(BuildContext context) {
    final color = _layerColor(layer.key);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(layer.label, style: _title()),
                    const SizedBox(height: 2),
                    Text(layer.description, style: _support()),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    layer.score.round().toString(),
                    style: AppTypography.inter(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  Text('stability / 100', style: _caption()),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          _Bar(fraction: layer.score / 100, color: color, height: 6),
          const SizedBox(height: 8),
          Text(
            'Adds +${_f(layer.frsPoints)} risk points = ${_f(layer.lambda, 2)} × (100 − ${_f(layer.score)})',
            style: _support(color: AppTheme.white60),
          ),
          if (!layer.hasData) ...[
            const SizedBox(height: 8),
            Text(
              'No readings today, so this part counts as fully stable (100) and adds no risk. '
              'It lowers data coverage instead.',
              style: _caption(),
            ),
          ],
          const SizedBox(height: 12),
          for (var i = 0; i < layer.measures.length; i++) ...[
            if (i > 0) const Divider(color: AppTheme.white10, height: 20),
            _MeasureRow(measure: layer.measures[i], layerScore: layer.score),
          ],
        ],
      ),
    );
  }
}

class _MeasureRow extends StatelessWidget {
  final MeasureDetail measure;
  final double layerScore;
  const _MeasureRow({required this.measure, required this.layerScore});

  @override
  Widget build(BuildContext context) {
    final measured = measure.measured;
    final color = _measureColor(measure.key);
    final details = [
      if (measure.reading != null) measure.reading!,
      if (measure.reference != null) measure.reference!,
    ].join('  ·  ');

    return Opacity(
      opacity: measured ? 1.0 : 0.55,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  measure.label,
                  style: AppTypography.inter(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                measured ? measure.subScore!.round().toString() : '—',
                style: AppTypography.inter(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(details, style: _support()),
          ],
          const SizedBox(height: 6),
          _Bar(fraction: measured ? measure.subScore! / 100 : 0, color: color),
          const SizedBox(height: 6),
          Text(
            measured
                ? 'Weight ${(measure.share * 100).round()}%  →  ${_f(measure.points)} of ${_f(layerScore)} points'
                : 'Not measured today — its weight is shared among the other inputs.',
            style: _support(color: AppTheme.white60),
          ),
          const SizedBox(height: 2),
          Text(measure.method, style: _caption()),
        ],
      ),
    );
  }
}

// ── Fall history ─────────────────────────────────────────────────────────────

class _FallHistoryCard extends StatelessWidget {
  final FallHistoryDetail history;
  const _FallHistoryCard({required this.history});

  @override
  Widget build(BuildContext context) {
    Widget line(String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Expanded(child: Text(label, style: _support())),
              Text(value, style: _support(color: Colors.white)),
            ],
          ),
        );

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Fall history', style: _title()),
                    const SizedBox(height: 2),
                    Text(
                      'Past falls are the strongest single predictor of the next one.',
                      style: _support(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    history.normalized.round().toString(),
                    style: AppTypography.inter(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  Text('risk / 100', style: _caption()),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          _Bar(fraction: history.normalized / 100, color: _layerColor('fh'), height: 6),
          const SizedBox(height: 12),
          line('Falls in the last 12 months', '${history.falls}'),
          line('Weighted by recency (90-day half-life)', _f(history.weightedFalls, 2)),
          line('Walking exposure used', '${history.ambulationHours.round()} h'),
          line('Falls per 100 walking hours', _f(history.rate * 100, 2)),
          const SizedBox(height: 4),
          Text(
            'Adds +${_f(history.frsPoints)} risk points = ${_f(history.lambda, 2)} × ${_f(history.normalized)}',
            style: _support(color: AppTheme.white60),
          ),
          const SizedBox(height: 2),
          Text(
            '1 fall per 100 walking hours = 100. Simulated demo falls are never counted.'
            '${history.belowAmbulationFloor ? ' Less than a week of walking data, so a one-week minimum is used.' : ''}',
            style: _caption(),
          ),
        ],
      ),
    );
  }
}

// ── Women's health ───────────────────────────────────────────────────────────

class _WomensHealthCard extends StatelessWidget {
  final WomensHealthDetail detail;
  final double hsiWeight;
  const _WomensHealthCard({required this.detail, required this.hsiWeight});

  @override
  Widget build(BuildContext context) {
    final applicable = detail.applicable && detail.score != null;
    return GlassCard(
      child: Opacity(
        opacity: applicable ? 1.0 : 0.55,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Women\'s health', style: _title())),
                Text(
                  applicable ? detail.score!.round().toString() : '—',
                  style: AppTypography.inter(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (applicable) ...[
              _Bar(fraction: detail.score! / 100, color: AppTheme.womenColor, height: 6),
              const SizedBox(height: 8),
              Text(
                [
                  if (detail.daysSinceLastPeriod != null) 'Cycle day ${detail.daysSinceLastPeriod! + 1}',
                  detail.isPMS ? 'pre-menstrual phase (−20 at full confidence)' : 'no phase penalty',
                  if (detail.confidence != null) 'confidence ${(detail.confidence! * 100).round()}%',
                ].join('  ·  '),
                style: _support(),
              ),
              const SizedBox(height: 6),
              Text(
                'Counts for ${(hsiWeight * 100).round()}% of the stability index. It does not add fall '
                'risk points directly, so a normal cycle is never mistaken for a fall risk.',
                style: _caption(),
              ),
            ] else
              Text(
                'Not included — no cycle data, not applicable, or opted out. The other parts are '
                're-weighted without it.',
                style: _support(),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Coverage ─────────────────────────────────────────────────────────────────

class _CoverageCard extends StatelessWidget {
  final ScoreBreakdown breakdown;
  const _CoverageCard({required this.breakdown});

  @override
  Widget build(BuildContext context) {
    final measured = <String>[];
    final missing = <String>[];
    for (final layer in breakdown.layers) {
      for (final m in layer.measures) {
        (m.measured ? measured : missing).add(m.label);
      }
    }
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('How much of the picture we can see', style: _title()),
              ),
              Text(
                '${breakdown.coverage.round()}%',
                style: AppTypography.inter(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _Bar(fraction: breakdown.coverage / 100, color: AppTheme.gold, height: 6),
          const SizedBox(height: 10),
          Text(
            'Coverage is the weighted share of inputs we actually have. Low coverage means the '
            'score leans on fewer signals, so treat it with more caution.',
            style: _support(),
          ),
          const SizedBox(height: 10),
          Text('Measured: ${measured.isEmpty ? 'none' : measured.join(', ')}', style: _support(color: AppTheme.white60)),
          const SizedBox(height: 4),
          Text('Missing: ${missing.isEmpty ? 'none' : missing.join(', ')}', style: _caption()),
          for (final d in breakdown.coverageDetails) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, color: AppTheme.textSec, size: 14),
                const SizedBox(width: 6),
                Expanded(child: Text(d, style: _caption())),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
