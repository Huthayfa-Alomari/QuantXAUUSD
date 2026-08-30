//+------------------------------------------------------------------+
//| TimeSeriesMomentum.mqh                                           |
//| QUANT_XAUUSD_ENGINE - Time-Series Momentum (spec section 10)     |
//+------------------------------------------------------------------+
#ifndef QXE_TIMESERIESMOMENTUM_MQH
#define QXE_TIMESERIESMOMENTUM_MQH

#include "IStrategy.mqh"
#include "../Core/Config.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Utilities.mqh"

class CTimeSeriesMomentum : public IStrategy
  {
public:
   StrategyType      Type(void) override { return STRAT_TIME_SERIES_MOMENTUM; }
   string            Name(void) override { return "TimeSeriesMomentum"; }

   bool              Evaluate(CMarketData *md, const MarketState &state, Signal &outSignal) override
     {
      outSignal.direction = SIGNAL_NONE;
      if(!EnableMomentum)
         return false;

      CTimeframeData *h4 = md.H4();
      CTimeframeData *h1 = md.H1();
      CTimeframeData *m15 = md.M15();

      double momH4  = AtrNormalizedReturn(h4, InpMomentumLookbackH4);
      double momH1  = AtrNormalizedReturn(h1, InpMomentumLookbackH1);
      double momM15 = AtrNormalizedReturn(m15, InpMomentumLookbackM15);

      int agree = 0;
      int bullVotes = 0, bearVotes = 0;
      if(momH4  > 0) bullVotes++; else if(momH4  < 0) bearVotes++;
      if(momH1  > 0) bullVotes++; else if(momH1  < 0) bearVotes++;
      if(momM15 > 0) bullVotes++; else if(momM15 < 0) bearVotes++;

      SignalDirection dir = SIGNAL_NONE;
      if(bullVotes >= 2 && bearVotes == 0)
         dir = SIGNAL_BUY;
      else if(bearVotes >= 2 && bullVotes == 0)
         dir = SIGNAL_SELL;

      if(dir == SIGNAL_NONE)
         return false;

      double magnitude = MathAbs(momH4) + MathAbs(momH1) + MathAbs(momM15);
      double score = QXE_Clamp(40.0 + magnitude * 8.0 + (bullVotes + bearVotes) * 5.0, 0.0, 100.0);

      double atr = h1.ATR(1);
      double entry = h1.Close(1);
      double stop = (dir == SIGNAL_BUY) ? entry - atr * InpATRStopMultiplier
                                         : entry + atr * InpATRStopMultiplier;
      double risk = MathAbs(entry - stop);
      double target = (dir == SIGNAL_BUY) ? entry + risk * InpTP2R : entry - risk * InpTP2R;

      outSignal.strategy = STRAT_TIME_SERIES_MOMENTUM;
      outSignal.direction = dir;
      outSignal.score = score;
      outSignal.confidence = score / 100.0;
      outSignal.entry = entry;
      outSignal.stop = stop;
      outSignal.target = target;
      outSignal.timestamp = h1.Time(1);
      outSignal.regime = state.regime;
      outSignal.reason = StringFormat("Multi-TF momentum agree (H4=%.2f H1=%.2f M15=%.2f)", momH4, momH1, momM15);
      return true;
     }

private:
   // Return over `lookback` closed bars, normalized by current ATR so
   // it is comparable across timeframes and volatility regimes.
   double            AtrNormalizedReturn(CTimeframeData *tf, int lookback) const
     {
      double now = tf.Close(1);
      double then = tf.Close(1 + lookback);
      double atr = tf.ATR(1);
      if(atr <= QXE_EPS || then <= 0.0)
         return 0.0;
      return (now - then) / atr;
     }
  };

#endif // QXE_TIMESERIESMOMENTUM_MQH
