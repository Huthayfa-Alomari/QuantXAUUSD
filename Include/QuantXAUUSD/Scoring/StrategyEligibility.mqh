//+------------------------------------------------------------------+
//| StrategyEligibility.mqh                                          |
//| QUANT_XAUUSD_ENGINE - Architecture v2 Strategy Eligibility Engine |
//|                                                                   |
//| This is an ADDITIONAL, finer-grained gate layered on top of the  |
//| EXISTING (preserved, unchanged) ScoreEngine::IsEligibleInRegime() |
//| base-RegimeType gate - it does not replace it. A signal must pass|
//| BOTH gates to contribute to aggregation.                          |
//|                                                                   |
//| Design philosophy (per explicit instruction): rules here are     |
//| CONSERVATIVE and domain-justified (e.g. "don't fade a fresh      |
//| trend with mean reversion"), NOT an encoding of the specific     |
//| multi-year ablation findings (Momentum+VWAP, Donchian pooled     |
//| weakness, etc.) - those are contested by small sample size and   |
//| belong in the Interaction Matrix as explicitly OPT-IN rules the  |
//| user enables after out-of-sample validation, not baked in here   |
//| as if already proven. See README "Architecture v2 Notes".        |
//+------------------------------------------------------------------+
#ifndef QXE_STRATEGYELIGIBILITY_MQH
#define QXE_STRATEGYELIGIBILITY_MQH

#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Utilities.mqh"

class CStrategyEligibilityEngine
  {
public:
   // Returns the eligibility decision for `strategy` under the current
   // meta-regime, plus a human-readable reason for the [ELIGIBILITY] log.
   EligibilityDecision Evaluate(StrategyType strategy, const MetaRegimeState &meta, string &outReason)
     {
      if(!InpEnableEligibilityEngine)
        {
         outReason = "eligibility engine disabled - base regime gate only";
         return ELIGIBILITY_ALLOW;
        }

      bool trendRegime = (meta.regime == META_TREND_EXPANSION_BULL || meta.regime == META_TREND_EXPANSION_BEAR ||
                           meta.regime == META_TREND_MATURE_BULL || meta.regime == META_TREND_MATURE_BEAR);
      bool rangeRegime = (meta.regime == META_RANGE_LOW_VOL || meta.regime == META_RANGE_NORMAL_VOL);
      bool chopRegime = (meta.regime == META_HIGH_VOL_CHOP);
      bool uncertainRegime = (meta.regime == META_UNCERTAIN);

      switch(strategy)
        {
         // Mean-reversion family: fading a fresh, confirmed trend is
         // textbook adverse-selection - block outright there. Fine in
         // range/chop, where reversion is the actual thesis.
         case STRAT_MEAN_REVERSION:
         case STRAT_BOLLINGER_ZSCORE:
            if(trendRegime)
              {
               outReason = "blocked: mean-reversion strategy in a confirmed trend regime";
               return ELIGIBILITY_BLOCK;
              }
            outReason = "allowed: range/chop regime matches mean-reversion thesis";
            return ELIGIBILITY_ALLOW;

         // Pure trend/momentum/breakout family: nothing to follow in a
         // genuine low-volatility range.
         case STRAT_TREND_FOLLOWING:
         case STRAT_TIME_SERIES_MOMENTUM:
         case STRAT_MOMENTUM_PULLBACK:
         case STRAT_DONCHIAN_BREAKOUT:
         case STRAT_VOLATILITY_BREAKOUT:
            if(meta.regime == META_RANGE_LOW_VOL)
              {
               outReason = "blocked: trend/momentum strategy in a low-volatility range";
               return ELIGIBILITY_BLOCK;
              }
            if(chopRegime)
              {
               outReason = "blocked: trend/momentum strategy in high-vol chop (low efficiency)";
               return ELIGIBILITY_BLOCK;
              }
            outReason = "allowed";
            return ELIGIBILITY_ALLOW;

         // Structure/liquidity: treated as confirmation-capable in any
         // regime (per the ablation finding that these work best as
         // ensemble confirmation, not standalone) - CONFIRMATION_ONLY
         // means it can still feed the Interaction Matrix as a
         // contributor without independently leading a trade, UNLESS
         // InpAllowStandaloneStructureLiquidity is explicitly enabled.
         case STRAT_MARKET_STRUCTURE:
         case STRAT_LIQUIDITY_SWEEP:
            if(!InpAllowStandaloneStructureLiquidity)
              {
               outReason = "confirmation-only: standalone trading disabled by config (see InpAllowStandaloneStructureLiquidity)";
               return ELIGIBILITY_CONFIRMATION_ONLY;
              }
            outReason = "allowed (standalone enabled by config)";
            return ELIGIBILITY_ALLOW;

         case STRAT_VWAP:
            outReason = "allowed - directional constraint (if any) handled per-pair in Interaction Matrix, not blanket-blocked here";
            return ELIGIBILITY_ALLOW;

         case STRAT_OPENING_RANGE_BREAKOUT:
            outReason = "allowed - session gating handled internally by the strategy itself";
            return ELIGIBILITY_ALLOW;

         default:
            outReason = "no specific rule - default allow";
            return ELIGIBILITY_ALLOW;
        }
     }
  };

#endif // QXE_STRATEGYELIGIBILITY_MQH
