//+------------------------------------------------------------------+
//| MarketStructureStrategy.mqh                                      |
//| QUANT_XAUUSD_ENGINE - Market Structure strategy (spec section 14)|
//| Trades confirmed BOS in the direction of the prevailing regime;   |
//| a CHoCH against the regime is treated as an early-warning only    |
//| (no entry) to avoid fighting a still-dominant trend.               |
//+------------------------------------------------------------------+
#ifndef QXE_MARKETSTRUCTURESTRATEGY_MQH
#define QXE_MARKETSTRUCTURESTRATEGY_MQH

#include "IStrategy.mqh"
#include "../Structure/MarketStructure.mqh"
#include "../Core/Config.mqh"
#include "../Core/Utilities.mqh"

class CMarketStructureStrategy : public IStrategy
  {
private:
   CMarketStructure  m_structure;
   bool              m_initialized;

public:
                     CMarketStructureStrategy(void) : m_initialized(false) {}

   StrategyType      Type(void) override { return STRAT_MARKET_STRUCTURE; }
   string            Name(void) override { return "MarketStructure"; }

   bool              Evaluate(CMarketData *md, const MarketState &state, Signal &outSignal) override
     {
      outSignal.direction = SIGNAL_NONE;
      if(!EnableStructure)
         return false;

      if(!m_initialized)
        {
         m_structure.Init();
         m_initialized = true;
        }

      CTimeframeData *h1 = md.H1();
      m_structure.Update(h1);

      StructureEventType ev = m_structure.LastEvent();
      SignalDirection dir = SIGNAL_NONE;

      // Only trade confirmed BOS that agrees with the current regime -
      // CHoCH alone is a warning, not an entry trigger, in this module.
      if(ev == STRUCT_BOS_BULL && state.regime == REGIME_TREND_BULL)
         dir = SIGNAL_BUY;
      else if(ev == STRUCT_BOS_BEAR && state.regime == REGIME_TREND_BEAR)
         dir = SIGNAL_SELL;

      if(dir == SIGNAL_NONE)
         return false;

      double atr = h1.ATR(1);
      double entry = h1.Close(1);
      double swingRef = (dir == SIGNAL_BUY) ? m_structure.LastSwingLow() : m_structure.LastSwingHigh();
      double buffer = atr * 0.25;
      double stop = (swingRef > 0.0) ?
         ((dir == SIGNAL_BUY) ? swingRef - buffer : swingRef + buffer) :
         ((dir == SIGNAL_BUY) ? entry - atr * InpATRStopMultiplier : entry + atr * InpATRStopMultiplier);

      double risk = MathAbs(entry - stop);
      double target = (dir == SIGNAL_BUY) ? entry + risk * InpTP2R : entry - risk * InpTP2R;

      outSignal.strategy = STRAT_MARKET_STRUCTURE;
      outSignal.direction = dir;
      outSignal.score = 65.0;
      outSignal.confidence = 0.65;
      outSignal.entry = entry;
      outSignal.stop = stop;
      outSignal.target = target;
      outSignal.timestamp = h1.Time(1);
      outSignal.regime = state.regime;
      outSignal.reason = "Confirmed BOS aligned with regime";
      return true;
     }
  };

#endif // QXE_MARKETSTRUCTURESTRATEGY_MQH
