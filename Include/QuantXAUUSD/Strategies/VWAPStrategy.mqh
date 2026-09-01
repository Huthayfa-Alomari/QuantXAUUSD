//+------------------------------------------------------------------+
//| VWAPStrategy.mqh                                                 |
//| QUANT_XAUUSD_ENGINE - VWAP strategy                              |
//| Wick Reversal v2.1: range-only mean-reversion confirmation.      |
//| Fix: Bollinger bands via native iBands handle, no StdDev20().     |
//+------------------------------------------------------------------+
#ifndef QXE_VWAPSTRATEGY_MQH
#define QXE_VWAPSTRATEGY_MQH

#include "IStrategy.mqh"
#include "../Entry/WickReversalConfirmation.mqh"
#include "../Core/Config.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Utilities.mqh"

class CVWAPStrategy : public IStrategy
  {
private:
   int m_bbHandleM5;

   bool EnsureIndicators(void)
     {
      if(m_bbHandleM5 != INVALID_HANDLE)
         return true;

      m_bbHandleM5 = iBands(_Symbol,
                           PERIOD_M5,
                           InpBBPeriod,
                           0,
                           InpBBDeviation,
                           PRICE_CLOSE);

      return (m_bbHandleM5 != INVALID_HANDLE);
     }

   bool GetM5Bands(const int shift,
                   double &upper,
                   double &middle,
                   double &lower)
     {
      upper  = 0.0;
      middle = 0.0;
      lower  = 0.0;

      if(!EnsureIndicators())
         return false;

      if(BarsCalculated(m_bbHandleM5) <= shift)
         return false;

      double baseBuf[1];
      double upperBuf[1];
      double lowerBuf[1];

      // MQL5 iBands:
      // buffer 0 = BASE_LINE
      // buffer 1 = UPPER_BAND
      // buffer 2 = LOWER_BAND
      if(CopyBuffer(m_bbHandleM5, 0, shift, 1, baseBuf)  != 1)
         return false;
      if(CopyBuffer(m_bbHandleM5, 1, shift, 1, upperBuf) != 1)
         return false;
      if(CopyBuffer(m_bbHandleM5, 2, shift, 1, lowerBuf) != 1)
         return false;

      middle = baseBuf[0];
      upper  = upperBuf[0];
      lower  = lowerBuf[0];

      return (upper > lower && middle > 0.0);
     }

public:
   CVWAPStrategy(void)
      : m_bbHandleM5(INVALID_HANDLE)
     {
     }

   ~CVWAPStrategy(void)
     {
      if(m_bbHandleM5 != INVALID_HANDLE)
        {
         IndicatorRelease(m_bbHandleM5);
         m_bbHandleM5 = INVALID_HANDLE;
        }
     }

   StrategyType Type(void) override { return STRAT_VWAP; }
   string Name(void) override { return "VWAP"; }

   bool Evaluate(CMarketData *md,
                 const MarketState &state,
                 Signal &outSignal) override
     {
      outSignal.direction = SIGNAL_NONE;

      if(!EnableVWAP)
         return false;

      CTimeframeData *m5 = md.M5();

      double vwap = md.VWAP();
      if(vwap <= 0.0)
         return false;

      double open1  = m5.Open(1);
      double high1  = m5.High(1);
      double low1   = m5.Low(1);
      double close1 = m5.Close(1);
      double atr    = m5.ATR(1);

      SignalDirection dir = SIGNAL_NONE;
      double score = 0.0;
      string reason = "";

      if(state.regime == REGIME_TREND_BULL ||
         state.regime == REGIME_TREND_BEAR)
        {
         double distPoints =
            QXE_PriceToPoints(
               _Symbol,
               MathAbs(close1 - vwap));

         bool nearVwap =
            distPoints <
            (atr / QXE_SymbolPoint(_Symbol)) * 0.5;

         if(state.regime == REGIME_TREND_BULL &&
            close1 >= vwap &&
            nearVwap)
           {
            dir = SIGNAL_BUY;
            reason =
               "Price reclaiming VWAP in bull trend";
           }
         else if(state.regime == REGIME_TREND_BEAR &&
                 close1 <= vwap &&
                 nearVwap)
           {
            dir = SIGNAL_SELL;
            reason =
               "Price rejecting VWAP in bear trend";
           }

         score = 55.0;

         // v2.1: no Wick promotion in trend VWAP mode.
        }
      else if(state.regime == REGIME_RANGE)
        {
         double distAtr =
            (atr > QXE_EPS)
            ? MathAbs(close1 - vwap) / atr
            : 0.0;

         if(distAtr >= 1.5)
           {
            dir =
               (close1 > vwap)
               ? SIGNAL_SELL
               : SIGNAL_BUY;

            reason =
               StringFormat(
                  "Price extended %.2fATR from VWAP in range",
                  distAtr);

            score =
               QXE_Clamp(
                  45.0 + distAtr * 10.0,
                  0.0,
                  100.0);
           }
        }

      if(dir == SIGNAL_NONE)
         return false;

      // Wick v2.1:
      // range-only confirmation for VWAP mean reversion.
      if(state.regime == REGIME_RANGE && atr > 0.0)
        {
         double bbUpper;
         double bbMiddle;
         double bbLower;

         if(GetM5Bands(1, bbUpper, bbMiddle, bbLower))
           {
            WickReversalResult wick;

            bool wickValid =
               CWickReversalConfirmation::Evaluate(
                  open1,
                  high1,
                  low1,
                  close1,
                  bbUpper,
                  bbLower,
                  atr,
                  wick);

            bool wickAligned =
               wickValid &&
               ((dir == SIGNAL_BUY  && wick.bullish) ||
                (dir == SIGNAL_SELL && wick.bearish));

            if(wickAligned)
  {
   double baseScore = score;

   double wickBoost =
      QXE_Clamp(3.0 + wick.quality * 0.05,
                3.0,
                8.0);

   double finalScore =
      QXE_Clamp(baseScore + wickBoost,
                0.0,
                100.0);

   PrintFormat(
      "[WICK-TELEMETRY] strategy=VWAP dir=%s regime=%s quality=%.1f baseScore=%.1f boost=%.1f finalScore=%.1f crossed70=%s",
      (dir == SIGNAL_BUY ? "BUY" : "SELL"),
      EnumToString(state.regime),
      wick.quality,
      baseScore,
      wickBoost,
      finalScore,
      (baseScore < InpMinScore && finalScore >= InpMinScore) ? "YES" : "NO"
   );

   score = finalScore;

   reason +=
      StringFormat(
         " + WickV2Range(q=%.1f,+%.1f)",
         wick.quality,
         wickBoost
      );
  }
           }
        }

      double entry = close1;

      double stop =
         (dir == SIGNAL_BUY)
         ? entry - atr * InpATRStopMultiplier
         : entry + atr * InpATRStopMultiplier;

      double target = vwap;

      outSignal.strategy   = STRAT_VWAP;
      outSignal.direction  = dir;
      outSignal.score      = score;
      outSignal.confidence = score / 100.0;
      outSignal.entry      = entry;
      outSignal.stop       = stop;
      outSignal.target     = target;
      outSignal.timestamp  = m5.Time(1);
      outSignal.regime     = state.regime;
      outSignal.reason     = reason;

      return true;
     }
  };

#endif // QXE_VWAPSTRATEGY_MQH
