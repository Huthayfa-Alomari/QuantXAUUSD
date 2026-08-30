//+------------------------------------------------------------------+
//| MomentumPullback.mqh                                             |
//| QUANT_XAUUSD_ENGINE - Momentum Pullback (spec section 13)        |
//| HTF Trend -> Impulse -> Pullback -> Confirmation -> Entry.        |
//| Uses EMA20/EMA50 + swing structure; Fibonacci is intentionally    |
//| NOT required (spec: "do not make Fibonacci mandatory").          |
//+------------------------------------------------------------------+
#ifndef QXE_MOMENTUMPULLBACK_MQH
#define QXE_MOMENTUMPULLBACK_MQH

#include "IStrategy.mqh"
#include "../Structure/SwingDetector.mqh"
#include "../Core/Config.mqh"
#include "../Core/Utilities.mqh"

class CMomentumPullback : public IStrategy
  {
private:
   CSwingDetector    m_swings;
   bool              m_initialized;

public:
                     CMomentumPullback(void) : m_initialized(false) {}

   StrategyType      Type(void) override { return STRAT_MOMENTUM_PULLBACK; }
   string            Name(void) override { return "MomentumPullback"; }

   bool              Evaluate(CMarketData *md, const MarketState &state, Signal &outSignal) override
     {
      outSignal.direction = SIGNAL_NONE;
      if(!EnablePullback)
         return false;

      if(!m_initialized)
        {
         m_swings.Init(InpPullbackSwingLeft, InpPullbackSwingRight);
         m_initialized = true;
        }

      CTimeframeData *h1 = md.H1();
      CTimeframeData *h4 = md.H4();

      double h4Slope = h4.EMA200SlopePoints(20);
      bool htfBull = h4.Close(1) > h4.EMA200(1) && h4Slope > InpEMASlopeMinPoints;
      bool htfBear = h4.Close(1) < h4.EMA200(1) && h4Slope < -InpEMASlopeMinPoints;

      if(!htfBull && !htfBear)
         return false;

      double ema20 = h1.EMA20(1);
      double ema50 = h1.EMA50(1);
      double close1 = h1.Close(1);
      double low1 = h1.Low(1);
      double high1 = h1.High(1);

      SignalDirection dir = SIGNAL_NONE;

      if(htfBull)
        {
         // Impulse already happened (price above EMA50), pullback = price
         // touches into the EMA20/EMA50 zone, confirmation = close back
         // above EMA20 with the bar closing bullish.
         bool touchedZone = (low1 <= ema20 && close1 >= ema50);
         bool confirmed = (close1 > ema20) && (close1 > h1.Open(1));
         if(touchedZone && confirmed)
            dir = SIGNAL_BUY;
        }
      else if(htfBear)
        {
         bool touchedZone = (high1 >= ema20 && close1 <= ema50);
         bool confirmed = (close1 < ema20) && (close1 < h1.Open(1));
         if(touchedZone && confirmed)
            dir = SIGNAL_SELL;
        }

      if(dir == SIGNAL_NONE)
         return false;

      double atr = h1.ATR(1);
      double score = QXE_Clamp(55.0 + MathAbs(h4Slope) / 5.0, 0.0, 100.0);

      double entry = close1;
      // Structural stop beyond the pullback swing (fallback to ATR if no
      // swing found nearby).
      int swingShift = (dir == SIGNAL_BUY) ?
         m_swings.FindLastSwingLow(h1, InpPullbackSwingRight + 1, 20) :
         m_swings.FindLastSwingHigh(h1, InpPullbackSwingRight + 1, 20);

      double stop;
      if(swingShift >= 0)
        {
         double swingPrice = (dir == SIGNAL_BUY) ? h1.Low(swingShift) : h1.High(swingShift);
         double buffer = atr * 0.25;
         stop = (dir == SIGNAL_BUY) ? swingPrice - buffer : swingPrice + buffer;
        }
      else
        {
         stop = (dir == SIGNAL_BUY) ? entry - atr * InpATRStopMultiplier
                                     : entry + atr * InpATRStopMultiplier;
        }

      double risk = MathAbs(entry - stop);
      double target = (dir == SIGNAL_BUY) ? entry + risk * InpTP2R : entry - risk * InpTP2R;

      outSignal.strategy = STRAT_MOMENTUM_PULLBACK;
      outSignal.direction = dir;
      outSignal.score = score;
      outSignal.confidence = score / 100.0;
      outSignal.entry = entry;
      outSignal.stop = stop;
      outSignal.target = target;
      outSignal.timestamp = h1.Time(1);
      outSignal.regime = state.regime;
      outSignal.reason = "HTF trend pullback to EMA20/50 zone, confirmed";
      return true;
     }
  };

#endif // QXE_MOMENTUMPULLBACK_MQH
