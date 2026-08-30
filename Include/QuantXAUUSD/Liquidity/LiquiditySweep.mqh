//+------------------------------------------------------------------+
//| LiquiditySweep.mqh                                               |
//| QUANT_XAUUSD_ENGINE - Liquidity sweep confirmation                |
//|                                                                   |
//| A sweep requires: level violation (wick beyond level) + close     |
//| back inside + optional displacement/structure confirmation.       |
//| A simple touch is NEVER treated as a sweep (spec section 15).     |
//+------------------------------------------------------------------+
#ifndef QXE_LIQUIDITYSWEEP_MQH
#define QXE_LIQUIDITYSWEEP_MQH

#include "LiquidityLevels.mqh"
#include "../Structure/MarketStructure.mqh"
#include "../Entry/DisplacementDetector.mqh"
#include "../Core/Config.mqh"

struct SweepResult
  {
   bool              found;
   LiquidityLevelType levelType;
   double            levelPrice;
   SignalDirection   direction;   // direction implied by the reversal after sweep
   bool              displacementConfirmed;
  };

class CLiquiditySweep
  {
public:
   // Checks the most recently closed bar (shift 1) against all tracked
   // levels for a confirmed sweep: high/low pierces the level but the
   // close comes back inside it.
   SweepResult       Detect(CTimeframeData *h1, CLiquidityLevels *levels, CDisplacementDetector *disp)
     {
      SweepResult result;
      result.found = false;
      result.levelType = LIQ_PDH;
      result.levelPrice = 0.0;
      result.direction = SIGNAL_NONE;
      result.displacementConfirmed = false;

      double high1 = h1.High(1);
      double low1 = h1.Low(1);
      double close1 = h1.Close(1);

      for(int i = 0; i < levels.Count(); i++)
        {
         LiquidityLevel lvl = levels.Get(i);
         if(lvl.swept || lvl.price <= 0.0)
            continue;

         bool isHighLevel = (lvl.type == LIQ_PDH || lvl.type == LIQ_PWH ||
                              lvl.type == LIQ_SWING_HIGH || lvl.type == LIQ_EQUAL_HIGH);
         bool isLowLevel  = (lvl.type == LIQ_PDL || lvl.type == LIQ_PWL ||
                              lvl.type == LIQ_SWING_LOW || lvl.type == LIQ_EQUAL_LOW);

         if(isHighLevel && high1 > lvl.price && close1 < lvl.price)
           {
            bool dispOk = !InpRequireDisplacementForSweep || disp.IsDisplacement(h1, 1, -1);
            if(dispOk)
              {
               result.found = true;
               result.levelType = lvl.type;
               result.levelPrice = lvl.price;
               result.direction = SIGNAL_SELL; // swept buy-side liquidity -> bearish reversal bias
               result.displacementConfirmed = disp.IsDisplacement(h1, 1, -1);
               levels.MarkSwept(i);
               return result;
              }
           }
         else if(isLowLevel && low1 < lvl.price && close1 > lvl.price)
           {
            bool dispOk = !InpRequireDisplacementForSweep || disp.IsDisplacement(h1, 1, 1);
            if(dispOk)
              {
               result.found = true;
               result.levelType = lvl.type;
               result.levelPrice = lvl.price;
               result.direction = SIGNAL_BUY; // swept sell-side liquidity -> bullish reversal bias
               result.displacementConfirmed = disp.IsDisplacement(h1, 1, 1);
               levels.MarkSwept(i);
               return result;
              }
           }
        }

      return result;
     }
  };

#endif // QXE_LIQUIDITYSWEEP_MQH
