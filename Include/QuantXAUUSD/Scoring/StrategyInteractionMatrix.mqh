//+------------------------------------------------------------------+
//| StrategyInteractionMatrix.mqh                                    |
//| QUANT_XAUUSD_ENGINE - Architecture v2 Interaction Matrix          |
//|                                                                   |
//| Corrects the implicit assumption in the base ScoreEngine that     |
//| "more confluence = better" by letting SPECIFIC pairs carry a      |
//| score modifier, a risk multiplier, and (optionally) an outright   |
//| block, instead of purely additive scoring.                        |
//|                                                                   |
//| Extensible: rules live in a small internal table (StrategyPairRule|
//| array) rather than an if/else chain, so adding a new pair is one  |
//| Register() call. Every rule that reflects a SPECIFIC multi-year   |
//| finding (Momentum+Structure, Momentum+VWAP, Momentum+Donchian) is |
//| gated behind its own Config toggle, defaulting OFF - see the      |
//| toggles' comments in Config.mqh for why.                          |
//+------------------------------------------------------------------+
#ifndef QXE_STRATEGYINTERACTIONMATRIX_MQH
#define QXE_STRATEGYINTERACTIONMATRIX_MQH

#include "../Core/Types.mqh"
#include "../Core/Config.mqh"

struct StrategyPairRule
  {
   StrategyType      a;
   StrategyType      b;
   bool              enabled;
   bool              blocks;         // if true, the pair being simultaneously present blocks the trade outright
   double            scoreModifier;  // added to composite score if both a and b contributed
   double            riskMultiplier; // multiplies the effective risk% if this pair fires (1.0 = no change)
   bool              restrictToTrendExpansion; // if true, `blocks` applies UNLESS meta-regime is a trend-expansion/breakout state
   string            reason;
  };

class CStrategyInteractionMatrix
  {
private:
   StrategyPairRule  m_rules[];
   bool              m_initialized;

public:
   void              Init(void)
     {
      ArrayResize(m_rules, 0);

      RegisterRule(STRAT_TIME_SERIES_MOMENTUM, STRAT_MARKET_STRUCTURE,
                   InpInteraction_MomentumStructure_Bonus, false,
                   InpInteraction_MomentumStructure_BonusPts, 1.0, false,
                   "STRUCTURE_CONFIRMATION");

      RegisterRule(STRAT_TIME_SERIES_MOMENTUM, STRAT_VWAP,
                   InpInteraction_MomentumVWAP_Penalty, false,
                   InpInteraction_MomentumVWAP_PenaltyPts, 1.0, false,
                   "MOMENTUM_VWAP_PENALTY");

      // Momentum+Donchian: not a bonus/penalty rule but a regime
      // restriction - blocks the PAIR unless the meta-regime is an
      // expansion/breakout state. Modeled here as a blocking rule with
      // restrictToTrendExpansion=true.
      RegisterRule(STRAT_TIME_SERIES_MOMENTUM, STRAT_DONCHIAN_BREAKOUT,
                   InpInteraction_MomentumDonchian_RestrictToExpansion, true,
                   0.0, 1.0, true,
                   "MOMENTUM_DONCHIAN_REGIME_RESTRICTED");

      m_initialized = true;
     }

   // `present[STRAT_COUNT]` = which strategies contributed to this
   // (same-direction) setup. Returns the total score modifier; sets
   // outBlocked=true if any enabled blocking rule fires; fills
   // outReason with a semicolon-joined trace of every rule that fired
   // (for the [INTERACTION] log).
   double            Evaluate(const bool &present[], const MetaRegimeState &meta, bool &outBlocked, string &outReason)
     {
      outBlocked = false;
      outReason = "";
      double totalModifier = 0.0;

      if(!InpEnableInteractionMatrix)
        {
         outReason = "interaction matrix disabled";
         return 0.0;
        }

      for(int i = 0; i < ArraySize(m_rules); i++)
        {
         StrategyPairRule rule = m_rules[i];
         if(!rule.enabled)
            continue;
         if(!present[rule.a] || !present[rule.b])
            continue;

         bool trendExpansionRegime = (meta.regime == META_TREND_EXPANSION_BULL || meta.regime == META_TREND_EXPANSION_BEAR ||
                                       meta.regime == META_BREAKOUT_TRANSITION);

         if(rule.blocks)
           {
            bool applies = rule.restrictToTrendExpansion ? !trendExpansionRegime : true;
            if(applies)
              {
               outBlocked = true;
               outReason += (outReason == "" ? "" : "; ") + rule.reason;
               continue;
              }
           }

         totalModifier += rule.scoreModifier;
         outReason += (outReason == "" ? "" : "; ") + rule.reason + StringFormat("(%.1f)", rule.scoreModifier);
        }

      return totalModifier;
     }

private:
   void              RegisterRule(StrategyType a, StrategyType b, bool enabled, bool blocks,
                                   double scoreModifier, double riskMultiplier,
                                   bool restrictToTrendExpansion, string reason)
     {
      int n = ArraySize(m_rules);
      ArrayResize(m_rules, n + 1);
      m_rules[n].a = a;
      m_rules[n].b = b;
      m_rules[n].enabled = enabled;
      m_rules[n].blocks = blocks;
      m_rules[n].scoreModifier = scoreModifier;
      m_rules[n].riskMultiplier = riskMultiplier;
      m_rules[n].restrictToTrendExpansion = restrictToTrendExpansion;
      m_rules[n].reason = reason;
     }
  };

#endif // QXE_STRATEGYINTERACTIONMATRIX_MQH
