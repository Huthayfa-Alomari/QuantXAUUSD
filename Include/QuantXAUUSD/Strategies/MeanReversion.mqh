//+------------------------------------------------------------------+
//| MeanReversion.mqh                                                |
//| QUANT_XAUUSD_ENGINE - Mean Reversion (spec section 18)           |
//| Only active when Regime == RANGE. Z-score extreme + reversal      |
//| confirmation (candle closes back toward the mean).                |
//+------------------------------------------------------------------+
#ifndef QXE_MEANREVERSION_MQH
#define QXE_MEANREVERSION_MQH

#include "IStrategy.mqh"
#include "../Core/Config.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Utilities.mqh"

class CMeanReversion : public IStrategy
  {
public:
   StrategyType      Type(void) override { return STRAT_MEAN_REVERSION; }
   string            Name(void) override { return "MeanReversion"; }

   bool              Evaluate(CMarketData *md, const MarketState &state, Signal &outSignal) override
     {
      outSignal.direction = SIGNAL_NONE;
      if(!EnableMeanReversion)
         return false;

      // Hard regime gate - never trades in a strong trend (spec: "do not
      // use Mean Reversion in Strong Trend").
      if(state.regime != REGIME_RANGE)
         return false;

      CTimeframeData *h1 = md.H1();

      // FIX (repair pass - Z-score forward contamination): zCurrent and
      // zPrevious must each be computed from their OWN window ending at
      // their own bar - never share one mean/stddev. Window A ends at
      // t (includes bar 1); Window B ends at t-1 (excludes bar 1
      // entirely, uses bars [2 .. lookback+1]).
      double seriesCurrent[];
      int nCur = h1.CopyCloseSeries(seriesCurrent, InpZScoreLookback);
      if(nCur < InpZScoreLookback)
         return false;
      double meanCur = QXE_Mean(seriesCurrent, nCur);
      double sdCur = QXE_StdDev(seriesCurrent, nCur, meanCur);
      if(sdCur <= QXE_EPS)
         return false;

      double seriesPrev[];
      ArrayResize(seriesPrev, InpZScoreLookback);
      for(int i = 0; i < InpZScoreLookback; i++)
         seriesPrev[i] = h1.Close(i + 2); // window ending at t-1, excludes bar 1 entirely
      double meanPrev = QXE_Mean(seriesPrev, InpZScoreLookback);
      double sdPrev = QXE_StdDev(seriesPrev, InpZScoreLookback, meanPrev);
      if(sdPrev <= QXE_EPS)
         return false;

      double close1 = h1.Close(1);
      double close2 = h1.Close(2);
      double z = (close1 - meanCur) / sdCur;
      double zPrev = (close2 - meanPrev) / sdPrev;

      SignalDirection dir = SIGNAL_NONE;

      // BUY candidate: was extreme oversold, now turning back up.
      if(zPrev <= -InpZScoreEntry && z > zPrev && close1 > h1.Open(1))
         dir = SIGNAL_BUY;
      // SELL candidate: was extreme overbought, now turning back down.
      else if(zPrev >= InpZScoreEntry && z < zPrev && close1 < h1.Open(1))
         dir = SIGNAL_SELL;

      if(dir == SIGNAL_NONE)
         return false;

      double score = QXE_Clamp(50.0 + (MathAbs(zPrev) - InpZScoreEntry) * 15.0, 0.0, 100.0);

      double atr = h1.ATR(1);
      double entry = close1;
      double stop = (dir == SIGNAL_BUY) ? entry - atr * InpATRStopMultiplier
                                         : entry + atr * InpATRStopMultiplier;
      // Mean reversion target = the mean itself (capped by normal R multiple).
      double rTarget = (dir == SIGNAL_BUY) ? entry + MathAbs(entry - stop) * InpTP2R
                                            : entry - MathAbs(entry - stop) * InpTP2R;
      double target = (dir == SIGNAL_BUY) ? MathMin(meanCur, rTarget) : MathMax(meanCur, rTarget);

      outSignal.strategy = STRAT_MEAN_REVERSION;
      outSignal.direction = dir;
      outSignal.score = score;
      outSignal.confidence = score / 100.0;
      outSignal.entry = entry;
      outSignal.stop = stop;
      outSignal.target = target;
      outSignal.timestamp = h1.Time(1);
      outSignal.regime = state.regime;
      outSignal.reason = StringFormat("Z-score reversal from %.2f toward mean", zPrev);
      return true;
     }
  };

#endif // QXE_MEANREVERSION_MQH
