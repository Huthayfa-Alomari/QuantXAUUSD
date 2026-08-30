//+------------------------------------------------------------------+
//| RegimeEngine.mqh                                                 |
//| QUANT_XAUUSD_ENGINE - Market regime classification               |
//|                                                                   |
//| REPAIR PASS changes: the previous version computed `adxH4` and    |
//| then never referenced it again - exactly the "calculate H4        |
//| variables and then ignore them" bug the repair spec called out.  |
//| This version keeps the SAME overall architecture and regime set  |
//| (not replaced, per spec) but makes every input it gathers         |
//| actually count toward the score, and adds two cheap inputs the    |
//| architecture was already positioned to use (D1 bias, range        |
//| efficiency). No new configurable thresholds were introduced -     |
//| these are small, fixed-weight, additive contributions in the      |
//| same style as the existing scoring, to avoid overfitting new       |
//| knobs onto backtest-specific behavior.                             |
//|                                                                   |
//| Combines TrendRegime + RangeRegime + VolatilityRegime scoring     |
//| (spec: Regime/TrendRegime.mqh, RangeRegime.mqh, VolatilityRegime |
//| .mqh) into one cohesive engine - see README "Architecture Notes". |
//+------------------------------------------------------------------+
#ifndef QXE_REGIMEENGINE_MQH
#define QXE_REGIMEENGINE_MQH

#include "../Data/MarketData.mqh"
#include "../Data/TimeframeAnalytics.mqh"
#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Utilities.mqh"

class CRegimeEngine
  {
public:
   void              Evaluate(CMarketData *md, MarketState &state)
     {
      CTimeframeData *h1 = md.H1();
      CTimeframeData *h4 = md.H4();
      CTimeframeData *d1 = md.D1();

      double emaSlope = h1.EMA200SlopePoints(20);
      double closeH1 = h1.Close(1);
      double ema200H1 = h1.EMA200(1);
      double adxH1 = h1.ADX(1);
      double adxH4 = h4.ADX(1);
      double h4Slope = h4.EMA200SlopePoints(20);
      double closeD1 = d1.Close(1);
      double ema200D1 = d1.EMA200(1);

      // ---- Trend score (H1 base, now with H4 confirmation and D1 bias) ----
      double trendScore = 0.0;
      bool priceAboveEma = closeH1 > ema200H1;
      bool priceBelowEma = closeH1 < ema200H1;
      bool slopeUp = emaSlope > InpEMASlopeMinPoints;
      bool slopeDown = emaSlope < -InpEMASlopeMinPoints;
      bool adxTrending = (adxH1 >= InpADXTrendThreshold);

      if(priceAboveEma) trendScore += 35.0;
      if(priceBelowEma) trendScore -= 35.0;
      if(slopeUp)   trendScore += 35.0;
      if(slopeDown) trendScore -= 35.0;
      if(adxTrending)
         trendScore += (trendScore >= 0 ? 30.0 : -30.0);

      // H4 confirmation: agreeing H4 slope + trending H4 ADX reinforces
      // the H1 read; a contradicting H4 slope dampens it. This is what
      // `adxH4`/`h4Slope` were computed for but previously discarded.
      bool h4TrendingUp = (h4Slope > InpEMASlopeMinPoints) && (adxH4 >= InpADXRangeThreshold);
      bool h4TrendingDown = (h4Slope < -InpEMASlopeMinPoints) && (adxH4 >= InpADXRangeThreshold);

      if(trendScore > 0.0)
        {
         if(h4TrendingUp)   trendScore += 10.0;
         if(h4TrendingDown) trendScore -= 15.0; // contradiction penalized harder than agreement is rewarded
        }
      else if(trendScore < 0.0)
        {
         if(h4TrendingDown) trendScore -= 10.0;
         if(h4TrendingUp)   trendScore += 15.0;
        }

      // D1 bias: a light directional input, same +/-10 weight regardless
      // of direction so it cannot dominate the H1/H4 read on its own.
      if(closeD1 > ema200D1) trendScore += 10.0;
      if(closeD1 < ema200D1) trendScore -= 10.0;

      trendScore = QXE_Clamp(trendScore, -100.0, 100.0);

      // ---- Range score (now with a range-efficiency input) ----
      double rangeScore = 0.0;
      if(adxH1 <= InpADXRangeThreshold)
         rangeScore += 40.0;
      if(MathAbs(emaSlope) < InpEMASlopeMinPoints)
         rangeScore += 40.0;

      // Range efficiency: how much of the bar's total range translated
      // into net directional movement, averaged over recent bars. Low
      // efficiency (lots of wick, little net progress) is characteristic
      // of a genuine range; high efficiency looks more like a trend even
      // if ADX hasn't confirmed it yet.
      double efficiency = QXE_AverageRangeEfficiency(h1, 10);
      if(efficiency < 0.35)
         rangeScore += 20.0;
      else if(efficiency > 0.65)
         rangeScore -= 20.0;
      rangeScore = QXE_Clamp(rangeScore, 0.0, 100.0);

      // ---- Volatility score (percentile-based, unchanged core; range
      //      efficiency is intentionally NOT mixed in here - it belongs
      //      to range/trend character, not volatility magnitude) ----
      double atrPercentile = md.ATRPercentile(InpATRPercentileLookback);
      double volatilityScore = atrPercentile * 100.0;

      // ---- Resolve regime (same regime set and thresholds as before -
      //      architecture preserved, per spec) ----
      RegimeType regime;
      bool trendUp = (trendScore >= 60.0);
      bool trendDown = (trendScore <= -60.0);
      bool isRanging = (rangeScore >= 70.0 && !trendUp && !trendDown);
      bool isExpansion = (atrPercentile >= InpVolExpansionPct);
      bool isContraction = (atrPercentile <= InpVolContractionPct);

      if(trendUp && !isRanging)
         regime = REGIME_TREND_BULL;
      else if(trendDown && !isRanging)
         regime = REGIME_TREND_BEAR;
      else if(isExpansion && !trendUp && !trendDown)
         regime = REGIME_VOL_EXPANSION;
      else if(isContraction && isRanging)
         regime = REGIME_VOL_CONTRACTION;
      else if(isRanging)
         regime = REGIME_RANGE;
      else
        {
         bool conflicting = (trendScore > 20.0 && trendScore < 60.0) ||
                             (trendScore < -20.0 && trendScore > -60.0);
         regime = conflicting ? REGIME_TRANSITION : REGIME_NO_TRADE;
        }

      state.trendScore = trendScore;
      state.rangeScore = rangeScore;
      state.volatilityScore = volatilityScore;
      state.atrPercentile = atrPercentile;
      state.regimeScore = MathMax(MathAbs(trendScore), MathMax(rangeScore, volatilityScore));
      state.regime = regime;
     }
  };

#endif // QXE_REGIMEENGINE_MQH
