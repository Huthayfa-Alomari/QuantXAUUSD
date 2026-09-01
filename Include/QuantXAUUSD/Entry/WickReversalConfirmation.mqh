//+------------------------------------------------------------------+
//| WickReversalConfirmation.mqh                                     |
//| QUANT_XAUUSD_ENGINE - Wick rejection confirmation primitive       |
//|                                                                  |
//| Purpose:                                                         |
//| - Confirmation / feature only.                                   |
//| - Does NOT open trades, size risk, or manage positions.           |
//| - Designed to be consumed by MomentumPullback, VWAP,              |
//|   LiquiditySweep, or the Interaction Matrix.                      |
//|                                                                  |
//| Uses CLOSED-candle values supplied by the caller.                 |
//+------------------------------------------------------------------+
#ifndef QXE_WICK_REVERSAL_CONFIRMATION_MQH
#define QXE_WICK_REVERSAL_CONFIRMATION_MQH

struct WickReversalResult
  {
   bool   valid;
   bool   bullish;
   bool   bearish;

   double quality;          // 0..100
   double body;
   double range;
   double upperWick;
   double lowerWick;
   double wickBodyRatio;
   double wickRangeRatio;
   double rangeATRRatio;

   bool   piercedBand;
   bool   closedBackInside;
   string reason;
  };

class CWickReversalConfirmation
  {
private:
   static double Clamp100(const double value)
     {
      if(value < 0.0)   return 0.0;
      if(value > 100.0) return 100.0;
      return value;
     }

   static void Reset(WickReversalResult &r)
     {
      r.valid             = false;
      r.bullish           = false;
      r.bearish           = false;
      r.quality           = 0.0;
      r.body              = 0.0;
      r.range             = 0.0;
      r.upperWick         = 0.0;
      r.lowerWick         = 0.0;
      r.wickBodyRatio     = 0.0;
      r.wickRangeRatio    = 0.0;
      r.rangeATRRatio     = 0.0;
      r.piercedBand       = false;
      r.closedBackInside  = false;
      r.reason            = "";
     }

public:
   // Conservative defaults chosen for research, not optimized:
   // minWickBodyRatio  = 2.0
   // minWickRangeRatio = 0.45
   // minRangeATRRatio  = 0.50
   //
   // A valid setup REQUIRES:
   // 1) price pierces the relevant Bollinger band;
   // 2) candle closes back inside the band;
   // 3) rejection wick dominates body;
   // 4) rejection wick is a meaningful fraction of total range;
   // 5) candle range is not trivially small vs ATR;
   // 6) candle closes in the rejection direction.
   static bool Evaluate(const double open,
                        const double high,
                        const double low,
                        const double close,
                        const double bbUpper,
                        const double bbLower,
                        const double atr,
                        WickReversalResult &out,
                        const double minWickBodyRatio  = 2.0,
                        const double minWickRangeRatio = 0.45,
                        const double minRangeATRRatio  = 0.50)
     {
      Reset(out);

      if(high <= low || atr <= 0.0 || bbUpper <= bbLower)
        {
         out.reason = "invalid candle/ATR/Bollinger inputs";
         return false;
        }

      out.range = high - low;
      out.body  = MathAbs(close - open);

      // Avoid division by zero without making a doji automatically valid.
      double safeBody = MathMax(out.body, out.range * 0.05);

      out.upperWick = high - MathMax(open, close);
      out.lowerWick = MathMin(open, close) - low;

      if(out.upperWick < 0.0) out.upperWick = 0.0;
      if(out.lowerWick < 0.0) out.lowerWick = 0.0;

      out.rangeATRRatio = out.range / atr;

      bool bullishCandle = (close > open);
      bool bearishCandle = (close < open);

      // ---------------------------------------------------------------
      // Bullish rejection:
      // low pierces lower band, then close returns INSIDE the band.
      // ---------------------------------------------------------------
      bool bullPierce = (low < bbLower);
      bool bullReturn = (close > bbLower);
      double bullBodyRatio  = out.lowerWick / safeBody;
      double bullRangeRatio = out.lowerWick / out.range;

      bool bullValid =
         bullPierce &&
         bullReturn &&
         bullishCandle &&
         bullBodyRatio  >= minWickBodyRatio &&
         bullRangeRatio >= minWickRangeRatio &&
         out.rangeATRRatio >= minRangeATRRatio;

      // ---------------------------------------------------------------
      // Bearish rejection:
      // high pierces upper band, then close returns INSIDE the band.
      // ---------------------------------------------------------------
      bool bearPierce = (high > bbUpper);
      bool bearReturn = (close < bbUpper);
      double bearBodyRatio  = out.upperWick / safeBody;
      double bearRangeRatio = out.upperWick / out.range;

      bool bearValid =
         bearPierce &&
         bearReturn &&
         bearishCandle &&
         bearBodyRatio  >= minWickBodyRatio &&
         bearRangeRatio >= minWickRangeRatio &&
         out.rangeATRRatio >= minRangeATRRatio;

      // Ambiguous pathological candle: reject if both somehow qualify.
      if(bullValid && bearValid)
        {
         out.reason = "ambiguous two-sided wick rejection";
         return false;
        }

      if(!bullValid && !bearValid)
        {
         out.reason = "wick rejection conditions not met";
         return false;
        }

      out.valid    = true;
      out.bullish  = bullValid;
      out.bearish  = bearValid;

      if(bullValid)
        {
         out.piercedBand      = bullPierce;
         out.closedBackInside = bullReturn;
         out.wickBodyRatio    = bullBodyRatio;
         out.wickRangeRatio   = bullRangeRatio;
        }
      else
        {
         out.piercedBand      = bearPierce;
         out.closedBackInside = bearReturn;
         out.wickBodyRatio    = bearBodyRatio;
         out.wickRangeRatio   = bearRangeRatio;
        }

      // Research-quality score, intentionally simple and bounded.
      // 40 pts wick/body, 35 pts wick/range, 25 pts candle range/ATR.
      double bodyComponent =
         MathMin(out.wickBodyRatio / MathMax(minWickBodyRatio, 0.01), 2.0) / 2.0 * 40.0;

      double rangeComponent =
         MathMin(out.wickRangeRatio / MathMax(minWickRangeRatio, 0.01), 1.5) / 1.5 * 35.0;

      double atrComponent =
         MathMin(out.rangeATRRatio / MathMax(minRangeATRRatio, 0.01), 2.0) / 2.0 * 25.0;

      out.quality = Clamp100(bodyComponent + rangeComponent + atrComponent);

      out.reason = StringFormat(
         "%s wick rejection q=%.1f wick/body=%.2f wick/range=%.2f range/ATR=%.2f",
         out.bullish ? "bullish" : "bearish",
         out.quality,
         out.wickBodyRatio,
         out.wickRangeRatio,
         out.rangeATRRatio);

      return true;
     }
  };

#endif // QXE_WICK_REVERSAL_CONFIRMATION_MQH
