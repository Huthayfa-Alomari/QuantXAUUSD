#ifndef QXE_REGIMEENGINE_MQH
#define QXE_REGIMEENGINE_MQH

#include "../Data/MarketData.mqh"
#include "../Data/TimeframeAnalytics.mqh"
#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Utilities.mqh"

class CRegimeEngine
  {
private:
   RegimeType        m_stableRegime;
   bool              m_initialized;

public:
                     CRegimeEngine(void) : m_stableRegime(REGIME_NO_TRADE), m_initialized(false) {}

   void              Evaluate(CMarketData *md, MarketState &state)
     {
      CTimeframeData *h1 = md.H1();
      CTimeframeData *h4 = md.H4();
      CTimeframeData *d1 = md.D1();

      double emaSlope = h1.EMA200SlopePoints(20);
      double closeH1 = h1.Close(1);
      double ema200H1 = h1.EMA200(1);
      double adxH1 = h1.ADX(1);
      double plusH1 = h1.ADXPlus(1);
      double minusH1 = h1.ADXMinus(1);

      double adxH4 = h4.ADX(1);
      double plusH4 = h4.ADXPlus(1);
      double minusH4 = h4.ADXMinus(1);
      double h4Slope = h4.EMA200SlopePoints(20);
      double closeD1 = d1.Close(1);
      double ema200D1 = d1.EMA200(1);

      state.plusDIH1 = plusH1;
      state.minusDIH1 = minusH1;
      state.plusDIH4 = plusH4;
      state.minusDIH4 = minusH4;

      double trendScore = 0.0;
      if(closeH1 > ema200H1) trendScore += 35.0;
      if(closeH1 < ema200H1) trendScore -= 35.0;
      if(emaSlope > InpEMASlopeMinPoints) trendScore += 35.0;
      if(emaSlope < -InpEMASlopeMinPoints) trendScore -= 35.0;

      bool adxBull = (adxH1 >= InpADXTrendThreshold && plusH1 > minusH1);
      bool adxBear = (adxH1 >= InpADXTrendThreshold && minusH1 > plusH1);
      if(adxBull) trendScore += 30.0;
      if(adxBear) trendScore -= 30.0;

      bool h4TrendingUp = (h4Slope > InpEMASlopeMinPoints) &&
                          (adxH4 >= InpADXTrendThreshold) &&
                          (plusH4 > minusH4);
      bool h4TrendingDown = (h4Slope < -InpEMASlopeMinPoints) &&
                            (adxH4 >= InpADXTrendThreshold) &&
                            (minusH4 > plusH4);

      if(trendScore > 0.0)
        {
         if(h4TrendingUp) trendScore += 10.0;
         if(h4TrendingDown) trendScore -= 15.0;
        }
      else if(trendScore < 0.0)
        {
         if(h4TrendingDown) trendScore -= 10.0;
         if(h4TrendingUp) trendScore += 15.0;
        }

      if(closeD1 > ema200D1) trendScore += 10.0;
      if(closeD1 < ema200D1) trendScore -= 10.0;
      trendScore = QXE_Clamp(trendScore, -100.0, 100.0);

      double rangeScore = 0.0;
      if(adxH1 <= InpADXRangeThreshold) rangeScore += 40.0;
      if(MathAbs(emaSlope) < InpEMASlopeMinPoints) rangeScore += 40.0;

      double efficiency = QXE_AverageRangeEfficiency(h1, InpRegimeEfficiencyLookback);
      if(efficiency < InpRangeEfficiencyMax) rangeScore += 20.0;
      else if(efficiency > InpTrendEfficiencyMin) rangeScore -= 20.0;
      rangeScore = QXE_Clamp(rangeScore, 0.0, 100.0);

      double atrPercentile = md.ATRPercentile(InpATRPercentileLookback);
      double volatilityScore = atrPercentile * 100.0;

      RegimeType raw = ResolveRaw(trendScore, rangeScore, atrPercentile);
      RegimeType stable = ApplyHysteresis(raw, trendScore, rangeScore, atrPercentile);

      state.rawRegime = raw;
      state.stableRegime = stable;
      state.trendScore = trendScore;
      state.rangeScore = rangeScore;
      state.volatilityScore = volatilityScore;
      state.atrPercentile = atrPercentile;
      state.regimeScore = MathMax(MathAbs(trendScore), MathMax(rangeScore, volatilityScore));
      state.regime = stable;
     }

private:
   RegimeType        ResolveRaw(double trendScore, double rangeScore, double atrPercentile) const
     {
      bool trendUp = (trendScore >= InpTrendEnterScore);
      bool trendDown = (trendScore <= -InpTrendEnterScore);
      bool isRanging = (rangeScore >= InpRangeEnterScore && !trendUp && !trendDown);
      bool isExpansion = (atrPercentile >= InpVolExpansionPct);
      bool isContraction = (atrPercentile <= InpVolContractionPct);

      if(trendUp && !isRanging) return REGIME_TREND_BULL;
      if(trendDown && !isRanging) return REGIME_TREND_BEAR;
      if(isExpansion && !trendUp && !trendDown) return REGIME_VOL_EXPANSION;
      if(isContraction && isRanging) return REGIME_VOL_CONTRACTION;
      if(isRanging) return REGIME_RANGE;

      bool conflicting = (trendScore > 20.0 && trendScore < InpTrendEnterScore) ||
                         (trendScore < -20.0 && trendScore > -InpTrendEnterScore);
      return conflicting ? REGIME_TRANSITION : REGIME_NO_TRADE;
     }

   RegimeType        ApplyHysteresis(RegimeType raw, double trendScore, double rangeScore, double atrPercentile)
     {
      if(!m_initialized)
        {
         m_stableRegime = raw;
         m_initialized = true;
         return m_stableRegime;
        }

      if(m_stableRegime == REGIME_TREND_BULL && trendScore >= InpTrendExitScore)
         return m_stableRegime;
      if(m_stableRegime == REGIME_TREND_BEAR && trendScore <= -InpTrendExitScore)
         return m_stableRegime;
      if(m_stableRegime == REGIME_RANGE && rangeScore >= InpRangeExitScore)
         return m_stableRegime;
      if(m_stableRegime == REGIME_VOL_EXPANSION && atrPercentile >= InpVolExpansionExitPct)
         return m_stableRegime;
      if(m_stableRegime == REGIME_VOL_CONTRACTION && atrPercentile <= InpVolContractionExitPct)
         return m_stableRegime;

      m_stableRegime = raw;
      return m_stableRegime;
     }
  };

#endif
