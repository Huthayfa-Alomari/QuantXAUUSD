//+------------------------------------------------------------------+
//| IStrategy.mqh                                                    |
//| QUANT_XAUUSD_ENGINE - Strategy interface                         |
//|                                                                   |
//| Every strategy hypothesis (spec section 54: treat each as a      |
//| hypothesis, never assumed to "work") implements this contract.   |
//| A strategy only ever PRODUCES a Signal - it never touches the    |
//| trade ticket directly.                                           |
//+------------------------------------------------------------------+
#ifndef QXE_ISTRATEGY_MQH
#define QXE_ISTRATEGY_MQH

#include "../Core/Types.mqh"
#include "../Data/MarketData.mqh"

class IStrategy
  {
public:
   // Evaluates current market state and produces a signal. If no setup
   // qualifies, `outSignal.direction` must be SIGNAL_NONE.
   virtual bool      Evaluate(CMarketData *md, const MarketState &state, Signal &outSignal) = 0;
   virtual StrategyType Type(void) = 0;
   virtual string    Name(void) = 0;

   // The timeframe whose bar-close should trigger this strategy's
   // Evaluate() (repair spec: "MULTI-TIMEFRAME EVENT SCHEDULER" - each
   // strategy runs on its own natural cadence, not lumped into one
   // H1-only gate). Defaults to H1; override for faster strategies
   // (e.g. ORB overrides to PERIOD_M5).
   virtual ENUM_TIMEFRAMES Cadence(void) { return PERIOD_H1; }

   virtual           ~IStrategy(void) {}
  };

#endif // QXE_ISTRATEGY_MQH
