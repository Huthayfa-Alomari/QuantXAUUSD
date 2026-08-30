//+------------------------------------------------------------------+
//| Metrics.mqh                                                      |
//| QUANT_XAUUSD_ENGINE - Performance metrics (spec section 35)      |
//| Pure computation over a TradeResult history - no side effects.   |
//+------------------------------------------------------------------+
#ifndef QXE_METRICS_MQH
#define QXE_METRICS_MQH

#include "../Core/Types.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Utilities.mqh"

struct PerformanceMetrics
  {
   int               tradeCount;
   double            netProfit;
   double            grossProfit;
   double            grossLoss;
   double            profitFactor;
   double            expectancyR;
   double            avgR;
   double            winRate;
   double            avgWin;
   double            avgLoss;
   double            sharpe;
   double            sortino;
   double            maxDrawdown;
   double            recoveryFactor;
   int               maxConsecutiveWins;
   int               maxConsecutiveLosses;
  };

class CMetrics
  {
public:
   PerformanceMetrics Compute(const TradeResult &trades[], int count) const
     {
      PerformanceMetrics m;
      ZeroMetrics(m);
      if(count <= 0)
         return m;

      m.tradeCount = count;
      int wins = 0, losses = 0;
      double sumR = 0.0;
      double rValues[];
      ArrayResize(rValues, count);

      double equityCurve[];
      ArrayResize(equityCurve, count + 1);
      equityCurve[0] = 0.0;

      int consecWin = 0, consecLoss = 0;

      for(int i = 0; i < count; i++)
        {
         double p = trades[i].profit;
         m.netProfit += p;
         if(p > 0.0) { m.grossProfit += p; wins++; consecWin++; consecLoss = 0; }
         else if(p < 0.0) { m.grossLoss += MathAbs(p); losses++; consecLoss++; consecWin = 0; }

         m.maxConsecutiveWins = MathMax(m.maxConsecutiveWins, consecWin);
         m.maxConsecutiveLosses = MathMax(m.maxConsecutiveLosses, consecLoss);

         double r = trades[i].rMultiple;
         rValues[i] = r;
         sumR += r;

         equityCurve[i + 1] = equityCurve[i] + p;
        }

      m.winRate = (count > 0) ? (double)wins / count * 100.0 : 0.0;
      m.avgWin = (wins > 0) ? m.grossProfit / wins : 0.0;
      m.avgLoss = (losses > 0) ? m.grossLoss / losses : 0.0;
      m.profitFactor = (m.grossLoss > QXE_EPS) ? m.grossProfit / m.grossLoss : (m.grossProfit > 0.0 ? DBL_MAX : 0.0);
      m.avgR = sumR / count;
      m.expectancyR = m.avgR; // expectancy expressed in R terms

      double meanR = QXE_Mean(rValues, count);
      double sdR = QXE_StdDev(rValues, count, meanR);
      m.sharpe = (sdR > QXE_EPS) ? (meanR / sdR) * MathSqrt((double)count) : 0.0;

      double downsideSumSq = 0.0;
      int downsideCount = 0;
      for(int i = 0; i < count; i++)
        {
         if(rValues[i] < 0.0)
           {
            downsideSumSq += rValues[i] * rValues[i];
            downsideCount++;
           }
        }
      double downsideDev = (downsideCount > 0) ? MathSqrt(downsideSumSq / downsideCount) : 0.0;
      m.sortino = (downsideDev > QXE_EPS) ? (meanR / downsideDev) * MathSqrt((double)count) : 0.0;

      // Max drawdown from the equity curve (money terms).
      double peak = equityCurve[0];
      double maxDD = 0.0;
      for(int i = 1; i <= count; i++)
        {
         if(equityCurve[i] > peak)
            peak = equityCurve[i];
         double dd = peak - equityCurve[i];
         if(dd > maxDD)
            maxDD = dd;
        }
      m.maxDrawdown = maxDD;
      m.recoveryFactor = (maxDD > QXE_EPS) ? m.netProfit / maxDD : 0.0;

      return m;
     }

private:
   void              ZeroMetrics(PerformanceMetrics &m) const
     {
      m.tradeCount = 0; m.netProfit = 0.0; m.grossProfit = 0.0; m.grossLoss = 0.0;
      m.profitFactor = 0.0; m.expectancyR = 0.0; m.avgR = 0.0; m.winRate = 0.0;
      m.avgWin = 0.0; m.avgLoss = 0.0; m.sharpe = 0.0; m.sortino = 0.0;
      m.maxDrawdown = 0.0; m.recoveryFactor = 0.0;
      m.maxConsecutiveWins = 0; m.maxConsecutiveLosses = 0;
     }
  };

#endif // QXE_METRICS_MQH
