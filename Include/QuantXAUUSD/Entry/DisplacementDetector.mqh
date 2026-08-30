//+------------------------------------------------------------------+
//| DisplacementDetector.mqh                                         |
//| QUANT_XAUUSD_ENGINE - Displacement candle detection               |
//|                                                                   |
//| Displacement = body/range ratio >= threshold AND candle range >= |
//| ATR x multiplier (spec section 17). All parameters configurable. |
//+------------------------------------------------------------------+
#ifndef QXE_DISPLACEMENTDETECTOR_MQH
#define QXE_DISPLACEMENTDETECTOR_MQH

#include "../Data/TimeframeData.mqh"
#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Constants.mqh"

class CDisplacementDetector
  {
public:
   // direction: 1 = require bullish displacement, -1 = bearish, 0 = either.
   bool              IsDisplacement(CTimeframeData *tf, int shift, int direction) const
     {
      double open  = tf.Open(shift);
      double close = tf.Close(shift);
      double high  = tf.High(shift);
      double low   = tf.Low(shift);
      double atr   = tf.ATR(shift);

      double range = high - low;
      if(range <= QXE_EPS || atr <= QXE_EPS)
         return false;

      double body = MathAbs(close - open);
      double bodyRatio = body / range;

      bool bigEnough = (range >= atr * InpDisplacementATRMult);
      bool bodyEnough = (bodyRatio >= InpDisplacementBodyRatio);

      if(!bigEnough || !bodyEnough)
         return false;

      if(direction > 0)
         return (close > open);
      if(direction < 0)
         return (close < open);
      return true;
     }
  };

#endif // QXE_DISPLACEMENTDETECTOR_MQH
