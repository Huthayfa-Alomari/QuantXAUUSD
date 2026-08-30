//+------------------------------------------------------------------+
//| PositionManager.mqh                                              |
//| QUANT_XAUUSD_ENGINE - Position lifecycle management (spec 27)    |
//|                                                                   |
//| REPAIR PASS rewrite - this file now owns the full logical-trade   |
//| lifecycle, not just partial/BE/trailing mechanics:                |
//|                                                                   |
//| 1. `PositionContext` (per repair spec) replaces the old thin      |
//|    ManagedPositionState - it carries strategy attribution         |
//|    (primary + full contributing ensemble), entry snapshot         |
//|    (ATR/ADX/spread/score), and running MAE/MFE.                   |
//| 2. MAE/MFE are now tracked for real, every tick, in both price    |
//|    units and R multiples, and persist through partial closes.     |
//| 3. Partial-close volume is floor-normalized and NEVER rounds up;  |
//|    if a requested partial would leave an unclosable remainder     |
//|    below the broker minimum, the manager closes the FULL          |
//|    remaining position instead of stranding sub-minimum dust.      |
//| 4. `ProcessDeal()` is the single place that turns 1..N broker     |
//|    deals (entry + partials + final exit) into exactly ONE         |
//|    `TradeResult` - partial deals update the context only; only    |
//|    the deal that empties the position produces a TradeResult.     |
//| 5. Exit reason is inferred from which stored level (original SL,  |
//|    current/trailed SL, TP1, TP2) the closing price actually       |
//|    matches, instead of always defaulting to EXIT_MANUAL.          |
//+------------------------------------------------------------------+
#ifndef QXE_POSITIONMANAGER_MQH
#define QXE_POSITIONMANAGER_MQH

#include "../Execution/TradeExecutor.mqh"
#include "../Risk/RiskEngine.mqh"
#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Utilities.mqh"

struct PositionContext
  {
   ulong             positionIdentifier;   // POSITION_TICKET / POSITION_IDENTIFIER - stable across partials

   datetime          openTime;

   SignalDirection   direction;
   RegimeType        regime;

   StrategyType      primaryStrategy;
   string            contributingStrategies;
   string            contributorEligibility;

   double            entryPrice;
   double            initialStop;
   double            currentStopPrice;     // updated by break-even / trailing
   double            takeProfit1;
   double            takeProfit2;
   double            initialRiskDistance;  // |entry - initialStop| in price units
   double            initialRiskMoney;
   double            initialVolume;

   double            entryATR;
   double            entryADX;
   double            entrySpread;
   double            entryScore;

   // Architecture v2 telemetry additions.
   MarketState       entryState;           // full point-in-time snapshot at entry (incl. meta-regime)
   double            rawScore;
   double            interactionModifier;
   int               contributorCount;
   string            interactionReason;

   // Risk-integrity audit trail (mirrors RiskParameters at open time).
   double            equityAtEntry;
   double            requestedRiskPercent;
   double            lossPerLotBrokerAtEntry;    // OrderCalcProfit()-based, the value actually used for sizing
   double            lossPerLotTickModelAtEntry; // old tick_size/tick_value formula's result - diagnostic only

   double            realizedProfit;       // accumulated profit from partial closes so far
   double            closedVolume;

   double            highestPriceSeen;
   double            lowestPriceSeen;

   double            mae;                  // price units, adverse
   double            mfe;                  // price units, favorable

   bool              tp1Taken;
   bool              tp2Taken;
   bool              breakEvenApplied;

   ExitReason        pendingExitReason;    // set BEFORE a manager-initiated close (e.g. opposite signal); EXIT_NONE = infer from price

   bool              active;
  };

