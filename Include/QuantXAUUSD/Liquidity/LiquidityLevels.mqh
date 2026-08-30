//+------------------------------------------------------------------+
//| LiquidityLevels.mqh                                              |
//| QUANT_XAUUSD_ENGINE - Liquidity level registry                   |
//|                                                                   |
//| REPAIR PASS changes:                                             |
//| 1. Levels now have a persistent identity key (type + formation    |
//|    date). Update() ADDS new levels and never clears the array,    |
//|    so a level's `swept` flag survives across calls - a swept     |
//|    level can never silently "reappear" unswept.                  |
//| 2. PWH/PWL now read the broker's actual PERIOD_W1 shift-1 bar,    |
//|    not a rolling 5-day D1 window (which is not the same thing as |
//|    "the previous calendar week").                                |
//| 3. Equal highs/lows are now built only from CONFIRMED SWING       |
//|    points (via CSwingDetector), not arbitrary adjacent-candle     |
//|    high/low pairs, with a minimum bar separation requirement.     |
//+------------------------------------------------------------------+
#ifndef QXE_LIQUIDITYLEVELS_MQH
#define QXE_LIQUIDITYLEVELS_MQH

#include "../Data/TimeframeData.mqh"
#include "../Structure/SwingDetector.mqh"
#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Utilities.mqh"

struct LiquidityLevel
  {
   LiquidityLevelType type;
   double            price;
   datetime          formedTime;   // identity key component (together with type)
   bool              swept;
   bool              active;       // false once expired/superseded (kept for audit, not removed)
  };

