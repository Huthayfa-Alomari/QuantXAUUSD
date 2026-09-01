#ifndef QXE_TIMEFRAMEDATA_MQH
#define QXE_TIMEFRAMEDATA_MQH

#include "../Core/Config.mqh"
#include "../Core/Constants.mqh"
#include "../Core/ErrorHandler.mqh"
#include "../Core/Utilities.mqh"

class CTimeframeData
  {
private:
   string m_symbol;
   ENUM_TIMEFRAMES m_tf;
   int m_historyBars;
   int m_hEMA20, m_hEMA50, m_hEMA200, m_hATR, m_hADX, m_hBB;
   double m_open[], m_high[], m_low[], m_close[];
   long m_tickVolume[];
   datetime m_time[];
   double m_ema20[], m_ema50[], m_ema200[], m_atr[];
   double m_adxMain[], m_adxPlusDI[], m_adxMinusDI[];
   double m_bbUpper[], m_bbMiddle[], m_bbLower[];
   datetime m_lastRefreshBarTime;
   bool m_ready;

public:
   CTimeframeData(void)
     {
      m_hEMA20 = m_hEMA50 = m_hEMA200 = INVALID_HANDLE;
      m_hATR = m_hADX = m_hBB = INVALID_HANDLE;
      m_lastRefreshBarTime = 0; m_ready = false;
     }
   ~CTimeframeData(void)
     {
      if(m_hEMA20 != INVALID_HANDLE) IndicatorRelease(m_hEMA20);
      if(m_hEMA50 != INVALID_HANDLE) IndicatorRelease(m_hEMA50);
      if(m_hEMA200 != INVALID_HANDLE) IndicatorRelease(m_hEMA200);
      if(m_hATR != INVALID_HANDLE) IndicatorRelease(m_hATR);
      if(m_hADX != INVALID_HANDLE) IndicatorRelease(m_hADX);
      if(m_hBB != INVALID_HANDLE) IndicatorRelease(m_hBB);
     }

   bool Init(string symbol, ENUM_TIMEFRAMES tf, int historyBars)
     {
      m_symbol = symbol; m_tf = tf; m_historyBars = historyBars;
      m_hEMA20 = iMA(symbol, tf, InpEMA20Period, 0, MODE_EMA, PRICE_CLOSE);
      m_hEMA50 = iMA(symbol, tf, InpEMA50Period, 0, MODE_EMA, PRICE_CLOSE);
      m_hEMA200 = iMA(symbol, tf, InpEMA200Period, 0, MODE_EMA, PRICE_CLOSE);
      m_hATR = iATR(symbol, tf, InpATRPeriod);
      m_hADX = iADX(symbol, tf, InpADXPeriod);
      m_hBB = iBands(symbol, tf, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
      bool ok = true;
      ok = QXE_ValidHandle(m_hEMA20, "EMA20 " + EnumToString(tf)) && ok;
      ok = QXE_ValidHandle(m_hEMA50, "EMA50 " + EnumToString(tf)) && ok;
      ok = QXE_ValidHandle(m_hEMA200, "EMA200 " + EnumToString(tf)) && ok;
      ok = QXE_ValidHandle(m_hATR, "ATR " + EnumToString(tf)) && ok;
      ok = QXE_ValidHandle(m_hADX, "ADX " + EnumToString(tf)) && ok;
      ok = QXE_ValidHandle(m_hBB, "Bands " + EnumToString(tf)) && ok;

      ArraySetAsSeries(m_open,true); ArraySetAsSeries(m_high,true); ArraySetAsSeries(m_low,true); ArraySetAsSeries(m_close,true);
      ArraySetAsSeries(m_tickVolume,true); ArraySetAsSeries(m_time,true);
      ArraySetAsSeries(m_ema20,true); ArraySetAsSeries(m_ema50,true); ArraySetAsSeries(m_ema200,true); ArraySetAsSeries(m_atr,true);
      ArraySetAsSeries(m_adxMain,true); ArraySetAsSeries(m_adxPlusDI,true); ArraySetAsSeries(m_adxMinusDI,true);
      ArraySetAsSeries(m_bbUpper,true); ArraySetAsSeries(m_bbMiddle,true); ArraySetAsSeries(m_bbLower,true);
      return ok;
     }

   bool Refresh(bool forceRefresh=false)
     {
      datetime barTime = iTime(m_symbol, m_tf, 0);
      if(barTime == 0) { m_ready=false; return false; }
      if(!forceRefresh && barTime == m_lastRefreshBarTime && m_ready) return true;

      int need = m_historyBars;
      int gotOpen = CopyOpen(m_symbol,m_tf,0,need,m_open);
      int gotHigh = CopyHigh(m_symbol,m_tf,0,need,m_high);
      int gotLow = CopyLow(m_symbol,m_tf,0,need,m_low);
      int gotClose = CopyClose(m_symbol,m_tf,0,need,m_close);
      int gotVol = CopyTickVolume(m_symbol,m_tf,0,need,m_tickVolume);
      int gotTime = CopyTime(m_symbol,m_tf,0,need,m_time);
      if(gotOpen <= 0 || gotHigh <= 0 || gotLow <= 0 || gotClose <= 0 || gotVol <= 0 || gotTime <= 0)
        {
         g_Logger.Warn(StringFormat("TimeframeData(%s): CopyRates failed err=%d", EnumToString(m_tf), GetLastError()));
         m_ready=false; return false;
        }

      int gotEMA20=CopyBuffer(m_hEMA20,0,0,need,m_ema20);
      int gotEMA50=CopyBuffer(m_hEMA50,0,0,need,m_ema50);
      int gotEMA200=CopyBuffer(m_hEMA200,0,0,need,m_ema200);
      int gotATR=CopyBuffer(m_hATR,0,0,need,m_atr);
      int gotADXm=CopyBuffer(m_hADX,0,0,need,m_adxMain);
      int gotADXp=CopyBuffer(m_hADX,1,0,need,m_adxPlusDI);
      int gotADXn=CopyBuffer(m_hADX,2,0,need,m_adxMinusDI);
      int gotBBu=CopyBuffer(m_hBB,1,0,need,m_bbUpper);
      int gotBBm=CopyBuffer(m_hBB,0,0,need,m_bbMiddle);
      int gotBBl=CopyBuffer(m_hBB,2,0,need,m_bbLower);

      int minIndicators = MathMin(gotEMA20, MathMin(gotEMA50, MathMin(gotEMA200, MathMin(gotATR, MathMin(gotADXm, MathMin(gotADXp, MathMin(gotADXn, MathMin(gotBBu, MathMin(gotBBm, gotBBl)))))))));
      int minPrices = MathMin(gotOpen, MathMin(gotHigh, MathMin(gotLow, MathMin(gotClose, MathMin(gotVol, gotTime)))));
      int minAvailable = MathMin(minIndicators, minPrices);
      if(minAvailable < QXE_MIN_BARS_REQUIRED)
         g_Logger.Debug(StringFormat("TimeframeData(%s): not ready (%d bars, required=%d)", EnumToString(m_tf), minAvailable, QXE_MIN_BARS_REQUIRED));

      m_ready = (minAvailable >= QXE_MIN_BARS_REQUIRED);
      m_lastRefreshBarTime = barTime;
      return m_ready;
     }

   bool IsReady(void) const { return m_ready; }
   int Bars(void) const { return ArraySize(m_close); }

   // Native series indexing: 0=current/forming bar; 1=latest CLOSED bar.
   double Close(int shift) const { return SafeGet(m_close,shift); }
   double Open(int shift) const { return SafeGet(m_open,shift); }
   double High(int shift) const { return SafeGet(m_high,shift); }
   double Low(int shift) const { return SafeGet(m_low,shift); }
   datetime Time(int shift) const { return (shift<0 || shift>=ArraySize(m_time)) ? 0 : m_time[shift]; }
   long TickVolume(int shift) const { return (shift<0 || shift>=ArraySize(m_tickVolume)) ? 0 : m_tickVolume[shift]; }
   double EMA20(int shift) const { return SafeGet(m_ema20,shift); }
   double EMA50(int shift) const { return SafeGet(m_ema50,shift); }
   double EMA200(int shift) const { return SafeGet(m_ema200,shift); }
   double ATR(int shift) const { return SafeGet(m_atr,shift); }
   double ADX(int shift) const { return SafeGet(m_adxMain,shift); }
   double ADXPlus(int shift) const { return SafeGet(m_adxPlusDI,shift); }
   double ADXMinus(int shift) const { return SafeGet(m_adxMinusDI,shift); }
   double BBUpper(int shift) const { return SafeGet(m_bbUpper,shift); }
   double BBMiddle(int shift) const { return SafeGet(m_bbMiddle,shift); }
   double BBLower(int shift) const { return SafeGet(m_bbLower,shift); }

   double EMA200SlopePoints(int lookback) const { return EMASlopeFromArray(m_ema200, lookback); }
   double EMA20SlopePoints(int lookback) const { return EMASlopeFromArray(m_ema20, lookback); }
   double EMA50SlopePoints(int lookback) const { return EMASlopeFromArray(m_ema50, lookback); }

   int CopyATRSeries(double &out[], int count) const
     {
      int n=MathMin(count,ArraySize(m_atr)-1); if(n<=0) return 0;
      ArrayResize(out,n); for(int i=0;i<n;i++) out[i]=m_atr[i+1]; return n;
     }
   int CopyCloseSeries(double &out[], int count) const
     {
      int n=MathMin(count,ArraySize(m_close)-1); if(n<=0) return 0;
      ArrayResize(out,n); for(int i=0;i<n;i++) out[i]=m_close[i+1]; return n;
     }

   double HighestHigh(int shiftStart, int period) const
     {
      if(shiftStart < 0 || period <= 0 || shiftStart + period > ArraySize(m_high)) return EMPTY_VALUE;
      double hh=m_high[shiftStart]; for(int i=shiftStart+1;i<shiftStart+period;i++) if(m_high[i]>hh) hh=m_high[i]; return hh;
     }
   double LowestLow(int shiftStart, int period) const
     {
      if(shiftStart < 0 || period <= 0 || shiftStart + period > ArraySize(m_low)) return EMPTY_VALUE;
      double ll=m_low[shiftStart]; for(int i=shiftStart+1;i<shiftStart+period;i++) if(m_low[i]<ll) ll=m_low[i]; return ll;
     }

private:
   double EMASlopeFromArray(const double &arr[], int lookback) const
     {
      int farShift=1+lookback;
      if(lookback<=0 || farShift>=ArraySize(arr)) return 0.0;
      return EMASlopePoints(arr[1],arr[farShift],lookback);
     }
   double EMASlopePoints(double now,double then,int lookback) const
     {
      if(now==0.0 || then==0.0 || lookback<=0) return 0.0;
      double point=QXE_SymbolPoint(m_symbol); if(point<=0.0) return 0.0;
      return ((now-then)/lookback)/point;
     }
   double SafeGet(const double &arr[], int shift) const
     {
      if(shift<0 || shift>=ArraySize(arr)) return 0.0; return arr[shift];
     }
  };

#endif