class CPositionManager
  {
private:
   CTradeExecutor    *m_executor;
   CRiskEngine       *m_risk;
   PositionContext   m_contexts[];

public:
   void              Init(CTradeExecutor *executor, CRiskEngine *risk)
     {
      m_executor = executor;
      m_risk = risk;
      ArrayResize(m_contexts, 0);
     }

   // Call immediately after a position is successfully opened. This is
   // the ONLY place a new trade is counted as "opened" (repair spec:
   // daily trade counter must count opens, not exit deals).
   void              RegisterOpen(ulong ticket, const TradeSetup &setup, const RiskParameters &risk,
                                   double entryATR, double entryADX, double entrySpread,
                                   const MarketState &entryState)
     {
      int n = ArraySize(m_contexts);
      ArrayResize(m_contexts, n + 1);

      m_contexts[n].positionIdentifier = ticket;
      m_contexts[n].openTime = TimeCurrent();
      m_contexts[n].direction = setup.direction;
      m_contexts[n].regime = setup.regime;
      m_contexts[n].primaryStrategy = setup.primaryStrategy;
      m_contexts[n].contributingStrategies = setup.contributingStrategies;
      m_contexts[n].contributorEligibility = setup.contributorEligibility;
      m_contexts[n].entryPrice = setup.entry;
      m_contexts[n].initialStop = setup.stopLoss;
      m_contexts[n].currentStopPrice = setup.stopLoss;
      m_contexts[n].takeProfit1 = setup.takeProfit1;
      m_contexts[n].takeProfit2 = setup.takeProfit2;
      m_contexts[n].initialRiskDistance = MathAbs(setup.entry - setup.stopLoss);
      m_contexts[n].initialRiskMoney = risk.moneyAtRisk;
      m_contexts[n].initialVolume = risk.lotSize;
      m_contexts[n].entryATR = entryATR;
      m_contexts[n].entryADX = entryADX;
      m_contexts[n].entrySpread = entrySpread;
      m_contexts[n].entryScore = setup.compositeScore;
      m_contexts[n].entryState = entryState;
      m_contexts[n].rawScore = setup.rawScore;
      m_contexts[n].interactionModifier = setup.interactionModifier;
      m_contexts[n].contributorCount = setup.contributorCount;
      m_contexts[n].interactionReason = setup.interactionReason;
      m_contexts[n].equityAtEntry = risk.equity;
      m_contexts[n].requestedRiskPercent = risk.riskPercent;
      m_contexts[n].lossPerLotBrokerAtEntry = risk.lossPerLotBroker;
      m_contexts[n].lossPerLotTickModelAtEntry = risk.lossPerLotTickModel;
      m_contexts[n].realizedProfit = 0.0;
      m_contexts[n].closedVolume = 0.0;
      m_contexts[n].highestPriceSeen = setup.entry;
      m_contexts[n].lowestPriceSeen = setup.entry;
      m_contexts[n].mae = 0.0;
      m_contexts[n].mfe = 0.0;
      m_contexts[n].tp1Taken = false;
      m_contexts[n].tp2Taken = false;
      m_contexts[n].breakEvenApplied = false;
      m_contexts[n].pendingExitReason = EXIT_NONE;
      m_contexts[n].active = true;

      m_risk.RegisterTradeOpened();
     }

   // Marks the context so the NEXT close is attributed to a specific
   // reason (e.g. opposite-signal reversal) instead of being inferred
   // from price. Call this BEFORE issuing the close.
   void              TagPendingExit(ulong ticket, ExitReason reason)
     {
      int idx = FindByTicket(ticket);
      if(idx >= 0)
         m_contexts[idx].pendingExitReason = reason;
     }

   // Call every tick for every open position belonging to this EA.
   // Updates MAE/MFE unconditionally, then runs partial-close /
   // break-even / trailing logic.
   void              ManageAll(string symbol, double atrH1)
     {
      for(int i = ArraySize(m_contexts) - 1; i >= 0; i--)
        {
         if(!m_contexts[i].active)
            continue;
         if(!PositionSelectByTicket(m_contexts[i].positionIdentifier))
            continue; // closed elsewhere - finalized via ProcessDeal(), not here
         UpdateExcursion(m_contexts[i]);
         ManageOne(m_contexts[i], symbol, atrH1);
        }
     }

   // Called from OnTradeTransaction for every DEAL_ENTRY_OUT/OUT_BY deal
   // belonging to this EA. Accumulates partials into the context; only
   // when the position is confirmed fully closed does this produce a
   // finalized TradeResult (repair spec: "one logical trade -> one
   // TradeResult"). Returns true and fills `outResult` on final close.
   bool              ProcessDeal(ulong positionTicket, double dealVolume, double dealProfit,
                                  double dealPrice, datetime dealTime, bool positionStillOpen,
                                  RegimeType regimeAtExit, TradeResult &outResult)
     {
      int idx = FindByTicket(positionTicket);
      if(idx < 0)
         return false; // not one of our tracked contexts

      m_contexts[idx].realizedProfit += dealProfit;
      m_contexts[idx].closedVolume += dealVolume;

      if(positionStillOpen)
         return false; // partial - context updated, no TradeResult yet

      // Final deal - the position is now fully closed.
      outResult = BuildFinalResult(m_contexts[idx], dealPrice, dealTime, regimeAtExit);
      m_risk.RegisterTradeClosed(outResult.profit);
      RemoveContext(idx);
      return true;
     }

   int               Count(void) const { return ArraySize(m_contexts); }

private:
   int               FindByTicket(ulong ticket) const
     {
      for(int i = 0; i < ArraySize(m_contexts); i++)
         if(m_contexts[i].positionIdentifier == ticket && m_contexts[i].active)
            return i;
      return -1;
     }

   void              UpdateExcursion(PositionContext &ctx)
     {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double currentPrice = (ctx.direction == SIGNAL_BUY) ? bid : ask;

      if(currentPrice > ctx.highestPriceSeen)
         ctx.highestPriceSeen = currentPrice;
      if(currentPrice < ctx.lowestPriceSeen)
         ctx.lowestPriceSeen = currentPrice;

      double adverse, favorable;
      if(ctx.direction == SIGNAL_BUY)
        {
         adverse = ctx.entryPrice - ctx.lowestPriceSeen;
         favorable = ctx.highestPriceSeen - ctx.entryPrice;
        }
      else
        {
         adverse = ctx.highestPriceSeen - ctx.entryPrice;
         favorable = ctx.entryPrice - ctx.lowestPriceSeen;
        }

      ctx.mae = MathMax(ctx.mae, adverse);
      ctx.mfe = MathMax(ctx.mfe, favorable);
     }

   void              ManageOne(PositionContext &ctx, string symbol, double atrH1)
     {
      double currentPrice = (ctx.direction == SIGNAL_BUY) ? SymbolInfoDouble(symbol, SYMBOL_BID)
                                                            : SymbolInfoDouble(symbol, SYMBOL_ASK);
      double profitDistance = (ctx.direction == SIGNAL_BUY) ? (currentPrice - ctx.entryPrice)
                                                              : (ctx.entryPrice - currentPrice);
      if(ctx.initialRiskDistance <= QXE_EPS)
         return;
      double rMultiple = profitDistance / ctx.initialRiskDistance;

      double positionVolume = PositionGetDouble(POSITION_VOLUME);
      double volMin = QXE_VolumeMin(symbol);

      // --- Partial close at TP1 / TP2 (volume-safe: never round a
      //     partial UP, and never strand a sub-minimum remainder) ---
      if(!ctx.tp1Taken && rMultiple >= InpTP1R)
        {
         double requested = positionVolume * (InpTP1Pct / 100.0);
         ExecuteSafePartial(ctx, requested, positionVolume, volMin, symbol);
         ctx.tp1Taken = true; // attempted once regardless of outcome - avoids retry spam
        }
      else if(ctx.tp1Taken && !ctx.tp2Taken && rMultiple >= InpTP2R)
        {
         double requested = positionVolume * (InpTP2Pct / (100.0 - InpTP1Pct));
         ExecuteSafePartial(ctx, requested, positionVolume, volMin, symbol);
         ctx.tp2Taken = true;
        }

      // --- Break-even ---
      if(!ctx.breakEvenApplied && rMultiple >= InpBreakEvenTriggerR)
        {
         double newStop = ctx.entryPrice;
         double currentTp = PositionGetDouble(POSITION_TP);
         if(m_executor.ModifyStops(ctx.positionIdentifier, newStop, currentTp))
           {
            ctx.breakEvenApplied = true;
            ctx.currentStopPrice = newStop;
           }
        }

      // --- Trailing stop (ATR-based, chandelier-style) ---
      if(rMultiple >= InpMinProfitRForTrailing && atrH1 > QXE_EPS)
        {
         double currentStop = PositionGetDouble(POSITION_SL);
         double trailDistance = atrH1 * InpTrailingATRMultiplier;
         double candidateStop = (ctx.direction == SIGNAL_BUY) ? currentPrice - trailDistance
                                                                : currentPrice + trailDistance;

         bool improves = (ctx.direction == SIGNAL_BUY) ? (candidateStop > currentStop)
                                                         : (candidateStop < currentStop || currentStop <= 0.0);
         if(improves)
           {
            double currentTp = PositionGetDouble(POSITION_TP);
            if(m_executor.ModifyStops(ctx.positionIdentifier, candidateStop, currentTp))
               ctx.currentStopPrice = candidateStop;
           }
        }
     }

   // Floors the requested volume to the broker step; if that floored
   // amount is below the minimum, skips the partial entirely; if the
   // REMAINDER after this partial would fall below the minimum, closes
   // the full remaining position now instead of stranding unclosable
   // dust (repair spec: "PARTIAL CLOSE VOLUME").
   void              ExecuteSafePartial(PositionContext &ctx, double requested, double positionVolume,
                                         double volMin, string symbol)
     {
      double floored = QXE_NormalizeVolume(symbol, requested);
      if(floored <= 0.0)
        {
         g_Logger.Debug(StringFormat("Partial close skipped (ticket=%d): requested %.4f floors below broker minimum %.4f",
                         ctx.positionIdentifier, requested, volMin));
         return;
        }

      double remainder = positionVolume - floored;
      if(remainder > QXE_EPS && remainder < volMin)
        {
         // Closing `floored` would strand a sub-minimum remainder -
         // close the FULL position now instead (documented remainder-
         // safe rule, never leaves an invalid dust position).
         g_Logger.Info(StringFormat("Partial close (ticket=%d) would strand %.4f below min %.4f - closing full remainder instead",
                        ctx.positionIdentifier, remainder, volMin));
         m_executor.CloseFull(ctx.positionIdentifier);
         return;
        }

      m_executor.ClosePartial(ctx.positionIdentifier, floored);
     }

   TradeResult       BuildFinalResult(const PositionContext &ctx, double exitPrice, datetime exitTime, RegimeType regimeAtExit)
     {
      TradeResult tr;
      tr.ticket = ctx.positionIdentifier;
      tr.openTime = ctx.openTime;
      tr.closeTime = exitTime;
      tr.strategy = ctx.primaryStrategy;
      tr.contributingStrategies = ctx.contributingStrategies;
      tr.contributorEligibility = ctx.contributorEligibility;
      tr.regime = ctx.regime;
      tr.direction = ctx.direction;
      tr.entry = ctx.entryPrice;
      tr.stopLoss = ctx.initialStop;
      tr.takeProfit = ctx.takeProfit2;
      tr.lot = ctx.initialVolume;
      tr.riskMoney = ctx.initialRiskMoney;
      tr.score = ctx.entryScore;
      tr.atrAtEntry = ctx.entryATR;
      tr.adxAtEntry = ctx.entryADX;
      tr.spreadAtEntry = ctx.entrySpread;
      tr.session = QXE_CurrentSession();
      tr.equityAtEntry = ctx.equityAtEntry;
      tr.requestedRiskPercent = ctx.requestedRiskPercent;
      tr.slDistancePriceAtEntry = ctx.initialRiskDistance;
      tr.lossPerLotBrokerAtEntry = ctx.lossPerLotBrokerAtEntry;
      tr.lossPerLotTickModelAtEntry = ctx.lossPerLotTickModelAtEntry;
      tr.expectedLossAtSL = ctx.initialRiskMoney;
      tr.exitPrice = exitPrice;
      tr.profit = ctx.realizedProfit;

      tr.rMultiple = (ctx.initialRiskMoney > QXE_EPS) ? ctx.realizedProfit / ctx.initialRiskMoney : 0.0;

      tr.mae = ctx.mae;
      tr.mfe = ctx.mfe;
      tr.maeR = (ctx.initialRiskDistance > QXE_EPS) ? -(ctx.mae / ctx.initialRiskDistance) : 0.0;
      tr.mfeR = (ctx.initialRiskDistance > QXE_EPS) ? (ctx.mfe / ctx.initialRiskDistance) : 0.0;
      tr.holdingSeconds = (int)(exitTime - ctx.openTime);

      tr.exitReason = InferExitReason(ctx, exitPrice);

      // Architecture v2 telemetry.
      tr.entryState = ctx.entryState;
      tr.regimeAtExit = regimeAtExit;
      tr.rawScore = ctx.rawScore;
      tr.interactionModifier = ctx.interactionModifier;
      tr.contributorCount = ctx.contributorCount;
      tr.interactionReason = ctx.interactionReason;
      tr.eligibilityDecision = ELIGIBILITY_ALLOW; // the primary strategy is always ALLOW-tier by construction (see ScoreEngine)
      tr.eligibilityReason = "primary strategy passed both the base regime gate and the meta-regime eligibility gate";

      // [RISK VIOLATION] check: a position that exits via its ORIGINAL
      // stop loss (never trailed, never break-evened) should realize
      // close to -1R. A large deviation means the actual loss did not
      // match what the sizing math promised - flag it loudly rather
      // than let it quietly pass through statistics.
      if(tr.exitReason == EXIT_STOP_LOSS && ctx.initialRiskMoney > QXE_EPS)
        {
         double expectedR = -1.0;
         double deviation = MathAbs(tr.rMultiple - expectedR);
         if(deviation > 1.5) // more than 1.5R away from the expected -1R
           {
            g_Logger.Error(StringFormat(
               "[RISK VIOLATION] ticket=%d equityAtEntry=%.2f reqRisk%%=%.4f expectedLossAtSL=%.2f actualPnL=%.2f actualR=%.2fR (expected ~-1R) lot=%.4f slDistPrice=%.5f lossPerLotBroker=%.5f lossPerLotTickModel=%.5f",
               tr.ticket, ctx.equityAtEntry, ctx.requestedRiskPercent, ctx.initialRiskMoney, tr.profit, tr.rMultiple,
               ctx.initialVolume, ctx.initialRiskDistance, ctx.lossPerLotBrokerAtEntry, ctx.lossPerLotTickModelAtEntry));
           }
        }

      return tr;
     }

   // Infers WHY a position closed by comparing the final exit price to
   // the levels the manager itself set, instead of always defaulting to
   // EXIT_MANUAL (repair spec: "EXIT REASON").
   ExitReason        InferExitReason(const PositionContext &ctx, double exitPrice) const
     {
      if(ctx.pendingExitReason != EXIT_NONE)
         return ctx.pendingExitReason; // explicitly tagged by the caller (e.g. opposite signal)

      double tolerance = MathMax(ctx.initialRiskDistance * 0.05, QXE_EPS * 10.0);

      if(ctx.breakEvenApplied && MathAbs(exitPrice - ctx.entryPrice) <= tolerance)
         return EXIT_BREAK_EVEN;

      if(MathAbs(exitPrice - ctx.currentStopPrice) <= tolerance && ctx.currentStopPrice != ctx.initialStop)
         return EXIT_TRAILING_STOP;

      if(MathAbs(exitPrice - ctx.initialStop) <= tolerance)
         return EXIT_STOP_LOSS;

      if(MathAbs(exitPrice - ctx.takeProfit2) <= tolerance)
         return ctx.tp2Taken ? EXIT_RUNNER : EXIT_TAKE_PROFIT_2;

      if(MathAbs(exitPrice - ctx.takeProfit1) <= tolerance)
         return EXIT_TAKE_PROFIT_1;

      return EXIT_MANUAL; // genuinely could not match any known level
     }

   void              RemoveContext(int index)
     {
      m_contexts[index].active = false;
      int n = ArraySize(m_contexts);
      for(int i = index; i < n - 1; i++)
         m_contexts[i] = m_contexts[i + 1];
      ArrayResize(m_contexts, n - 1);
     }
  };

#endif // QXE_POSITIONMANAGER_MQH
