#ifndef QXE_METRICS_MQH
#define QXE_METRICS_MQH

#include "../Core/Types.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Utilities.mqh"

struct PerformanceMetrics
  {
   int tradeCount,wins,losses,breakevens;
   double netProfit,grossProfit,grossLoss,profitFactor,expectancyR,avgR,winRate,winRateExBE,avgWin,avgLoss;
   double sharpe,sortino,maxDrawdown,recoveryFactor;
   int maxConsecutiveWins,maxConsecutiveLosses;
  };

class CMetrics
  {
public:
   PerformanceMetrics Compute(const TradeResult &trades[],int count) const
     {
      PerformanceMetrics m; ZeroMetrics(m); if(count<=0) return m;
      m.tradeCount=count; double sumR=0.0; double rValues[]; ArrayResize(rValues,count);
      double equityCurve[]; ArrayResize(equityCurve,count+1); equityCurve[0]=0.0;
      int consecWin=0,consecLoss=0;
      for(int i=0;i<count;i++)
        {
         double p=trades[i].profit; m.netProfit+=p;
         if(p>QXE_EPS) { m.grossProfit+=p; m.wins++; consecWin++; consecLoss=0; }
         else if(p<-QXE_EPS) { m.grossLoss+=MathAbs(p); m.losses++; consecLoss++; consecWin=0; }
         else { m.breakevens++; consecWin=0; consecLoss=0; }
         m.maxConsecutiveWins=MathMax(m.maxConsecutiveWins,consecWin);
         m.maxConsecutiveLosses=MathMax(m.maxConsecutiveLosses,consecLoss);
         double r=trades[i].rMultiple; rValues[i]=r; sumR+=r; equityCurve[i+1]=equityCurve[i]+p;
        }
      m.winRate=(double)m.wins/count*100.0;
      int decisive=m.wins+m.losses; m.winRateExBE=(decisive>0)?(double)m.wins/decisive*100.0:0.0;
      m.avgWin=(m.wins>0)?m.grossProfit/m.wins:0.0; m.avgLoss=(m.losses>0)?m.grossLoss/m.losses:0.0;
      m.profitFactor=(m.grossLoss>QXE_EPS)?m.grossProfit/m.grossLoss:(m.grossProfit>0.0?DBL_MAX:0.0);
      m.avgR=sumR/count; m.expectancyR=m.avgR;
      double meanR=QXE_Mean(rValues,count),sdR=QXE_StdDev(rValues,count,meanR);
      // Per-trade distribution quality. No sqrt(count) sample-size inflation.
      m.sharpe=(sdR>QXE_EPS)?meanR/sdR:0.0;
      double downsideSumSq=0.0; int downsideCount=0;
      for(int i=0;i<count;i++) if(rValues[i]<0.0){downsideSumSq+=rValues[i]*rValues[i];downsideCount++;}
      double downsideDev=(downsideCount>0)?MathSqrt(downsideSumSq/downsideCount):0.0;
      m.sortino=(downsideDev>QXE_EPS)?meanR/downsideDev:0.0;
      double peak=equityCurve[0],maxDD=0.0;
      for(int i=1;i<=count;i++){if(equityCurve[i]>peak)peak=equityCurve[i];double dd=peak-equityCurve[i];if(dd>maxDD)maxDD=dd;}
      // Realized/closed-trade PnL drawdown, not intratrade account equity DD.
      m.maxDrawdown=maxDD; m.recoveryFactor=(maxDD>QXE_EPS)?m.netProfit/maxDD:0.0;
      return m;
     }
private:
   void ZeroMetrics(PerformanceMetrics &m) const
     {
      m.tradeCount=m.wins=m.losses=m.breakevens=0;
      m.netProfit=m.grossProfit=m.grossLoss=m.profitFactor=m.expectancyR=m.avgR=m.winRate=m.winRateExBE=m.avgWin=m.avgLoss=0.0;
      m.sharpe=m.sortino=m.maxDrawdown=m.recoveryFactor=0.0; m.maxConsecutiveWins=m.maxConsecutiveLosses=0;
     }
  };
#endif
