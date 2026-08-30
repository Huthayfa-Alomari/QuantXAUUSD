//+------------------------------------------------------------------+
//| TradeStatistics.mqh + StrategyStatistics.mqh (combined)          |
//| QUANT_XAUUSD_ENGINE - In-memory trade history + attribution      |
//| (spec sections 35-36). Combined into one store because strategy  |
//| attribution is simply the same trade history grouped by strategy |
//| - documented consolidation, see README.                          |
//+------------------------------------------------------------------+
#ifndef QXE_TRADESTATISTICS_MQH
#define QXE_TRADESTATISTICS_MQH

#include "Metrics.mqh"
#include "../Core/Types.mqh"
#include "../Core/Constants.mqh"

class CTradeStatistics
  {
private:
   TradeResult       m_trades[];
   CMetrics          m_metrics;

public:
   void              Init(void)
     {
      ArrayResize(m_trades, 0);
     }

   void              Add(const TradeResult &tr)
     {
      int n = ArraySize(m_trades);
      ArrayResize(m_trades, n + 1);
      m_trades[n] = tr;
     }

   int               Count(void) const { return ArraySize(m_trades); }

   PerformanceMetrics Overall(void) const
     {
      return m_metrics.Compute(m_trades, ArraySize(m_trades));
     }

   // Per-strategy attribution (spec section 36).
   StrategyResult    ForStrategy(StrategyType strat) const
     {
      TradeResult filtered[];
      int n = 0;
      int total = ArraySize(m_trades);
      ArrayResize(filtered, total);
      for(int i = 0; i < total; i++)
        {
         if(m_trades[i].strategy == strat)
           {
            filtered[n] = m_trades[i];
            n++;
           }
        }
      ArrayResize(filtered, n);

      PerformanceMetrics pm = m_metrics.Compute(filtered, n);

      StrategyResult sr;
      sr.strategy = strat;
      sr.trades = pm.tradeCount;
      sr.wins = (int)MathRound(pm.winRate / 100.0 * pm.tradeCount);
      sr.losses = pm.tradeCount - sr.wins;
      sr.grossProfit = pm.grossProfit;
      sr.grossLoss = pm.grossLoss;
      sr.netProfit = pm.netProfit;
      sr.profitFactor = pm.profitFactor;
      sr.expectancyR = pm.expectancyR;
      sr.avgR = pm.avgR;
      sr.maxDrawdown = pm.maxDrawdown;
      return sr;
     }

   void              PrintAttributionReport(void) const
     {
      Print("==== STRATEGY ATTRIBUTION REPORT ====");
      for(int s = 0; s < STRAT_COUNT; s++)
        {
         StrategyType st = (StrategyType)s;
         StrategyResult r = ForStrategy(st);
         if(r.trades == 0)
            continue;
         PrintFormat("%s: trades=%d PF=%.2f Expectancy(R)=%.2f NetProfit=%.2f MaxDD=%.2f",
                      QXE_StrategyToString(st), r.trades, r.profitFactor, r.expectancyR,
                      r.netProfit, r.maxDrawdown);
        }
      Print("======================================");
     }

   // ---- Architecture v2: Meta-Regime Attribution (spec section 16) ----
   void              PrintRegimeReport(void) const
     {
      Print("==== META REGIME REPORT ====");
      for(int r = 0; r < META_REGIME_COUNT; r++)
        {
         ENUM_META_REGIME regime = (ENUM_META_REGIME)r;
         TradeResult filtered[];
         int n = FilterByMetaRegime(regime, filtered);
         if(n == 0)
            continue;
         PerformanceMetrics pm = m_metrics.Compute(filtered, n);
         PrintFormat("%s: trades=%d PF=%.2f ExpectancyR=%.2f Net=%.2f WinRate=%.1f%%",
                      EnumToString(regime), pm.tradeCount, pm.profitFactor, pm.expectancyR,
                      pm.netProfit, pm.winRate);
        }
      Print("=============================");
     }

   // ---- Architecture v2: Strategy x Regime Report (spec section 16) ----
   void              PrintStrategyByRegimeReport(void) const
     {
      Print("==== STRATEGY x REGIME REPORT ====");
      for(int s = 0; s < STRAT_COUNT; s++)
        {
         StrategyType strat = (StrategyType)s;
         for(int r = 0; r < META_REGIME_COUNT; r++)
           {
            ENUM_META_REGIME regime = (ENUM_META_REGIME)r;
            TradeResult filtered[];
            int n = FilterByStrategyAndRegime(strat, regime, filtered);
            if(n == 0)
               continue;
            PerformanceMetrics pm = m_metrics.Compute(filtered, n);
            PrintFormat("%s x %s: trades=%d PF=%.2f ExpectancyR=%.2f Net=%.2f",
                         QXE_StrategyToString(strat), EnumToString(regime),
                         pm.tradeCount, pm.profitFactor, pm.expectancyR, pm.netProfit);
           }
        }
      Print("===================================");
     }

   // ---- Architecture v2: Contributor/Interaction Attribution (spec 15B) ----
   // Groups by the exact `contributingStrategies` string (e.g.
   // "TimeSeriesMomentum+MarketStructure") - this naturally separates
   // "TimeSeriesMomentum standalone" from "TimeSeriesMomentum+VWAP" etc,
   // without needing a combinatorial explosion of hardcoded pair checks.
   void              PrintInteractionAttributionReport(void) const
     {
      Print("==== CONTRIBUTOR / INTERACTION ATTRIBUTION REPORT ====");
      string seenKeys[];
      ArrayResize(seenKeys, 0);

      int total = ArraySize(m_trades);
      for(int i = 0; i < total; i++)
        {
         string key = m_trades[i].contributingStrategies;
         if(key == "")
            continue;
         if(AlreadySeen(seenKeys, key))
            continue;

         int n2 = ArraySize(seenKeys);
         ArrayResize(seenKeys, n2 + 1);
         seenKeys[n2] = key;

         TradeResult filtered[];
         int n = FilterByContributorKey(key, filtered);
         PerformanceMetrics pm = m_metrics.Compute(filtered, n);
         double avgMfeR = 0.0, avgMaeR = 0.0;
         for(int j = 0; j < n; j++) { avgMfeR += filtered[j].mfeR; avgMaeR += filtered[j].maeR; }
         if(n > 0) { avgMfeR /= n; avgMaeR /= n; }

         PrintFormat("%s: trades=%d WinRate=%.1f%% PF=%.2f Net=%.2f ExpectancyR=%.2f AvgMFE_R=%.2f AvgMAE_R=%.2f MaxDD=%.2f",
                      key, pm.tradeCount, pm.winRate, pm.profitFactor, pm.netProfit,
                      pm.expectancyR, avgMfeR, avgMaeR, pm.maxDrawdown);
        }
      Print("=======================================================");
     }

private:
   int               FilterByMetaRegime(ENUM_META_REGIME regime, TradeResult &out[]) const
     {
      int total = ArraySize(m_trades);
      ArrayResize(out, total);
      int n = 0;
      for(int i = 0; i < total; i++)
         if(m_trades[i].entryState.meta.regime == regime)
            out[n++] = m_trades[i];
      ArrayResize(out, n);
      return n;
     }

   int               FilterByStrategyAndRegime(StrategyType strat, ENUM_META_REGIME regime, TradeResult &out[]) const
     {
      int total = ArraySize(m_trades);
      ArrayResize(out, total);
      int n = 0;
      for(int i = 0; i < total; i++)
         if(m_trades[i].strategy == strat && m_trades[i].entryState.meta.regime == regime)
            out[n++] = m_trades[i];
      ArrayResize(out, n);
      return n;
     }

   int               FilterByContributorKey(string key, TradeResult &out[]) const
     {
      int total = ArraySize(m_trades);
      ArrayResize(out, total);
      int n = 0;
      for(int i = 0; i < total; i++)
         if(m_trades[i].contributingStrategies == key)
            out[n++] = m_trades[i];
      ArrayResize(out, n);
      return n;
     }

   bool              AlreadySeen(const string &keys[], string key) const
     {
      for(int i = 0; i < ArraySize(keys); i++)
         if(keys[i] == key)
            return true;
      return false;
     }
  };

#endif // QXE_TRADESTATISTICS_MQH
