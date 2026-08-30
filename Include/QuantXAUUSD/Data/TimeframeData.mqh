//+------------------------------------------------------------------+
//| TimeframeData.mqh                                                |
//| QUANT_XAUUSD_ENGINE - Per-timeframe OHLC + indicator cache        |
//|                                                                   |
//| One instance per tracked timeframe. Owns its indicator handles,  |
//| refreshes buffers once per closed bar (caching), and exposes     |
//| defensive accessors that never index out of range.               |
//| Combines the roles of CandleData + IndicatorCache from the spec  |
//| tree into a single cohesive per-timeframe object (documented     |
//| consolidation - see README "Architecture Notes").                |
//+------------------------------------------------------------------+
#ifndef QXE_TIMEFRAMEDATA_MQH
#define QXE_TIMEFRAMEDATA_MQH

#include "../Core/Config.mqh"
#include "../Core/Constants.mqh"
#include "../Core/ErrorHandler.mqh"
#include "../Core/Utilities.mqh"

class CTimeframeData
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   int               m_historyBars;

   // Indicator handles
   int               m_hEMA20, m_hEMA50, m_hEMA200;
   int               m_hATR;
   int               m_hADX;
   int               m_hBB;

   // Cached OHLC (index 0 = most recent CLOSED bar, i.e. shift 1 on the chart)
   double            m_open[], m_high[], m_low[], m_close[];
   long              m_tickVolume[];
   datetime          m_time[];

   // Cached indicator buffers (same indexing convention)
   double            m_ema20[], m_ema50[], m_ema200[];
   double            m_atr[];
   double            m_adxMain[], m_adxPlusDI[], m_adxMinusDI[];
   double            m_bbUpper[], m_bbMiddle[], m_bbLower[];

   datetime          m_lastRefreshBarTime;
   bool              m_ready;

