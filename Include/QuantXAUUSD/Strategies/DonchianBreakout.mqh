//+------------------------------------------------------------------+
//| DonchianBreakout.mqh                                             |
//| QUANT_XAUUSD_ENGINE - Donchian channel breakout (spec section 11)|
//+------------------------------------------------------------------+
#ifndef QXE_DONCHIANBREAKOUT_MQH
#define QXE_DONCHIANBREAKOUT_MQH

#include "IStrategy.mqh"
#include "../Core/Config.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Utilities.mqh"

class CDonchianBreakout : public IStrategy
  {
public:
   StrategyType      Type(void) override { return STRAT_DONCHIAN_BREAKOUT; }
   string            Name(void) override { return "DonchianBreakout"; }

   bool              Evaluate(CMarketData *md, const MarketState &state, Signal &outSignal) override
     {
      outSignal.direction = SIGNAL_NONE;
      if(!EnableDonchian)
         return false;

      CTimeframeData *h1 = md.H1();

      // Channel computed from bars [2 .. N+1], i.e. excluding the last
      // closed bar itself, so the breakout bar cannot be inside its own
      // channel (spec: "do not include the current candle in the channel").
      double highestHigh = h1.HighestHigh(2, InpDonchianEntry);
      double lowestLow   = h1.LowestLow(2, InpDonchianEntry);
      double close1 = h1.Close(1);

      SignalDirection dir = SIGNAL_NONE;
      if(close1 > highestHigh)
         dir = SIGNAL_BUY;
      else if(close1 < lowestLow)
         dir = SIGNAL_SELL;

      if(dir == SIGNAL_NONE)
         return false;

      double atr = h1.ATR(1);
      double channelWidth = highestHigh - lowestLow;
      double breakoutStrength = (channelWidth > QXE_EPS) ?
         MathAbs(close1 - (dir == SIGNAL_BUY ? highestHigh : lowestLow)) / atr : 0.0;

      double score = QXE_Clamp(55.0 + breakoutStrength * 15.0, 0.0, 100.0);

      double entry = close1;
      double exitChannelStop = (dir == SIGNAL_BUY) ? h1.LowestLow(1, InpDonchianExit)
                                                     : h1.HighestHigh(1, InpDonchianExit);
      double atrStop = (dir == SIGNAL_BUY) ? entry - atr * InpATRStopMultiplier
                                            : entry + atr * InpATRStopMultiplier;
      // Use the tighter of the two protective stops (structural exit channel
      // vs ATR) as the initial stop, but never inside the entry.
      double stop = (dir == SIGNAL_BUY) ? MathMax(exitChannelStop, atrStop)
                                         : MathMin(exitChannelStop, atrStop);

      double risk = MathAbs(entry - stop);
      double target = (dir == SIGNAL_BUY) ? entry + risk * InpTP2R : entry - risk * InpTP2R;

      outSignal.strategy = STRAT_DONCHIAN_BREAKOUT;
      outSignal.direction = dir;
      outSignal.score = score;
      outSignal.confidence = score / 100.0;
      outSignal.entry = entry;
      outSignal.stop = stop;
      outSignal.target = target;
      outSignal.timestamp = h1.Time(1);
      outSignal.regime = state.regime;
      outSignal.reason = StringFormat("Donchian(%d) breakout, strength=%.2fATR", InpDonchianEntry, breakoutStrength);
      return true;
     }
  };

#endif // QXE_DONCHIANBREAKOUT_MQH
