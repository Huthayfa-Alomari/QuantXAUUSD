//+------------------------------------------------------------------+
//| StrategyEligibility.mqh                                          |
//| QUANT_XAUUSD_ENGINE - Architecture v2 Strategy Eligibility Engine |
//| Direction-aware controlled research pass                          |
//+------------------------------------------------------------------+
#ifndef QXE_STRATEGYELIGIBILITY_MQH
#define QXE_STRATEGYELIGIBILITY_MQH

#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Utilities.mqh"

class CStrategyEligibilityEngine
  {
public:
   // Direction-aware eligibility decision.
   //
   // Controlled multi-year research rules currently encoded:
   // 1) TSM + META_TREND_MATURE_BEAR + SELL  => BLOCK
   // 2) TSM + META_BREAKOUT_TRANSITION + BUY => BLOCK
   // 3) TSM + META_TREND_MATURE_BULL + SELL  => BLOCK
   //
   // All other pre-existing conservative eligibility rules are preserved.
   EligibilityDecision Evaluate(StrategyType strategy,
                                const MetaRegimeState &meta,
                                SignalDirection direction,
                                string &outReason)
     {
      if(!InpEnableEligibilityEngine)
        {
         outReason = "eligibility engine disabled - base regime gate only";
         return ELIGIBILITY_ALLOW;
        }

      bool trendRegime =
         (meta.regime == META_TREND_EXPANSION_BULL ||
          meta.regime == META_TREND_EXPANSION_BEAR ||
          meta.regime == META_TREND_MATURE_BULL ||
          meta.regime == META_TREND_MATURE_BEAR);

      bool rangeRegime =
         (meta.regime == META_RANGE_LOW_VOL ||
          meta.regime == META_RANGE_NORMAL_VOL);

      bool chopRegime = (meta.regime == META_HIGH_VOL_CHOP);

      // ---------------------------------------------------------------
      // Controlled multi-year directional filters.
      //
      // These rules intentionally apply ONLY to TimeSeriesMomentum and
      // ONLY to the exact regime + direction combinations validated by
      // the cleaned 2022-2026 telemetry dataset. No blanket directional
      // ban is introduced.
      // ---------------------------------------------------------------
      if(strategy == STRAT_TIME_SERIES_MOMENTUM)
        {
         if(meta.regime == META_TREND_MATURE_BEAR &&
            direction == SIGNAL_SELL)
           {
            outReason =
               "blocked: research rule TSM SELL in META_TREND_MATURE_BEAR";
            return ELIGIBILITY_BLOCK;
           }

         if(meta.regime == META_BREAKOUT_TRANSITION &&
            direction == SIGNAL_BUY)
           {
            outReason =
               "blocked: research rule TSM BUY in META_BREAKOUT_TRANSITION";
            return ELIGIBILITY_BLOCK;
           }

         if(meta.regime == META_TREND_MATURE_BULL &&
            direction == SIGNAL_SELL)
           {
            outReason =
               "blocked: research rule TSM SELL in META_TREND_MATURE_BULL";
            return ELIGIBILITY_BLOCK;
           }
        }

      switch(strategy)
        {
         // Mean-reversion family: fading a fresh, confirmed trend is
         // adverse-selection. Preserve the existing conservative gate.
         case STRAT_MEAN_REVERSION:
         case STRAT_BOLLINGER_ZSCORE:
            if(trendRegime)
              {
               outReason =
                  "blocked: mean-reversion strategy in a confirmed trend regime";
               return ELIGIBILITY_BLOCK;
              }

            outReason =
               "allowed: range/chop regime matches mean-reversion thesis";
            return ELIGIBILITY_ALLOW;

         // Trend/momentum/breakout family.
         case STRAT_TREND_FOLLOWING:
         case STRAT_TIME_SERIES_MOMENTUM:
         case STRAT_MOMENTUM_PULLBACK:
         case STRAT_DONCHIAN_BREAKOUT:
         case STRAT_VOLATILITY_BREAKOUT:
            if(meta.regime == META_RANGE_LOW_VOL)
              {
               outReason =
                  "blocked: trend/momentum strategy in a low-volatility range";
               return ELIGIBILITY_BLOCK;
              }

            if(chopRegime)
              {
               outReason =
                  "blocked: trend/momentum strategy in high-vol chop (low efficiency)";
               return ELIGIBILITY_BLOCK;
              }

            outReason = "allowed";
            return ELIGIBILITY_ALLOW;

         // Structure/liquidity remain confirmation-capable.
         case STRAT_MARKET_STRUCTURE:
         case STRAT_LIQUIDITY_SWEEP:
            if(!InpAllowStandaloneStructureLiquidity)
              {
               outReason =
                  "confirmation-only: standalone trading disabled by config "
                  "(see InpAllowStandaloneStructureLiquidity)";
               return ELIGIBILITY_CONFIRMATION_ONLY;
              }

            outReason = "allowed (standalone enabled by config)";
            return ELIGIBILITY_ALLOW;

         case STRAT_VWAP:
            outReason =
               "allowed - directional constraint (if any) handled per-pair "
               "in Interaction Matrix, not blanket-blocked here";
            return ELIGIBILITY_ALLOW;

         case STRAT_OPENING_RANGE_BREAKOUT:
            outReason =
               "allowed - session gating handled internally by the strategy itself";
            return ELIGIBILITY_ALLOW;

         default:
            outReason = "no specific rule - default allow";
            return ELIGIBILITY_ALLOW;
        }
     }
  };

#endif // QXE_STRATEGYELIGIBILITY_MQH