public:
                     CTimeframeData(void)
     {
      m_hEMA20 = m_hEMA50 = m_hEMA200 = INVALID_HANDLE;
      m_hATR = INVALID_HANDLE;
      m_hADX = INVALID_HANDLE;
      m_hBB = INVALID_HANDLE;
      m_lastRefreshBarTime = 0;
      m_ready = false;
     }

                    ~CTimeframeData(void)
     {
      if(m_hEMA20 != INVALID_HANDLE)  IndicatorRelease(m_hEMA20);
      if(m_hEMA50 != INVALID_HANDLE)  IndicatorRelease(m_hEMA50);
      if(m_hEMA200 != INVALID_HANDLE) IndicatorRelease(m_hEMA200);
      if(m_hATR != INVALID_HANDLE)    IndicatorRelease(m_hATR);
      if(m_hADX != INVALID_HANDLE)    IndicatorRelease(m_hADX);
      if(m_hBB != INVALID_HANDLE)     IndicatorRelease(m_hBB);
     }

   bool              Init(string symbol, ENUM_TIMEFRAMES tf, int historyBars)
     {
      m_symbol = symbol;
      m_tf = tf;
      m_historyBars = historyBars;

      m_hEMA20  = iMA(symbol, tf, InpEMA20Period, 0, MODE_EMA, PRICE_CLOSE);
      m_hEMA50  = iMA(symbol, tf, InpEMA50Period, 0, MODE_EMA, PRICE_CLOSE);
      m_hEMA200 = iMA(symbol, tf, InpEMA200Period, 0, MODE_EMA, PRICE_CLOSE);
      m_hATR    = iATR(symbol, tf, InpATRPeriod);
      m_hADX    = iADX(symbol, tf, InpADXPeriod);
      m_hBB     = iBands(symbol, tf, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);

      bool ok = true;
      ok = QXE_ValidHandle(m_hEMA20,  "EMA20 " + EnumToString(tf))  && ok;
      ok = QXE_ValidHandle(m_hEMA50,  "EMA50 " + EnumToString(tf))  && ok;
      ok = QXE_ValidHandle(m_hEMA200, "EMA200 " + EnumToString(tf)) && ok;
      ok = QXE_ValidHandle(m_hATR,    "ATR " + EnumToString(tf))    && ok;
      ok = QXE_ValidHandle(m_hADX,    "ADX " + EnumToString(tf))    && ok;
      ok = QXE_ValidHandle(m_hBB,     "Bands " + EnumToString(tf))  && ok;

      ArraySetAsSeries(m_open, true);
      ArraySetAsSeries(m_high, true);
      ArraySetAsSeries(m_low, true);
      ArraySetAsSeries(m_close, true);
      ArraySetAsSeries(m_tickVolume, true);
      ArraySetAsSeries(m_time, true);
      ArraySetAsSeries(m_ema20, true);
      ArraySetAsSeries(m_ema50, true);
      ArraySetAsSeries(m_ema200, true);
      ArraySetAsSeries(m_atr, true);
      ArraySetAsSeries(m_adxMain, true);
      ArraySetAsSeries(m_adxPlusDI, true);
      ArraySetAsSeries(m_adxMinusDI, true);
      ArraySetAsSeries(m_bbUpper, true);
      ArraySetAsSeries(m_bbMiddle, true);
      ArraySetAsSeries(m_bbLower, true);

      return ok;
     }

   // Refreshes cached buffers. Cheap no-op if the timeframe has not
   // produced a new closed bar since the last refresh (caching, see
   // spec section 6 - avoid recreating/recopying on every tick).
   bool              Refresh(bool forceRefresh = false)
     {
      datetime barTime = iTime(m_symbol, m_tf, 0);
      if(barTime == 0)
        {
         m_ready = false;
         return false;
        }

      if(!forceRefresh && barTime == m_lastRefreshBarTime && m_ready)
         return true; // already cached for this bar

      int need = m_historyBars;

      bool ok = true;
      ok = (CopyOpen(m_symbol, m_tf, 0, need, m_open) > 0) && ok;
      ok = (CopyHigh(m_symbol, m_tf, 0, need, m_high) > 0) && ok;
      ok = (CopyLow(m_symbol, m_tf, 0, need, m_low) > 0) && ok;
      ok = (CopyClose(m_symbol, m_tf, 0, need, m_close) > 0) && ok;
      ok = (CopyTickVolume(m_symbol, m_tf, 0, need, m_tickVolume) > 0) && ok;
      ok = (CopyTime(m_symbol, m_tf, 0, need, m_time) > 0) && ok;

      if(!ok)
        {
         g_Logger.Warn(StringFormat("TimeframeData(%s): CopyRates failed, err=%d", EnumToString(m_tf), GetLastError()));
         m_ready = false;
         return false;
        }

      int gotEMA20  = CopyBuffer(m_hEMA20, 0, 0, need, m_ema20);
      int gotEMA50  = CopyBuffer(m_hEMA50, 0, 0, need, m_ema50);
      int gotEMA200 = CopyBuffer(m_hEMA200, 0, 0, need, m_ema200);
      int gotATR    = CopyBuffer(m_hATR, 0, 0, need, m_atr);
      int gotADXm   = CopyBuffer(m_hADX, 0, 0, need, m_adxMain);
      int gotADXp   = CopyBuffer(m_hADX, 1, 0, need, m_adxPlusDI);
      int gotADXn   = CopyBuffer(m_hADX, 2, 0, need, m_adxMinusDI);
      int gotBBu    = CopyBuffer(m_hBB, 1, 0, need, m_bbUpper);
      int gotBBm    = CopyBuffer(m_hBB, 0, 0, need, m_bbMiddle);
      int gotBBl    = CopyBuffer(m_hBB, 2, 0, need, m_bbLower);

      int minGot = MathMin(gotEMA20, MathMin(gotEMA50, MathMin(gotEMA200,
                   MathMin(gotATR, MathMin(gotADXm, MathMin(gotADXp,
                   MathMin(gotADXn, MathMin(gotBBu, MathMin(gotBBm, gotBBl)))))))));

      if(minGot <= QXE_MIN_BARS_REQUIRED && minGot < need)
        {
         // Not necessarily fatal (e.g. limited broker history) - warn only.
         g_Logger.Debug(StringFormat("TimeframeData(%s): partial indicator data (%d/%d)", EnumToString(m_tf), minGot, need));
        }

      m_ready = (minGot > 1 && ArraySize(m_close) > 1);
      m_lastRefreshBarTime = barTime;
      return m_ready;
     }

   bool              IsReady(void) const { return m_ready; }
   int               Bars(void) const    { return ArraySize(m_close); }

   // Defensive accessors - shift 1 = last CLOSED bar (never shift 0 for signals).
   double            Close(int shift) const { return SafeGet(m_close, shift); }
   double            Open(int shift)  const { return SafeGet(m_open, shift); }
   double            High(int shift)  const { return SafeGet(m_high, shift); }
   double            Low(int shift)   const { return SafeGet(m_low, shift); }
   datetime          Time(int shift)  const
     {
      if(shift < 0 || shift >= ArraySize(m_time))
         return 0;
      return m_time[shift];
     }
   long              TickVolume(int shift) const
     {
      if(shift < 0 || shift >= ArraySize(m_tickVolume))
         return 0;
      return m_tickVolume[shift];
     }

   double            EMA20(int shift)  const { return SafeGet(m_ema20, shift); }
   double            EMA50(int shift)  const { return SafeGet(m_ema50, shift); }
   double            EMA200(int shift) const { return SafeGet(m_ema200, shift); }
   double            ATR(int shift)    const { return SafeGet(m_atr, shift); }
   double            ADX(int shift)    const { return SafeGet(m_adxMain, shift); }
   double            ADXPlus(int shift) const { return SafeGet(m_adxPlusDI, shift); }
   double            ADXMinus(int shift) const { return SafeGet(m_adxMinusDI, shift); }
   double            BBUpper(int shift) const { return SafeGet(m_bbUpper, shift); }
   double            BBMiddle(int shift) const { return SafeGet(m_bbMiddle, shift); }
   double            BBLower(int shift) const { return SafeGet(m_bbLower, shift); }

   // Returns EMA200 slope over `lookback` bars, expressed in points/bar.
   double            EMA200SlopePoints(int lookback) const
     {
      return EMASlopePoints(EMA200(1), EMA200(1 + lookback), lookback);
     }

   // Generalized versions (Architecture v2 Market State Engine needs
   // EMA20/EMA50 slopes too - reuses the same math, not duplicated).
   double            EMA20SlopePoints(int lookback) const
     {
      return EMASlopePoints(EMA20(1), EMA20(1 + lookback), lookback);
     }

   double            EMA50SlopePoints(int lookback) const
     {
      return EMASlopePoints(EMA50(1), EMA50(1 + lookback), lookback);
     }

   // Copies the last `count` closed-bar ATR values into `out` (out[0] most recent).
   int               CopyATRSeries(double &out[], int count) const
     {
      int n = MathMin(count, ArraySize(m_atr) - 1);
      if(n <= 0)
         return 0;
      ArrayResize(out, n);
      for(int i = 0; i < n; i++)
         out[i] = m_atr[i + 1]; // skip forming bar
      return n;
     }

   int               CopyCloseSeries(double &out[], int count) const
     {
      int n = MathMin(count, ArraySize(m_close) - 1);
      if(n <= 0)
         return 0;
      ArrayResize(out, n);
      for(int i = 0; i < n; i++)
         out[i] = m_close[i + 1];
      return n;
     }

   double            HighestHigh(int shiftStart, int period) const
     {
      double hh = -DBL_MAX;
      for(int i = shiftStart; i < shiftStart + period; i++)
        {
         double h = High(i);
         if(h > hh)
            hh = h;
        }
      return hh;
     }

   double            LowestLow(int shiftStart, int period) const
     {
      double ll = DBL_MAX;
      for(int i = shiftStart; i < shiftStart + period; i++)
        {
         double l = Low(i);
         if(l < ll)
            ll = l;
        }
      return ll;
     }

private:
   double            EMASlopePoints(double now, double then, int lookback) const
     {
      if(now == 0.0 || then == 0.0 || lookback <= 0)
         return 0.0;
      double point = QXE_SymbolPoint(m_symbol);
      if(point <= 0.0)
         return 0.0;
      return ((now - then) / lookback) / point;
     }

   double            SafeGet(const double &arr[], int shift) const
     {
      if(shift < 0 || shift >= ArraySize(arr))
         return 0.0;
      return arr[shift];
     }
  };

#endif // QXE_TIMEFRAMEDATA_MQH
