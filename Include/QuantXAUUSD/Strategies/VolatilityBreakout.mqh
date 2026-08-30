//+------------------------------------------------------------------+
//| VolatilityBreakout.mqh                                           |
//| QUANT_XAUUSD_ENGINE - Volatility Breakout (spec section 12)      |
//| Compression -> Expansion -> Breakout, using ATR ratio + range     |
//| break, with optional HTF bias.                                   |
//+------------------------------------------------------------------+
#ifndef QXE_VOLATILITYBREAKOUT_MQH
#define QXE_VOLATILITYBREAKOUT_MQH

#include "IStrategy.mqh"
#include "../Core/Config.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Utilities.mqh"

class CVolatilityBreakout : public IStrategy
  {
public:
   StrategyType      Type(void) override { return STRAT_VOLATILITY_BREAKOUT; }
   string            Name(void) override { return "VolatilityBreakout"; }

   bool              Evaluate(CMarketData *md, const MarketState &state, Signal &outSignal) override
     {
      outSignal.direction = SIGNAL_NONE;
      if(!EnableBreakout)
         return false;

      CTimeframeData *h1 = md.H1();
      CTimeframeData *h4 = md.H4();

      double atrNow = h1.ATR(1);
      double atrSeries[];
      int n = h1.CopyATRSeries(atrSeries, InpATRPercentileLookback);
      if(n < 10)
         return false;

      double atrAvg = QXE_Mean(atrSeries, n);
      if(atrAvg <= QXE_EPS)
         return false;

      double atrRatio = atrNow / atrAvg;
      if(atrRatio < InpVolBreakoutATRRatio)
         return false; // still compressed, no expansion yet

      double rangeHigh = h1.HighestHigh(2, InpVolBreakoutRangeBars);
      double rangeLow  = h1.LowestLow(2, InpVolBreakoutRangeBars);
      double close1 = h1.Close(1);

      SignalDirection dir = SIGNAL_NONE;
      if(close1 > rangeHigh)
         dir = SIGNAL_BUY;
      else if(close1 < rangeLow)
         dir = SIGNAL_SELL;

      if(dir == SIGNAL_NONE)
         return false;

      // Optional HTF bias filter - do not fight the H4 trend direction
      // when it is clearly established.
      double h4Slope = h4.EMA200SlopePoints(20);
      if(dir == SIGNAL_BUY && h4Slope < -InpEMASlopeMinPoints * 2.0)
         return false;
      if(dir == SIGNAL_SELL && h4Slope > InpEMASlopeMinPoints * 2.0)
         return false;

      double score = QXE_Clamp(50.0 + (atrRatio - InpVolBreakoutATRRatio) * 40.0, 0.0, 100.0);

      double entry = close1;
      double stop = (dir == SIGNAL_BUY) ? entry - atrNow * InpATRStopMultiplier
                                         : entry + atrNow * InpATRStopMultiplier;
      double risk = MathAbs(entry - stop);
      double target = (dir == SIGNAL_BUY) ? entry + risk * InpTP2R : entry - risk * InpTP2R;

      outSignal.strategy = STRAT_VOLATILITY_BREAKOUT;
      outSignal.direction = dir;
      outSignal.score = score;
      outSignal.confidence = score / 100.0;
      outSignal.entry = entry;
      outSignal.stop = stop;
      outSignal.target = target;
      outSignal.timestamp = h1.Time(1);
      outSignal.regime = state.regime;
      outSignal.reason = StringFormat("Vol expansion ATR ratio=%.2f, range break", atrRatio);
      return true;
     }
  };

#endif // QXE_VOLATILITYBREAKOUT_MQH
