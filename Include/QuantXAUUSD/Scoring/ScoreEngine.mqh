//+------------------------------------------------------------------+
//| ScoreEngine.mqh                                                  |
//| QUANT_XAUUSD_ENGINE - Signal aggregation + composite scoring     |
//|                                                                   |
//| Combines SignalAggregator (spec section 21) and the ScoreEngine   |
//| (section 23) into one module: aggregation and scoring are a       |
//| single pass over the same signal list (documented in README).     |
//| Regime priority (section 22) determines which strategies'        |
//| signals are eligible to contribute in the current regime.        |
//+------------------------------------------------------------------+
#ifndef QXE_SCOREENGINE_MQH
#define QXE_SCOREENGINE_MQH

#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Utilities.mqh"
#include "StrategyInteractionMatrix.mqh"

class CScoreEngine
  {
public:
   // Filters `signals` by regime priority, aggregates same-direction
   // votes into a composite score, applies the Strategy Interaction
   // Matrix, and rejects conflicting/insufficient/blocked setups. Only
   // ONE resulting TradeSetup is produced (spec section 21: never let
   // strategies open separate trades).
   //
   // `confirmationOnly[i]` parallel to `signals[i]`: true if the
   // Eligibility Engine marked that strategy CONFIRMATION_ONLY for the
   // current meta-regime - such a signal can still contribute score and
   // participate in the Interaction Matrix, but can never be chosen as
   // the PRIMARY (entry/stop-defining) contributor, and a direction with
   // ONLY confirmation-only support (no ALLOW-tier signal) is rejected.
   TradeSetup        Aggregate(const Signal &signals[], const bool &confirmationOnly[], int count,
                                const MarketState &state, CStrategyInteractionMatrix *interactionMatrix)
     {
      TradeSetup setup;
      setup.valid = false;
      setup.direction = SIGNAL_NONE;
      setup.rawScore = 0.0;
      setup.interactionModifier = 0.0;
      setup.compositeScore = 0.0;
      setup.regime = state.regime;
      setup.metaRegime = state.meta.regime;
      setup.metaRegimeConfidence = state.meta.confidence;
      setup.primaryStrategy = STRAT_TREND_FOLLOWING; // placeholder until resolved; setup.valid=false until then
      setup.contributingStrategies = "";
      setup.contributorEligibility = "";
      setup.contributorCount = 0;
      setup.interactionReason = "";
      setup.rejectReason = "";

      if(state.regime == REGIME_NO_TRADE)
        {
         setup.rejectReason = "Regime = NO_TRADE";
         return setup;
        }
      if(state.regime == REGIME_TRANSITION)
        {
         setup.rejectReason = "Regime = TRANSITION (reduced risk / no trade)";
         return setup;
        }

      double buyScore = 0.0, sellScore = 0.0;
      int buyVotes = 0, sellVotes = 0;
      int buyAllowVotes = 0, sellAllowVotes = 0; // excludes confirmation-only
      string buyContributors = "", sellContributors = "";
      string buyEligibility = "", sellEligibility = "";
      bool buyPresent[]; bool sellPresent[];
      ArrayResize(buyPresent, STRAT_COUNT);
      ArrayResize(sellPresent, STRAT_COUNT);
      ArrayInitialize(buyPresent, false);
      ArrayInitialize(sellPresent, false);

      // Track the PRIMARY (highest single weighted-score, ALLOW-tier
      // only) contributor per direction - its entry/stop/target are used
      // directly. Stops are NEVER averaged across strategies (repair
      // spec: "a mean stop price has no structural meaning").
      double buyPrimaryWeighted = -1.0, sellPrimaryWeighted = -1.0;
      int buyPrimaryIdx = -1, sellPrimaryIdx = -1;

      for(int i = 0; i < count; i++)
        {
         if(signals[i].direction == SIGNAL_NONE)
            continue;
         if(!IsEligibleInRegime(signals[i].strategy, state.regime))
            continue;

         double weighted = WeightedScore(signals[i]);
         bool isConfirmOnly = confirmationOnly[i];

         if(signals[i].direction == SIGNAL_BUY)
           {
            buyScore += weighted;
            buyVotes++;
            if(!isConfirmOnly) buyAllowVotes++;
            buyPresent[signals[i].strategy] = true;
            buyContributors += (buyContributors == "" ? "" : "+") + QXE_StrategyToString(signals[i].strategy);
            buyEligibility += (buyEligibility == "" ? "" : "|") + QXE_StrategyToString(signals[i].strategy) +
                               ":" + (isConfirmOnly ? "CONFIRMATION_ONLY" : "ALLOW");
            if(!isConfirmOnly && weighted > buyPrimaryWeighted)
              {
               buyPrimaryWeighted = weighted;
               buyPrimaryIdx = i;
              }
           }
         else
           {
            sellScore += weighted;
            sellVotes++;
            if(!isConfirmOnly) sellAllowVotes++;
            sellPresent[signals[i].strategy] = true;
            sellContributors += (sellContributors == "" ? "" : "+") + QXE_StrategyToString(signals[i].strategy);
            sellEligibility += (sellEligibility == "" ? "" : "|") + QXE_StrategyToString(signals[i].strategy) +
                                ":" + (isConfirmOnly ? "CONFIRMATION_ONLY" : "ALLOW");
            if(!isConfirmOnly && weighted > sellPrimaryWeighted)
              {
               sellPrimaryWeighted = weighted;
               sellPrimaryIdx = i;
              }
           }
        }

      // A direction with zero ALLOW-tier votes cannot lead a trade, even
      // if confirmation-only strategies fired for it (spec: "may
      // contribute to interaction bonus but not lead a trade alone").
      if(buyAllowVotes == 0) { buyVotes = 0; buyScore = 0.0; }
      if(sellAllowVotes == 0) { sellVotes = 0; sellScore = 0.0; }

      // Conflict resolution: if both sides have votes, take the stronger
      // side only if it clearly dominates; otherwise reject (no trade).
      SignalDirection finalDir = SIGNAL_NONE;
      double finalScore = 0.0;
      int primaryIdx = -1;
      string contributors = "";
      string eligibilityStr = "";
      int votes = 0;
      bool present[]; ArrayResize(present, STRAT_COUNT);

      if(buyVotes > 0 && sellVotes == 0)
        {
         finalDir = SIGNAL_BUY; finalScore = buyScore; votes = buyVotes;
         primaryIdx = buyPrimaryIdx; contributors = buyContributors; eligibilityStr = buyEligibility;
         ArrayCopy(present, buyPresent);
        }
      else if(sellVotes > 0 && buyVotes == 0)
        {
         finalDir = SIGNAL_SELL; finalScore = sellScore; votes = sellVotes;
         primaryIdx = sellPrimaryIdx; contributors = sellContributors; eligibilityStr = sellEligibility;
         ArrayCopy(present, sellPresent);
        }
      else if(buyVotes > 0 && sellVotes > 0)
        {
         if(buyScore > sellScore * 1.5)
           {
            finalDir = SIGNAL_BUY; finalScore = buyScore; votes = buyVotes;
            primaryIdx = buyPrimaryIdx; contributors = buyContributors; eligibilityStr = buyEligibility;
            ArrayCopy(present, buyPresent);
           }
         else if(sellScore > buyScore * 1.5)
           {
            finalDir = SIGNAL_SELL; finalScore = sellScore; votes = sellVotes;
            primaryIdx = sellPrimaryIdx; contributors = sellContributors; eligibilityStr = sellEligibility;
            ArrayCopy(present, sellPresent);
           }
         else
           {
            setup.rejectReason = "Conflicting signals (BUY and SELL both present, no clear dominance)";
            return setup;
           }
        }
      else
        {
         setup.rejectReason = "No qualifying ALLOW-tier signals (confirmation-only support does not count alone)";
         return setup;
        }

      if(primaryIdx < 0)
        {
         setup.rejectReason = "Internal error: no primary contributor resolved";
         return setup;
        }

      // Entry/stop/target come DIRECTLY from the primary (highest-weighted
      // ALLOW-tier) signal - never averaged across strategies.
      double entry = signals[primaryIdx].entry;
      double stop = signals[primaryIdx].stop;
      double target = signals[primaryIdx].target;
      StrategyType primaryStrategy = signals[primaryIdx].strategy;

      // Explicit directional SL validation (repair spec: "DIRECTIONAL SL
      // VALIDATION") - MathAbs(entry-stop) alone is not sufficient; the
      // stop must be on the correct SIDE of entry for the direction traded.
      if(finalDir == SIGNAL_BUY && stop >= entry)
        {
         setup.rejectReason = StringFormat("Invalid BUY stop: SL %.2f is not below entry %.2f", stop, entry);
         return setup;
        }
      if(finalDir == SIGNAL_SELL && stop <= entry)
        {
         setup.rejectReason = StringFormat("Invalid SELL stop: SL %.2f is not above entry %.2f", stop, entry);
         return setup;
        }

      // ---- Strategy Interaction Matrix (Architecture v2) ----
      bool interactionBlocked = false;
      string interactionReason = "";
      double interactionModifier = 0.0;
      if(CheckPointer(interactionMatrix) != POINTER_INVALID)
         interactionModifier = interactionMatrix.Evaluate(present, state.meta, interactionBlocked, interactionReason);

      if(interactionBlocked)
        {
         setup.rejectReason = "Blocked by Interaction Matrix: " + interactionReason;
         setup.interactionReason = interactionReason;
         return setup;
        }

      // Session and volatility scoring components (spec section 23).
      double sessionBonus = IsFavorableSession(state.session) ? InpWeightSession : 0.0;
      double volBonus = (state.regime == REGIME_VOL_EXPANSION) ? InpWeightVolatility : InpWeightVolatility * 0.5;
      double entryQualityBonus = MathMin(InpWeightEntryQuality, votes * 1.5);

      double rawTotal = finalScore + sessionBonus + volBonus + entryQualityBonus;
      double composite = QXE_Clamp(rawTotal + interactionModifier, QXE_SCORE_MIN, QXE_SCORE_MAX);

      setup.direction = finalDir;
      setup.rawScore = rawTotal;
      setup.interactionModifier = interactionModifier;
      setup.interactionReason = interactionReason;
      setup.compositeScore = composite;
      setup.entry = entry;
      setup.stopLoss = stop;
      setup.primaryStrategy = primaryStrategy;
      setup.contributorCount = votes;

      double risk = MathAbs(entry - stop);
      setup.takeProfit1 = (finalDir == SIGNAL_BUY) ? entry + risk * InpTP1R : entry - risk * InpTP1R;
      setup.takeProfit2 = (finalDir == SIGNAL_BUY) ? entry + risk * InpTP2R : entry - risk * InpTP2R;
      setup.runnerTarget = target;
      setup.contributingStrategies = contributors;
      setup.contributorEligibility = eligibilityStr;

      if(EnableScoreFilter && composite < InpMinScore)
        {
         setup.valid = false;
         setup.rejectReason = StringFormat("Composite score %.1f below minimum %.1f", composite, InpMinScore);
         return setup;
        }

      setup.valid = true;
      return setup;
     }

private:
   // Regime priority table (spec section 22).
   bool              IsEligibleInRegime(StrategyType strat, RegimeType regime) const
     {
      switch(regime)
        {
         case REGIME_TREND_BULL:
         case REGIME_TREND_BEAR:
            return (strat == STRAT_TREND_FOLLOWING || strat == STRAT_TIME_SERIES_MOMENTUM ||
                    strat == STRAT_MOMENTUM_PULLBACK || strat == STRAT_MARKET_STRUCTURE ||
                    strat == STRAT_LIQUIDITY_SWEEP || strat == STRAT_VWAP);

         case REGIME_RANGE:
            return (strat == STRAT_MEAN_REVERSION || strat == STRAT_BOLLINGER_ZSCORE ||
                    strat == STRAT_VWAP);

         case REGIME_VOL_EXPANSION:
            return (strat == STRAT_VOLATILITY_BREAKOUT || strat == STRAT_TIME_SERIES_MOMENTUM ||
                    strat == STRAT_DONCHIAN_BREAKOUT || strat == STRAT_OPENING_RANGE_BREAKOUT);

         case REGIME_VOL_CONTRACTION:
            // Contraction precedes expansion - only breakout-anticipation
            // strategies with tight risk are allowed; conservatively, none
            // by default (waiting for the actual expansion/breakout).
            return false;

         default:
            return false;
        }
     }

   double            WeightedScore(const Signal &s) const
     {
      // Each strategy's raw 0..100 score is treated as its HTF-trend /
      // momentum / structure / liquidity / displacement / FVG component
      // already baked in by the strategy itself; here we simply scale it
      // by the strategy's relative weight bucket for cross-strategy fairness.
      double weight = 1.0;
      switch(s.strategy)
        {
         case STRAT_TREND_FOLLOWING:        weight = InpWeightHTFTrend / 20.0; break;
         case STRAT_TIME_SERIES_MOMENTUM:   weight = InpWeightMomentum / 10.0; break;
         case STRAT_MARKET_STRUCTURE:       weight = InpWeightStructure / 15.0; break;
         case STRAT_LIQUIDITY_SWEEP:        weight = InpWeightLiquidity / 15.0; break;
         default:                           weight = 1.0; break;
        }
      return s.score * weight;
     }

   bool              IsFavorableSession(SessionType s) const
     {
      return (s == SESSION_LONDON || s == SESSION_NEWYORK || s == SESSION_LONDON_NY_OVERLAP);
     }
  };

#endif // QXE_SCOREENGINE_MQH
