//+------------------------------------------------------------------+
//| FVGDetector.mqh                                                  |
//| QUANT_XAUUSD_ENGINE - Fair Value Gap detection                   |
//|                                                                   |
//| 3-candle window: A = oldest, B = middle, C = newest (shift order: |
//| A = shift+2, B = shift+1, C = shift).                             |
//|   Bullish FVG:  Low[C]  > High[A]   (upward gap left behind)     |
//|   Bearish FVG:  High[C] < Low[A]    (downward gap left behind)   |
//| CORRECTED (repair pass): the original definition here had A/C    |
//| reversed, which silently swapped bullish and bearish zones. This |
//| direction (Low[C] > High[A] = bullish) is the standard ICT/SMC   |
//| convention and is now verified against that definition.          |
//| An FVG is never a standalone entry signal - only a confirmation  |
//| / entry-location input used by other strategies.                 |
//+------------------------------------------------------------------+
#ifndef QXE_FVGDETECTOR_MQH
#define QXE_FVGDETECTOR_MQH

#include "../Data/TimeframeData.mqh"
#include "../Core/Types.mqh"

struct FVGZone
  {
   bool              bullish;
   double            top;
   double            bottom;
   datetime          time;
  };

class CFVGDetector
  {
public:
   // Checks the 3-candle window ending at `shift` (shift = C, the most
   // recent/newest candle of the three) for a valid FVG.
   bool              Detect(CTimeframeData *tf, int shift, FVGZone &zone) const
     {
      // candle A (oldest) = shift+2, candle B (middle) = shift+1, candle C (newest) = shift
      double lowA  = tf.Low(shift + 2);
      double highA = tf.High(shift + 2);
      double lowC  = tf.Low(shift);
      double highC = tf.High(shift);

      if(lowC > highA)
        {
         zone.bullish = true;
         zone.top = lowC;
         zone.bottom = highA;
         zone.time = tf.Time(shift);
         return true;
        }
      if(highC < lowA)
        {
         zone.bullish = false;
         zone.top = lowA;
         zone.bottom = highC;
         zone.time = tf.Time(shift);
         return true;
        }
      return false;
     }

   // Returns true if `price` currently sits inside the given FVG zone.
   bool              PriceInZone(const FVGZone &zone, double price) const
     {
      return (price <= zone.top && price >= zone.bottom);
     }
  };

#endif // QXE_FVGDETECTOR_MQH
