//+------------------------------------------------------------------+
//| TrendFollowing.mqh                                               |
//| QUANT_XAUUSD_ENGINE - Trend Following strategy (spec section 9)  |
//+------------------------------------------------------------------+
#ifndef QXE_TRENDFOLLOWING_MQH
#define QXE_TRENDFOLLOWING_MQH

#include "IStrategy.mqh"
#include "../Core/Config.mqh"
#include "../Core/Utilities.mqh"

class CTrendFollowing : public IStrategy
  {
public:
   StrategyType      Type(void) override { return STRAT_TREND_FOLLOWING; }
   string            Name(void) override { return "TrendFollowing"; }

   bool              Evaluate(CMarketData *md, const MarketState &state, Signal &outSignal) override
     {
      outSignal.direction = SIGNAL_NONE;
      if(!EnableTrend)
         return false;

      CTimeframeData *h1 = md.H1();
      CTimeframeData *h4 = md.H4();

      double emaSlope = h1.EMA200SlopePoints(20);
      double close1 = h1.Close(1);
      double ema200 = h1.EMA200(1);
      double adx = h1.ADX(1);
      double adxPlus = h1.ADXPlus(1);
      double adxMinus = h1.ADXMinus(1);
      double h4Close = h4.Close(1);
      double h4Ema200 = h4.EMA200(1);

      bool bullConditions = (close1 > ema200) && (emaSlope > InpEMASlopeMinPoints) &&
                             (adx >= InpADXTrendThreshold) && (adxPlus > adxMinus) &&
                             (h4Close > h4Ema200);

      bool bearConditions = (close1 < ema200) && (emaSlope < -InpEMASlopeMinPoints) &&
                             (adx >= InpADXTrendThreshold) && (adxMinus > adxPlus) &&
                             (h4Close < h4Ema200);

      if(!bullConditions && !bearConditions)
         return false;

      SignalDirection dir = bullConditions ? SIGNAL_BUY : SIGNAL_SELL;

      double score = 50.0;
      score += MathMin(20.0, MathAbs(emaSlope) / 5.0);
      score += MathMin(20.0, (adx - InpADXTrendThreshold));
      score = QXE_Clamp(score, 0.0, 100.0);

      double atr = h1.ATR(1);
      double entry = close1;
      double stop = (dir == SIGNAL_BUY) ? entry - atr * InpATRStopMultiplier
                                         : entry + atr * InpATRStopMultiplier;
      double risk = MathAbs(entry - stop);
      double target = (dir == SIGNAL_BUY) ? entry + risk * InpTP2R : entry - risk * InpTP2R;

      outSignal.strategy = STRAT_TREND_FOLLOWING;
      outSignal.direction = dir;
      outSignal.score = score;
      outSignal.confidence = score / 100.0;
      outSignal.entry = entry;
      outSignal.stop = stop;
      outSignal.target = target;
      outSignal.timestamp = h1.Time(1);
      outSignal.regime = state.regime;
      outSignal.reason = StringFormat("EMA200 trend + ADX %.1f + H4 alignment", adx);
      return true;
     }
  };

#endif // QXE_TRENDFOLLOWING_MQH
