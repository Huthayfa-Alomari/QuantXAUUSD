//+------------------------------------------------------------------+
//| VWAPStrategy.mqh                                                 |
//| QUANT_XAUUSD_ENGINE - VWAP strategy (spec section 20)            |
//| In trend regimes: VWAP as directional confirmation (price on the |
//| correct side, pulling back to it). In range regimes: VWAP as a   |
//| mean-reversion target.                                            |
//+------------------------------------------------------------------+
#ifndef QXE_VWAPSTRATEGY_MQH
#define QXE_VWAPSTRATEGY_MQH

#include "IStrategy.mqh"
#include "../Core/Config.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Utilities.mqh"

class CVWAPStrategy : public IStrategy
  {
public:
   StrategyType      Type(void) override { return STRAT_VWAP; }
   string            Name(void) override { return "VWAP"; }

   bool              Evaluate(CMarketData *md, const MarketState &state, Signal &outSignal) override
     {
      outSignal.direction = SIGNAL_NONE;
      if(!EnableVWAP)
         return false;

      CTimeframeData *m5 = md.M5();
      double vwap = md.VWAP();
      if(vwap <= 0.0)
         return false;

      double close1 = m5.Close(1);
      double atr = m5.ATR(1);
      SignalDirection dir = SIGNAL_NONE;
      double score = 0.0;
      string reason = "";

      if(state.regime == REGIME_TREND_BULL || state.regime == REGIME_TREND_BEAR)
        {
         // Trend confirmation: price pulled back to VWAP and is closing
         // back in the direction of the established trend.
         double distPoints = QXE_PriceToPoints(_Symbol, MathAbs(close1 - vwap));
         bool nearVwap = distPoints < (atr / QXE_SymbolPoint(_Symbol)) * 0.5;

         if(state.regime == REGIME_TREND_BULL && close1 >= vwap && nearVwap)
           {
            dir = SIGNAL_BUY;
            reason = "Price reclaiming VWAP in bull trend";
           }
         else if(state.regime == REGIME_TREND_BEAR && close1 <= vwap && nearVwap)
           {
            dir = SIGNAL_SELL;
            reason = "Price rejecting VWAP in bear trend";
           }
         score = 55.0;
        }
      else if(state.regime == REGIME_RANGE)
        {
         // Mean-reversion target: price extended away from VWAP, expect pull back.
         double distAtr = (atr > QXE_EPS) ? MathAbs(close1 - vwap) / atr : 0.0;
         if(distAtr >= 1.5)
           {
            dir = (close1 > vwap) ? SIGNAL_SELL : SIGNAL_BUY;
            reason = StringFormat("Price extended %.2fATR from VWAP in range", distAtr);
            score = QXE_Clamp(45.0 + distAtr * 10.0, 0.0, 100.0);
           }
        }

      if(dir == SIGNAL_NONE)
         return false;

      double entry = close1;
      double stop = (dir == SIGNAL_BUY) ? entry - atr * InpATRStopMultiplier
                                         : entry + atr * InpATRStopMultiplier;
      double target = vwap;

      outSignal.strategy = STRAT_VWAP;
      outSignal.direction = dir;
      outSignal.score = score;
      outSignal.confidence = score / 100.0;
      outSignal.entry = entry;
      outSignal.stop = stop;
      outSignal.target = target;
      outSignal.timestamp = m5.Time(1);
      outSignal.regime = state.regime;
      outSignal.reason = reason;
      return true;
     }
  };

#endif // QXE_VWAPSTRATEGY_MQH
