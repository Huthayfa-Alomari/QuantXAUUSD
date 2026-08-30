//+------------------------------------------------------------------+
//| MetaRegimeClassifier.mqh                                         |
//| QUANT_XAUUSD_ENGINE - Architecture v2 Meta-Regime Classifier      |
//|                                                                   |
//| Deterministic, rule-based (NOT a black box - spec sec. 12: "start |
//| deterministic / rule-based, not ML"). Consumes the ALREADY-       |
//| computed MarketState (which carries the base RegimeType from the |
//| unchanged, preserved RegimeEngine, plus the v2 feature set: EMA   |
//| slopes, D1/H4 bias/alignment, range/trend efficiency, ATR         |
//| percentile) and refines it into one of 11 richer meta-regimes.    |
//|                                                                   |
//| This module does NOT replace RegimeEngine - it is a second,      |
//| independent layer on top of it, exactly as the spec's pipeline    |
//| diagram shows (Market State -> Meta-Regime Classifier, with the   |
//| base RegimeEngine's output as one of the Market State inputs).    |
//+------------------------------------------------------------------+
#ifndef QXE_METAREGIMECLASSIFIER_MQH
#define QXE_METAREGIMECLASSIFIER_MQH

#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Utilities.mqh"

class CMetaRegimeClassifier
  {
public:
   // Fills state.meta based on fields already present in `state`
   // (assumes RegimeEngine::Evaluate and the Market State Engine's
   // extra feature computation already ran this cycle).
   void              Classify(MarketState &state)
     {
      MetaRegimeState m;
      m.regime = META_UNCERTAIN;
      m.direction = 0;
      m.confidence = 0.5;
      m.trendStrength = MathAbs(state.trendScore);
      m.volatilityScore = state.volatilityScore;
      m.efficiencyScore = state.rangeEfficiency;
      m.d1H4Aligned = state.d1H4Aligned;

      bool expansion = (state.atrPercentile >= InpVolExpansionPct);
      bool contraction = (state.atrPercentile <= InpVolContractionPct);
      bool highEfficiency = (state.rangeEfficiency >= 0.55) || (state.trendEfficiency >= 0.45);
      bool lowEfficiency = (state.rangeEfficiency <= 0.35) && (state.trendEfficiency <= 0.25);

      // --- Trend states: base regime already says BULL/BEAR; refine
      //     into EXPANSION (fresh, still accelerating - high ATR
      //     percentile + high efficiency) vs MATURE (established but
      //     no longer expanding in volatility terms). ---
      if(state.regime == REGIME_TREND_BULL)
        {
         m.direction = 1;
         m.regime = (expansion && highEfficiency) ? META_TREND_EXPANSION_BULL : META_TREND_MATURE_BULL;
         m.confidence = QXE_Clamp(0.5 + (m.trendStrength / 200.0) + (state.d1H4Aligned ? 0.15 : 0.0), 0.0, 1.0);
        }
      else if(state.regime == REGIME_TREND_BEAR)
        {
         m.direction = -1;
         m.regime = (expansion && highEfficiency) ? META_TREND_EXPANSION_BEAR : META_TREND_MATURE_BEAR;
         m.confidence = QXE_Clamp(0.5 + (m.trendStrength / 200.0) + (state.d1H4Aligned ? 0.15 : 0.0), 0.0, 1.0);
        }
      else if(state.regime == REGIME_RANGE)
        {
         m.direction = 0;
         m.regime = contraction ? META_RANGE_LOW_VOL : META_RANGE_NORMAL_VOL;
         m.confidence = QXE_Clamp(0.5 + (state.rangeScore / 200.0), 0.0, 1.0);
        }
      else if(state.regime == REGIME_VOL_EXPANSION)
        {
         m.direction = 0;
         // Expansion with low efficiency (lots of range, little net
         // progress) is choppy volatility, not a clean breakout attempt.
         m.regime = lowEfficiency ? META_HIGH_VOL_CHOP : META_BREAKOUT_TRANSITION;
         m.confidence = QXE_Clamp(0.4 + (state.volatilityScore / 250.0), 0.0, 1.0);
        }
      else if(state.regime == REGIME_VOL_CONTRACTION)
        {
         m.direction = 0;
         m.regime = META_VOL_CONTRACTION;
         m.confidence = 0.55;
        }
      else if(state.regime == REGIME_TRANSITION)
        {
         m.direction = 0;
         m.regime = META_UNCERTAIN;
         m.confidence = 0.35;
        }
      else // REGIME_NO_TRADE
        {
         m.direction = 0;
         m.regime = expansion ? META_VOL_EXPANSION : META_UNCERTAIN;
         m.confidence = 0.3;
        }

      state.meta = m;
     }
  };

#endif // QXE_METAREGIMECLASSIFIER_MQH
