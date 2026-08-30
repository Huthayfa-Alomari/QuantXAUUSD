//+------------------------------------------------------------------+
//| LiquiditySweepStrategy.mqh                                       |
//| QUANT_XAUUSD_ENGINE - Liquidity Sweep strategy (spec section 15) |
//+------------------------------------------------------------------+
#ifndef QXE_LIQUIDITYSWEEPSTRATEGY_MQH
#define QXE_LIQUIDITYSWEEPSTRATEGY_MQH

#include "IStrategy.mqh"
#include "../Liquidity/LiquidityLevels.mqh"
#include "../Liquidity/LiquiditySweep.mqh"
#include "../Entry/DisplacementDetector.mqh"
#include "../Core/Config.mqh"
#include "../Core/Utilities.mqh"

class CLiquiditySweepStrategy : public IStrategy
  {
private:
   CLiquidityLevels  m_levels;
   CLiquiditySweep   m_sweepDetector;
   CDisplacementDetector m_disp;
   datetime          m_lastRebuildBar;
   bool              m_initialized;

public:
                     CLiquiditySweepStrategy(void) : m_lastRebuildBar(0), m_initialized(false) {}

   StrategyType      Type(void) override { return STRAT_LIQUIDITY_SWEEP; }
   string            Name(void) override { return "LiquiditySweep"; }

   bool              Evaluate(CMarketData *md, const MarketState &state, Signal &outSignal) override
     {
      outSignal.direction = SIGNAL_NONE;
      if(!EnableLiquidity)
         return false;

      if(!m_initialized)
        {
         m_levels.Init(_Symbol);
         m_initialized = true;
        }

      CTimeframeData *d1 = md.D1();
      CTimeframeData *h1 = md.H1();

      datetime h1BarTime = h1.Time(1);
      if(h1BarTime != m_lastRebuildBar)
        {
         m_levels.Update(d1, h1);
         m_lastRebuildBar = h1BarTime;
        }

      SweepResult sweep = m_sweepDetector.Detect(h1, GetPointer(m_levels), GetPointer(m_disp));
      if(!sweep.found)
         return false;

      double atr = h1.ATR(1);
      double entry = h1.Close(1);
      double stop = (sweep.direction == SIGNAL_BUY) ? entry - atr * InpATRStopMultiplier
                                                      : entry + atr * InpATRStopMultiplier;
      double risk = MathAbs(entry - stop);
      double target = (sweep.direction == SIGNAL_BUY) ? entry + risk * InpTP2R : entry - risk * InpTP2R;

      double score = 60.0;
      if(sweep.displacementConfirmed)
         score += 15.0;

      outSignal.strategy = STRAT_LIQUIDITY_SWEEP;
      outSignal.direction = sweep.direction;
      outSignal.score = QXE_Clamp(score, 0.0, 100.0);
      outSignal.confidence = score / 100.0;
      outSignal.entry = entry;
      outSignal.stop = stop;
      outSignal.target = target;
      outSignal.timestamp = h1.Time(1);
      outSignal.regime = state.regime;
      outSignal.reason = StringFormat("Liquidity sweep of level type=%d, displacement=%s",
                          (int)sweep.levelType, sweep.displacementConfirmed ? "yes" : "no");
      return true;
     }
  };

#endif // QXE_LIQUIDITYSWEEPSTRATEGY_MQH
