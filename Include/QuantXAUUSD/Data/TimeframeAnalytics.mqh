//+------------------------------------------------------------------+
//| TimeframeAnalytics.mqh                                           |
//| QUANT_XAUUSD_ENGINE - Shared CTimeframeData analytics helpers    |
//|                                                                   |
//| Lives in Data/ (not Core/Utilities.mqh) specifically to avoid a  |
//| circular include: TimeframeData.mqh already depends on           |
//| Core/Utilities.mqh (for QXE_SymbolPoint), so these two helpers -  |
//| which need the full CTimeframeData class definition - cannot     |
//| live in Utilities.mqh without creating a cycle.                  |
//+------------------------------------------------------------------+
#ifndef QXE_TIMEFRAMEANALYTICS_MQH
#define QXE_TIMEFRAMEANALYTICS_MQH

#include "TimeframeData.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Utilities.mqh"

// Average |close-open| / (high-low) over the last `bars` closed candles -
// a simple, unitless measure of per-bar directional efficiency (1.0 =
// every bar closed at its extreme; near 0 = mostly wick/chop). Shared by
// RegimeEngine and the Market State Engine (Architecture v2) - single
// source of truth, not duplicated.
double QXE_AverageRangeEfficiency(CTimeframeData *tf, int bars)
  {
   double sum = 0.0;
   int counted = 0;
   for(int i = 1; i <= bars; i++)
     {
      double range = tf.High(i) - tf.Low(i);
      if(range <= QXE_EPS)
         continue;
      double body = MathAbs(tf.Close(i) - tf.Open(i));
      sum += body / range;
      counted++;
     }
   return (counted > 0) ? sum / counted : 0.5;
  }

// Net displacement over `bars` closed candles divided by the summed
// per-bar range - distinguishes a smoothly trending market (high value)
// from one that covers the same net distance via choppy back-and-forth
// (low value), which per-bar efficiency alone does not capture.
double QXE_TrendEfficiency(CTimeframeData *tf, int bars)
  {
   double netDisplacement = MathAbs(tf.Close(1) - tf.Close(1 + bars));
   double summedRange = 0.0;
   for(int i = 1; i <= bars; i++)
      summedRange += (tf.High(i) - tf.Low(i));
   if(summedRange <= QXE_EPS)
      return 0.5;
   return QXE_Clamp(netDisplacement / summedRange, 0.0, 1.0);
  }

#endif // QXE_TIMEFRAMEANALYTICS_MQH
