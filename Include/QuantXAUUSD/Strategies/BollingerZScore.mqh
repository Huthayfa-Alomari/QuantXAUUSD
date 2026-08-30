//+------------------------------------------------------------------+
//| BollingerZScore.mqh                                              |
//| QUANT_XAUUSD_ENGINE - Bollinger Band statistical strategy         |
//|                                                                   |
//| Distinct from MeanReversion.mqh: this strategy fires purely on a  |
//| Bollinger Band close-beyond-band + Z-score confirmation, WITHOUT  |
//| requiring a reversal candle. Kept separate so strategy attribution|
//| (spec section 36) can compare the two hypotheses independently.   |
//+------------------------------------------------------------------+
#ifndef QXE_BOLLINGERZSCORE_MQH
#define QXE_BOLLINGERZSCORE_MQH

#include "IStrategy.mqh"
#include "../Core/Config.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Utilities.mqh"

class CBollingerZScore : public IStrategy
  {
public:
   StrategyType      Type(void) override { return STRAT_BOLLINGER_ZSCORE; }
   string            Name(void) override { return "BollingerZScore"; }

   bool              Evaluate(CMarketData *md, const MarketState &state, Signal &outSignal) override
     {
      outSignal.direction = SIGNAL_NONE;
      if(!EnableMeanReversion) // shares the same ablation toggle family
         return false;
      if(state.regime != REGIME_RANGE)
         return false;

      CTimeframeData *h1 = md.H1();

      double close1 = h1.Close(1);
      double upper = h1.BBUpper(1);
      double lower = h1.BBLower(1);
      double mid = h1.BBMiddle(1);

      double series[];
      int n = h1.CopyCloseSeries(series, InpZScoreLookback);
      if(n < InpZScoreLookback)
         return false;
      double mean = QXE_Mean(series, n);
      double sd = QXE_StdDev(series, n, mean);
      if(sd <= QXE_EPS)
         return false;
      double z = (close1 - mean) / sd;

      SignalDirection dir = SIGNAL_NONE;
      if(close1 < lower && z <= -InpZScoreEntry)
         dir = SIGNAL_BUY;
      else if(close1 > upper && z >= InpZScoreEntry)
         dir = SIGNAL_SELL;

      if(dir == SIGNAL_NONE)
         return false;

      double score = QXE_Clamp(45.0 + MathAbs(z) * 10.0, 0.0, 100.0);
      double atr = h1.ATR(1);
      double entry = close1;
      double stop = (dir == SIGNAL_BUY) ? entry - atr * InpATRStopMultiplier
                                         : entry + atr * InpATRStopMultiplier;
      double target = mid;

      outSignal.strategy = STRAT_BOLLINGER_ZSCORE;
      outSignal.direction = dir;
      outSignal.score = score;
      outSignal.confidence = score / 100.0;
      outSignal.entry = entry;
      outSignal.stop = stop;
      outSignal.target = target;
      outSignal.timestamp = h1.Time(1);
      outSignal.regime = state.regime;
      outSignal.reason = StringFormat("Close beyond Bollinger band, Z=%.2f", z);
      return true;
     }
  };

#endif // QXE_BOLLINGERZSCORE_MQH
