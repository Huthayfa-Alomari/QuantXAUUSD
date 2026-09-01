//+------------------------------------------------------------------+
//| MomentumPullback.mqh                                             |
//| QUANT_XAUUSD_ENGINE - Momentum Pullback                           |
//| Wick Reversal v2.1: regime-gated confirmation boost only.        |
//| Fix: Bollinger bands via native iBands handle, no StdDev20().     |
//+------------------------------------------------------------------+
#ifndef QXE_MOMENTUMPULLBACK_MQH
#define QXE_MOMENTUMPULLBACK_MQH

#include "IStrategy.mqh"
#include "../Structure/SwingDetector.mqh"
#include "../Entry/WickReversalConfirmation.mqh"
#include "../Core/Config.mqh"
#include "../Core/Utilities.mqh"

class CMomentumPullback : public IStrategy
  {
private:
   CSwingDetector m_swings;
   bool           m_initialized;
   int            m_bbHandleH1;

   bool EnsureIndicators(void)
     {
      if(m_bbHandleH1 != INVALID_HANDLE)
         return true;

      m_bbHandleH1 = iBands(_Symbol,
                           PERIOD_H1,
                           InpBBPeriod,
                           0,
                           InpBBDeviation,
                           PRICE_CLOSE);

      return (m_bbHandleH1 != INVALID_HANDLE);
     }

   bool GetH1Bands(const int shift,
                   double &upper,
                   double &middle,
                   double &lower)
     {
      upper  = 0.0;
      middle = 0.0;
      lower  = 0.0;

      if(!EnsureIndicators())
         return false;

      if(BarsCalculated(m_bbHandleH1) <= shift)
         return false;

      double baseBuf[1];
      double upperBuf[1];
      double lowerBuf[1];

      // MQL5 iBands buffers:
      // 0 = BASE_LINE
      // 1 = UPPER_BAND
      // 2 = LOWER_BAND
      if(CopyBuffer(m_bbHandleH1, 0, shift, 1, baseBuf)  != 1)
         return false;
      if(CopyBuffer(m_bbHandleH1, 1, shift, 1, upperBuf) != 1)
         return false;
      if(CopyBuffer(m_bbHandleH1, 2, shift, 1, lowerBuf) != 1)
         return false;

      middle = baseBuf[0];
      upper  = upperBuf[0];
      lower  = lowerBuf[0];

      return (upper > lower && middle > 0.0);
     }

public:
   CMomentumPullback(void)
      : m_initialized(false),
        m_bbHandleH1(INVALID_HANDLE)
     {
     }

   ~CMomentumPullback(void)
     {
      if(m_bbHandleH1 != INVALID_HANDLE)
        {
         IndicatorRelease(m_bbHandleH1);
         m_bbHandleH1 = INVALID_HANDLE;
        }
     }

   StrategyType Type(void) override { return STRAT_MOMENTUM_PULLBACK; }
   string Name(void) override { return "MomentumPullback"; }

   bool Evaluate(CMarketData *md, const MarketState &state, Signal &outSignal) override
     {
      outSignal.direction = SIGNAL_NONE;
      if(!EnablePullback)
         return false;

      if(!m_initialized)
        {
         m_swings.Init(InpPullbackSwingLeft, InpPullbackSwingRight);
         m_initialized = true;
        }

      CTimeframeData *h1 = md.H1();
      CTimeframeData *h4 = md.H4();

      double h4Slope = h4.EMA200SlopePoints(20);

      bool htfBull =
         h4.Close(1) > h4.EMA200(1) &&
         h4Slope > InpEMASlopeMinPoints;

      bool htfBear =
         h4.Close(1) < h4.EMA200(1) &&
         h4Slope < -InpEMASlopeMinPoints;

      if(!htfBull && !htfBear)
         return false;

      double ema20  = h1.EMA20(1);
      double ema50  = h1.EMA50(1);
      double open1  = h1.Open(1);
      double close1 = h1.Close(1);
      double low1   = h1.Low(1);
      double high1  = h1.High(1);

      SignalDirection dir = SIGNAL_NONE;

      if(htfBull)
        {
         bool touchedZone = (low1 <= ema20 && close1 >= ema50);
         bool confirmed   = (close1 > ema20) && (close1 > open1);

         if(touchedZone && confirmed)
            dir = SIGNAL_BUY;
        }
      else if(htfBear)
        {
         bool touchedZone = (high1 >= ema20 && close1 <= ema50);
         bool confirmed   = (close1 < ema20) && (close1 < open1);

         if(touchedZone && confirmed)
            dir = SIGNAL_SELL;
        }

      if(dir == SIGNAL_NONE)
         return false;

      double atr = h1.ATR(1);

      double score =
         QXE_Clamp(55.0 + MathAbs(h4Slope) / 5.0,
                   0.0,
                   100.0);

      string reason =
         "HTF trend pullback to EMA20/50 zone, confirmed";

      // Wick v2.1:
      // only promote a pullback when engine regime confirms the same trend.
      bool regimeAllowsWick =
         (dir == SIGNAL_BUY  && state.regime == REGIME_TREND_BULL) ||
         (dir == SIGNAL_SELL && state.regime == REGIME_TREND_BEAR);

      if(regimeAllowsWick && atr > 0.0)
        {
         double bbUpper;
         double bbMiddle;
         double bbLower;

         if(GetH1Bands(1, bbUpper, bbMiddle, bbLower))
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
      "[WICK-TELEMETRY] strategy=MomentumPullback dir=%s regime=%s quality=%.1f baseScore=%.1f boost=%.1f finalScore=%.1f crossed70=%s",
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
         " + WickV2Trend(q=%.1f,+%.1f)",
         wick.quality,
         wickBoost
      );
  }
           }
        }

      double entry = close1;

      int swingShift =
         (dir == SIGNAL_BUY)
         ? m_swings.FindLastSwingLow(
              h1,
              InpPullbackSwingRight + 1,
              20)
         : m_swings.FindLastSwingHigh(
              h1,
              InpPullbackSwingRight + 1,
              20);

      double stop;

      if(swingShift >= 0)
        {
         double swingPrice =
            (dir == SIGNAL_BUY)
            ? h1.Low(swingShift)
            : h1.High(swingShift);

         double buffer = atr * 0.25;

         stop =
            (dir == SIGNAL_BUY)
            ? swingPrice - buffer
            : swingPrice + buffer;
        }
      else
        {
         stop =
            (dir == SIGNAL_BUY)
            ? entry - atr * InpATRStopMultiplier
            : entry + atr * InpATRStopMultiplier;
        }

      double risk = MathAbs(entry - stop);

      double target =
         (dir == SIGNAL_BUY)
         ? entry + risk * InpTP2R
         : entry - risk * InpTP2R;

      outSignal.strategy   = STRAT_MOMENTUM_PULLBACK;
      outSignal.direction  = dir;
      outSignal.score      = score;
      outSignal.confidence = score / 100.0;
      outSignal.entry      = entry;
      outSignal.stop       = stop;
      outSignal.target     = target;
      outSignal.timestamp  = h1.Time(1);
      outSignal.regime     = state.regime;
      outSignal.reason     = reason;

      return true;
     }
  };

#endif // QXE_MOMENTUMPULLBACK_MQH
