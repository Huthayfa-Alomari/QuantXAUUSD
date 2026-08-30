//+------------------------------------------------------------------+
//| EntryEngine.mqh                                                  |
//| QUANT_XAUUSD_ENGINE - Entry refinement / confirmation             |
//|                                                                   |
//| Combines EntryEngine + ConfirmationEngine from the spec tree:    |
//| given a directional bias from a strategy, this module checks for |
//| an FVG confirmation nearby and proposes a structural stop.       |
//| (Consolidation documented in README.)                            |
//+------------------------------------------------------------------+
#ifndef QXE_ENTRYENGINE_MQH
#define QXE_ENTRYENGINE_MQH

#include "FVGDetector.mqh"
#include "DisplacementDetector.mqh"
#include "../Data/TimeframeData.mqh"
#include "../Core/Types.mqh"

class CEntryEngine
  {
private:
   CFVGDetector      m_fvg;
   CDisplacementDetector m_disp;

public:
   // Scans the last `lookback` closed bars for an FVG matching `direction`.
   // Returns true and fills `zone` with the most recent matching FVG.
   bool              FindConfirmingFVG(CTimeframeData *tf, SignalDirection direction, int lookback, FVGZone &zone) const
     {
      bool wantBullish = (direction == SIGNAL_BUY);
      for(int shift = 1; shift < lookback; shift++)
        {
         FVGZone candidate;
         if(m_fvg.Detect(tf, shift, candidate) && candidate.bullish == wantBullish)
           {
            zone = candidate;
            return true;
           }
        }
      return false;
     }

   bool              HasDisplacement(CTimeframeData *tf, SignalDirection direction) const
     {
      int dir = (direction == SIGNAL_BUY) ? 1 : (direction == SIGNAL_SELL ? -1 : 0);
      return m_disp.IsDisplacement(tf, 1, dir);
     }

   // Structural stop: beyond the most recent swing in the direction of risk,
   // with a small ATR-based buffer to avoid stop hunts on the exact level.
   double            StructuralStop(CTimeframeData *tf, SignalDirection direction, double swingLevel) const
     {
      double atr = tf.ATR(1);
      double buffer = atr * 0.25;
      if(direction == SIGNAL_BUY)
         return swingLevel - buffer;
      if(direction == SIGNAL_SELL)
         return swingLevel + buffer;
      return 0.0;
     }
  };

#endif // QXE_ENTRYENGINE_MQH
