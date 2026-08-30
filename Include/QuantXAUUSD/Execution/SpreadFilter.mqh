//+------------------------------------------------------------------+
//| SpreadFilter.mqh                                                 |
//| QUANT_XAUUSD_ENGINE - Spread validation (spec section 31)        |
//+------------------------------------------------------------------+
#ifndef QXE_SPREADFILTER_MQH
#define QXE_SPREADFILTER_MQH

#include "../Core/Config.mqh"

class CSpreadFilter
  {
public:
   bool              IsAcceptable(double currentSpreadPoints, double atrM5Price, string symbol, string &reason) const
     {
      if(currentSpreadPoints > InpMaxSpreadPoints)
        {
         reason = StringFormat("Spread %.0f points > max %.0f points", currentSpreadPoints, InpMaxSpreadPoints);
         return false;
        }

      double atrPoints = QXE_PriceToPoints(symbol, atrM5Price);
      if(atrPoints > 0.0)
        {
         double ratio = currentSpreadPoints / atrPoints;
         if(ratio > InpMaxSpreadATRRatio)
           {
            reason = StringFormat("Spread/ATR ratio %.2f > max %.2f (abnormal spread)", ratio, InpMaxSpreadATRRatio);
            return false;
           }
        }

      reason = "";
      return true;
     }
  };

#endif // QXE_SPREADFILTER_MQH