class CLiquidityLevels
  {
private:
   LiquidityLevel    m_levels[];
   string            m_symbol;
   CSwingDetector    m_swings;
   datetime          m_lastPDHDay;
   datetime          m_lastPWHWeek;

public:
   void              Init(string symbol)
     {
      m_symbol = symbol;
      m_swings.Init(InpSwingLeft, InpSwingRight);
      ArrayResize(m_levels, 0);
      m_lastPDHDay = 0;
      m_lastPWHWeek = 0;
     }

   // Call once per new closed D1 bar and once per new closed H1 bar.
   // ADDS levels that don't already exist; NEVER clears the array, so
   // `swept` state persists (repair spec: "LIQUIDITY STATE BUG").
   void              Update(CTimeframeData *d1, CTimeframeData *h1)
     {
      UpdatePDH_PDL(d1);
      UpdatePWH_PWL();
      UpdateEqualLevels(h1);
     }

   int               Count(void) const { return ArraySize(m_levels); }

   LiquidityLevel    Get(int index) const
     {
      LiquidityLevel empty;
      empty.type = LIQ_PDH; empty.price = 0.0; empty.formedTime = 0;
      empty.swept = false; empty.active = false;
      if(index < 0 || index >= ArraySize(m_levels))
         return empty;
      return m_levels[index];
     }

   void              MarkSwept(int index)
     {
      if(index >= 0 && index < ArraySize(m_levels))
         m_levels[index].swept = true;
     }

private:
   // Finds an existing level with the same type+formedTime identity.
   // Returns its index, or -1 if not present.
   int               FindByIdentity(LiquidityLevelType type, datetime formedTime) const
     {
      for(int i = 0; i < ArraySize(m_levels); i++)
         if(m_levels[i].type == type && m_levels[i].formedTime == formedTime)
            return i;
      return -1;
     }

   void              AddOrUpdate(LiquidityLevelType type, double price, datetime formedTime)
     {
      if(price <= 0.0)
         return;
      int idx = FindByIdentity(type, formedTime);
      if(idx >= 0)
         return; // already registered - preserve its swept state, don't touch it

      int n = ArraySize(m_levels);
      ArrayResize(m_levels, n + 1);
      m_levels[n].type = type;
      m_levels[n].price = price;
      m_levels[n].formedTime = formedTime;
      m_levels[n].swept = false;
      m_levels[n].active = true;
     }

   void              UpdatePDH_PDL(CTimeframeData *d1)
     {
      if(d1.Bars() <= 2)
         return;
      datetime dayKey = d1.Time(1); // identity = the D1 bar that formed this level
      if(dayKey == m_lastPDHDay)
         return;
      m_lastPDHDay = dayKey;
      AddOrUpdate(LIQ_PDH, d1.High(1), dayKey);
      AddOrUpdate(LIQ_PDL, d1.Low(1), dayKey);
     }

   // True previous COMPLETED calendar week high/low, read directly from
   // the broker's W1 series - not a rolling 5-day D1 window.
   void              UpdatePWH_PWL(void)
     {
      datetime weekTime = iTime(m_symbol, PERIOD_W1, 1);
      if(weekTime == 0 || weekTime == m_lastPWHWeek)
         return;

      double wh = iHigh(m_symbol, PERIOD_W1, 1);
      double wl = iLow(m_symbol, PERIOD_W1, 1);
      if(wh <= 0.0 || wl <= 0.0)
         return;

      m_lastPWHWeek = weekTime;
      AddOrUpdate(LIQ_PWH, wh, weekTime);
      AddOrUpdate(LIQ_PWL, wl, weekTime);
     }

   // Equal highs/lows from CONFIRMED swing points only, with a minimum
   // bar separation so two adjacent candles of a single swing don't
   // falsely count as "equal liquidity".
   void              UpdateEqualLevels(CTimeframeData *h1)
     {
      double tolPrice = QXE_PointsToPrice(m_symbol, InpEqualLevelTolPoints);
      int scan = 40;
      int minSeparation = InpSwingLeft + InpSwingRight + 2;

      int swingHighShifts[];
      int swingLowShifts[];
      ArrayResize(swingHighShifts, 0);
      ArrayResize(swingLowShifts, 0);

      int cursor = InpSwingRight + 1;
      while(cursor < scan)
        {
         int hi = m_swings.FindLastSwingHigh(h1, cursor, scan - cursor);
         if(hi < 0)
            break;
         int n = ArraySize(swingHighShifts);
         ArrayResize(swingHighShifts, n + 1);
         swingHighShifts[n] = hi;
         cursor = hi + minSeparation;
        }

      cursor = InpSwingRight + 1;
      while(cursor < scan)
        {
         int lo = m_swings.FindLastSwingLow(h1, cursor, scan - cursor);
         if(lo < 0)
            break;
         int n = ArraySize(swingLowShifts);
         ArrayResize(swingLowShifts, n + 1);
         swingLowShifts[n] = lo;
         cursor = lo + minSeparation;
        }

      for(int i = 0; i < ArraySize(swingHighShifts); i++)
        {
         for(int j = i + 1; j < ArraySize(swingHighShifts); j++)
           {
            if(MathAbs(swingHighShifts[i] - swingHighShifts[j]) < minSeparation)
               continue;
            double hi_i = h1.High(swingHighShifts[i]);
            double hi_j = h1.High(swingHighShifts[j]);
            if(MathAbs(hi_i - hi_j) <= tolPrice)
              {
               datetime key = h1.Time(swingHighShifts[i]);
               AddOrUpdate(LIQ_EQUAL_HIGH, MathMax(hi_i, hi_j), key);
              }
           }
        }

      for(int i = 0; i < ArraySize(swingLowShifts); i++)
        {
         for(int j = i + 1; j < ArraySize(swingLowShifts); j++)
           {
            if(MathAbs(swingLowShifts[i] - swingLowShifts[j]) < minSeparation)
               continue;
            double lo_i = h1.Low(swingLowShifts[i]);
            double lo_j = h1.Low(swingLowShifts[j]);
            if(MathAbs(lo_i - lo_j) <= tolPrice)
              {
               datetime key = h1.Time(swingLowShifts[i]);
               AddOrUpdate(LIQ_EQUAL_LOW, MathMin(lo_i, lo_j), key);
              }
           }
        }
     }
  };

#endif // QXE_LIQUIDITYLEVELS_MQH
