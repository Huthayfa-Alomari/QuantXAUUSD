//+------------------------------------------------------------------+
//| OpeningRangeBreakout.mqh                                         |
//| QUANT_XAUUSD_ENGINE - Opening Range Breakout (spec section 19)   |
//| Supports 15/30/60 min opening ranges, configurable session start.|
//|                                                                   |
//| REPAIR PASS changes:                                             |
//| 1. Cadence() = PERIOD_M5, so this strategy is now actually        |
//|    evaluated on every M5 close (previously the whole EA only      |
//|    called Evaluate() once per H1 bar, so ORB only ever saw ONE    |
//|    of the six M5 bars inside each H1 - it silently missed most   |
//|    of the opening range and most breakout bars).                  |
//| 2. The range is no longer accumulated tick-by-tick as bars stream |
//|    past. Once the session window has fully closed, the range is   |
//|    RECONSTRUCTED DETERMINISTICALLY by scanning the cached M5       |
//|    history between session-start and session-start+minutes - so   |
//|    the result does not depend on having "seen" every bar live,    |
//|    which is the robust behavior the repair spec asked for.        |
//+------------------------------------------------------------------+
#ifndef QXE_OPENINGRANGEBREAKOUT_MQH
#define QXE_OPENINGRANGEBREAKOUT_MQH

#include "IStrategy.mqh"
#include "../Core/Config.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Utilities.mqh"

class COpeningRangeBreakout : public IStrategy
  {
private:
   datetime          m_currentDayAnchor;
   double            m_orHigh, m_orLow;
   bool              m_orComplete;
   bool              m_brokenToday;

public:
                     COpeningRangeBreakout(void)
     {
      m_currentDayAnchor = 0;
      m_orHigh = 0.0; m_orLow = 0.0;
      m_orComplete = false;
      m_brokenToday = false;
     }

   StrategyType      Type(void) override { return STRAT_OPENING_RANGE_BREAKOUT; }
   string            Name(void) override { return "OpeningRangeBreakout"; }
   ENUM_TIMEFRAMES   Cadence(void) override { return PERIOD_M5; }

   bool              Evaluate(CMarketData *md, const MarketState &state, Signal &outSignal) override
     {
      outSignal.direction = SIGNAL_NONE;
      if(!EnableORB)
         return false;

      CTimeframeData *m5 = md.M5();
      datetime barTime = m5.Time(1);
      MqlDateTime dt;
      TimeToStruct(barTime, dt);

      MqlDateTime dayStruct = dt;
      dayStruct.hour = 0; dayStruct.min = 0; dayStruct.sec = 0;
      datetime dayAnchor = StructToTime(dayStruct);

      MqlDateTime orStart = dt;
      orStart.hour = InpORBSessionStartHour;
      orStart.min = InpORBSessionStartMin;
      orStart.sec = 0;
      datetime orStartTime = StructToTime(orStart);
      datetime orEndTime = orStartTime + InpORBMinutes * 60;

      if(dayAnchor != m_currentDayAnchor)
        {
         m_currentDayAnchor = dayAnchor;
         m_orHigh = -DBL_MAX;
         m_orLow = DBL_MAX;
         m_orComplete = false;
         m_brokenToday = false;
        }

      if(barTime < orStartTime)
         return false; // before today's session

      if(barTime < orEndTime)
         return false; // still inside the opening range - no signal yet, range built on completion below

      if(!m_orComplete)
        {
         // Deterministically reconstruct the range from cached M5 history
         // rather than relying on incremental accumulation - scan every
         // closed M5 bar whose timestamp falls in [orStartTime, orEndTime).
         if(!RebuildRangeFromHistory(m5, orStartTime, orEndTime))
            return false; // insufficient cached history for this window yet
         m_orComplete = true;
        }

      if(m_brokenToday)
         return false;

      double close1 = m5.Close(1);
      SignalDirection dir = SIGNAL_NONE;
      if(close1 > m_orHigh)
         dir = SIGNAL_BUY;
      else if(close1 < m_orLow)
         dir = SIGNAL_SELL;

      if(dir == SIGNAL_NONE)
         return false;

      // Volatility filter - avoid ORB breakouts on abnormally quiet ranges.
      double atr = m5.ATR(1);
      double rangeWidth = m_orHigh - m_orLow;
      if(EnableATRFilter && atr > QXE_EPS && rangeWidth < atr * 0.3)
         return false;

      m_brokenToday = true;

      double score = QXE_Clamp(55.0 + (rangeWidth / MathMax(atr, QXE_EPS)) * 5.0, 0.0, 100.0);

      double entry = close1;
      double stop = (dir == SIGNAL_BUY) ? m_orLow : m_orHigh;
      double risk = MathAbs(entry - stop);
      double target = (dir == SIGNAL_BUY) ? entry + risk * InpTP2R : entry - risk * InpTP2R;

      outSignal.strategy = STRAT_OPENING_RANGE_BREAKOUT;
      outSignal.direction = dir;
      outSignal.score = score;
      outSignal.confidence = score / 100.0;
      outSignal.entry = entry;
      outSignal.stop = stop;
      outSignal.target = target;
      outSignal.timestamp = barTime;
      outSignal.regime = state.regime;
      outSignal.reason = StringFormat("ORB(%dmin) break, range=%.2f", InpORBMinutes, rangeWidth);
      return true;
     }

private:
   // Scans cached M5 bars for those whose open time falls within
   // [orStartTime, orEndTime). Returns false if the cached history does
   // not yet reach back that far (caller should retry next call).
   bool              RebuildRangeFromHistory(CTimeframeData *m5, datetime orStartTime, datetime orEndTime)
     {
      double hi = -DBL_MAX, lo = DBL_MAX;
      int found = 0;
      int maxScan = (InpORBMinutes / 5) + 10; // small safety margin for irregular bar spacing
      int bars = m5.Bars();

      for(int shift = 1; shift < MathMin(maxScan + 5, bars); shift++)
        {
         datetime t = m5.Time(shift);
         if(t == 0)
            break;
         if(t < orStartTime)
            break; // scanned past the start of the window - stop
         if(t >= orStartTime && t < orEndTime)
           {
            hi = MathMax(hi, m5.High(shift));
            lo = MathMin(lo, m5.Low(shift));
            found++;
           }
        }

      if(found == 0)
         return false;

      m_orHigh = hi;
      m_orLow = lo;
      return true;
     }
  };

#endif // QXE_OPENINGRANGEBREAKOUT_MQH
