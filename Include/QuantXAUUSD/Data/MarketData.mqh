#ifndef QXE_MARKETDATA_MQH
#define QXE_MARKETDATA_MQH

#include "TimeframeData.mqh"
#include "../Core/Types.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Utilities.mqh"

class CMarketData
  {
private:
   string m_symbol;
   CTimeframeData m_tfD1, m_tfH4, m_tfH1, m_tfM15, m_tfM5;
   double m_vwapCumPV, m_vwapCumVol;
   datetime m_vwapSessionAnchor, m_vwapLastBarAdded;
   double m_vwapValue;

public:
   bool Init(string symbol)
     {
      m_symbol = symbol;
      bool ok = true;
      ok = m_tfD1.Init(symbol, PERIOD_D1, QXE_HISTORY_D1) && ok;
      ok = m_tfH4.Init(symbol, PERIOD_H4, QXE_HISTORY_H4) && ok;
      ok = m_tfH1.Init(symbol, PERIOD_H1, QXE_HISTORY_H1) && ok;
      ok = m_tfM15.Init(symbol, PERIOD_M15, QXE_HISTORY_M15) && ok;
      ok = m_tfM5.Init(symbol, PERIOD_M5, QXE_HISTORY_M5) && ok;
      m_vwapCumPV = 0.0; m_vwapCumVol = 0.0; m_vwapSessionAnchor = 0;
      m_vwapLastBarAdded = 0; m_vwapValue = 0.0;
      return ok;
     }

   bool RefreshAll(void)
     {
      bool ok = true;
      ok = m_tfD1.Refresh() && ok; ok = m_tfH4.Refresh() && ok; ok = m_tfH1.Refresh() && ok;
      ok = m_tfM15.Refresh() && ok; ok = m_tfM5.Refresh() && ok;
      UpdateVWAP();
      return ok;
     }

   bool IsReady(void) const { return m_tfD1.IsReady() && m_tfH4.IsReady() && m_tfH1.IsReady() && m_tfM15.IsReady() && m_tfM5.IsReady(); }
   CTimeframeData *D1(void) { return GetPointer(m_tfD1); }
   CTimeframeData *H4(void) { return GetPointer(m_tfH4); }
   CTimeframeData *H1(void) { return GetPointer(m_tfH1); }
   CTimeframeData *M15(void) { return GetPointer(m_tfM15); }
   CTimeframeData *M5(void) { return GetPointer(m_tfM5); }
   double VWAP(void) const { return m_vwapValue; }
   double CurrentSpreadPoints(void) const { return (double)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD); }
   double Bid(void) const { return SymbolInfoDouble(m_symbol, SYMBOL_BID); }
   double Ask(void) const { return SymbolInfoDouble(m_symbol, SYMBOL_ASK); }

   double ATRPercentile(int lookback) const
     {
      double series[];
      int n = m_tfM5.CopyATRSeries(series, lookback);
      if(n <= 1) return 0.5;
      return QXE_PercentileRank(series, n, series[0]);
     }

private:
   void UpdateVWAP(void)
     {
      if(!m_tfM5.IsReady()) return;
      datetime barTime = m_tfM5.Time(1);
      MqlDateTime dt; TimeToStruct(barTime, dt); dt.hour = 0; dt.min = 0; dt.sec = 0;
      datetime dayAnchor = StructToTime(dt);

      if(dayAnchor != m_vwapSessionAnchor)
        {
         m_vwapSessionAnchor = dayAnchor;
         m_vwapCumPV = 0.0; m_vwapCumVol = 0.0; m_vwapLastBarAdded = 0; m_vwapValue = 0.0;
        }

      int bars = m_tfM5.Bars();
      int added = 0;
      for(int i = bars - 1; i >= 1; i--)
        {
         datetime t = m_tfM5.Time(i);
         if(t < dayAnchor) continue;
         if(m_vwapLastBarAdded > 0 && t <= m_vwapLastBarAdded) continue;
         AccumulateVWAPBar(i);
         m_vwapLastBarAdded = t;
         added++;
        }

      if(added > 1)
         g_Logger.Info(StringFormat("[VWAP-RECOVERY] addedClosedBars=%d last=%s", added, TimeToString(m_vwapLastBarAdded, TIME_DATE|TIME_MINUTES)));

      if(m_vwapCumVol > 0.0) m_vwapValue = m_vwapCumPV / m_vwapCumVol;
     }

   void AccumulateVWAPBar(int shift)
     {
      double typical = (m_tfM5.High(shift) + m_tfM5.Low(shift) + m_tfM5.Close(shift)) / 3.0;
      double vol = (double)m_tfM5.TickVolume(shift); if(vol <= 0.0) vol = 1.0;
      m_vwapCumPV += typical * vol; m_vwapCumVol += vol;
     }
  };
#endif
