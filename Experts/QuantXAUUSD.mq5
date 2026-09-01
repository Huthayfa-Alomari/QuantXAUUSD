//+------------------------------------------------------------------+
//| QuantXAUUSD.mq5                                                  |
//| QUANT_XAUUSD_ENGINE - Main Expert Advisor                        |
//| Stable cache cleanup build                                      |
//+------------------------------------------------------------------+
#property copyright "QUANT_XAUUSD_ENGINE"
#property version   "1.12"
#property strict

#include <QuantXAUUSD/Core/Types.mqh>
#include <QuantXAUUSD/Core/Constants.mqh>
#include <QuantXAUUSD/Core/Config.mqh>
#include <QuantXAUUSD/Core/Logger.mqh>
#include <QuantXAUUSD/Core/ErrorHandler.mqh>
#include <QuantXAUUSD/Core/Utilities.mqh>

#include <QuantXAUUSD/Data/MarketData.mqh>
#include <QuantXAUUSD/Data/TimeframeAnalytics.mqh>

#include <QuantXAUUSD/Regime/RegimeEngine.mqh>
#include <QuantXAUUSD/Regime/MetaRegimeClassifier.mqh>

#include <QuantXAUUSD/Structure/SwingDetector.mqh>
#include <QuantXAUUSD/Structure/MarketStructure.mqh>

#include <QuantXAUUSD/Liquidity/LiquidityLevels.mqh>
#include <QuantXAUUSD/Liquidity/LiquiditySweep.mqh>

#include <QuantXAUUSD/Entry/FVGDetector.mqh>
#include <QuantXAUUSD/Entry/DisplacementDetector.mqh>
#include <QuantXAUUSD/Entry/EntryEngine.mqh>

#include <QuantXAUUSD/Strategies/IStrategy.mqh>
#include <QuantXAUUSD/Strategies/TrendFollowing.mqh>
#include <QuantXAUUSD/Strategies/TimeSeriesMomentum.mqh>
#include <QuantXAUUSD/Strategies/DonchianBreakout.mqh>
#include <QuantXAUUSD/Strategies/VolatilityBreakout.mqh>
#include <QuantXAUUSD/Strategies/MomentumPullback.mqh>
#include <QuantXAUUSD/Strategies/MeanReversion.mqh>
#include <QuantXAUUSD/Strategies/BollingerZScore.mqh>
#include <QuantXAUUSD/Strategies/VWAPStrategy.mqh>
#include <QuantXAUUSD/Strategies/OpeningRangeBreakout.mqh>
#include <QuantXAUUSD/Strategies/MarketStructureStrategy.mqh>
#include <QuantXAUUSD/Strategies/LiquiditySweepStrategy.mqh>

#include <QuantXAUUSD/Scoring/ScoreEngine.mqh>
#include <QuantXAUUSD/Scoring/StrategyEligibility.mqh>
#include <QuantXAUUSD/Scoring/StrategyInteractionMatrix.mqh>

#include <QuantXAUUSD/Risk/RiskEngine.mqh>
#include <QuantXAUUSD/Execution/SpreadFilter.mqh>
#include <QuantXAUUSD/Execution/TradeExecutor.mqh>
#include <QuantXAUUSD/Management/PositionManager.mqh>
#include <QuantXAUUSD/Research/Journal.mqh>
#include <QuantXAUUSD/Research/TradeTelemetry.mqh>
#include <QuantXAUUSD/Research/TradeStatistics.mqh>

//====================================================================
// GLOBAL ENGINE OBJECTS
//====================================================================
CMarketData                  g_MarketData;
CRegimeEngine                g_RegimeEngine;
CMetaRegimeClassifier        g_MetaClassifier;
CStrategyEligibilityEngine   g_EligibilityEngine;
CStrategyInteractionMatrix   g_InteractionMatrix;
CMarketStructure             g_StateStructure;
CScoreEngine                 g_ScoreEngine;
CRiskEngine                  g_RiskEngine;
CSpreadFilter                g_SpreadFilter;
CTradeExecutor               g_Executor;
CPositionManager             g_PositionManager;
CJournal                     g_Journal;
CTradeTelemetry              g_Telemetry;
CTradeStatistics             g_Statistics;

IStrategy *g_Strategies[STRAT_COUNT];

datetime g_lastBarD1  = 0;
datetime g_lastBarH4  = 0;
datetime g_lastBarH1  = 0;
datetime g_lastBarM15 = 0;
datetime g_lastBarM5  = 0;

Signal              g_lastSignal[STRAT_COUNT];
datetime            g_lastSignalBarTime[STRAT_COUNT];
EligibilityDecision g_lastEligibility[STRAT_COUNT];

double     g_startingEquity   = 0.0;
datetime   g_lastHealthLogDay = 0;
RegimeType g_lastKnownRegime  = REGIME_NO_TRADE;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_Logger.Init(DebugMode, QXE_SYSTEM_NAME);
   g_Logger.Info(StringFormat("Initializing %s v%s on %s", QXE_SYSTEM_NAME, QXE_VERSION, _Symbol));

   if(!ValidateDrawdownConfig())
      return INIT_FAILED;

   if(!g_MarketData.Init(_Symbol))
     {
      g_Logger.Error("MarketData initialization failed - aborting.");
      return INIT_FAILED;
     }

   g_StateStructure.Init();
   g_InteractionMatrix.Init();

   g_startingEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_RiskEngine.Init(g_startingEquity, _Symbol, InpMagicNumber);

   g_Logger.Info(StringFormat(
      "[SYMBOL-SPEC] %s digits=%d point=%.8f tickSize=%.8f tickValue=%.8f contractSize=%.2f volMin=%.4f volMax=%.4f volStep=%.4f stopsLevel=%.0f",
      _Symbol,
      (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS),
      SymbolInfoDouble(_Symbol, SYMBOL_POINT),
      SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE),
      SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE),
      SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE),
      SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN),
      SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX),
      SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP),
      (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL)));

   g_Executor.Init(_Symbol, InpMagicNumber);
   g_PositionManager.Init(GetPointer(g_Executor), GetPointer(g_RiskEngine));
   g_PositionManager.RecoverOpenPositions(_Symbol, InpMagicNumber);
   g_Statistics.Init();

   string tradeFile     = "QXE_Trades_" + _Symbol + ".csv";
   string researchFile  = "QXE_Research_" + _Symbol + ".csv";
   string telemetryFile = "QXE_TradeTelemetry_" + _Symbol + ".csv";

   if(!g_Journal.Init(tradeFile, researchFile))
      g_Logger.Warn("Journal failed to initialize CSV files - continuing without file logging.");

   if(!g_Telemetry.Init(telemetryFile))
      g_Logger.Warn("Telemetry failed to initialize CSV file - continuing without it.");

   g_Strategies[STRAT_TREND_FOLLOWING]        = new CTrendFollowing();
   g_Strategies[STRAT_TIME_SERIES_MOMENTUM]   = new CTimeSeriesMomentum();
   g_Strategies[STRAT_DONCHIAN_BREAKOUT]      = new CDonchianBreakout();
   g_Strategies[STRAT_VOLATILITY_BREAKOUT]    = new CVolatilityBreakout();
   g_Strategies[STRAT_MOMENTUM_PULLBACK]      = new CMomentumPullback();
   g_Strategies[STRAT_MARKET_STRUCTURE]       = new CMarketStructureStrategy();
   g_Strategies[STRAT_LIQUIDITY_SWEEP]        = new CLiquiditySweepStrategy();
   g_Strategies[STRAT_MEAN_REVERSION]         = new CMeanReversion();
   g_Strategies[STRAT_BOLLINGER_ZSCORE]       = new CBollingerZScore();
   g_Strategies[STRAT_VWAP]                   = new CVWAPStrategy();
   g_Strategies[STRAT_OPENING_RANGE_BREAKOUT] = new COpeningRangeBreakout();

   for(int i = 0; i < STRAT_COUNT; i++)
     {
      g_lastSignal[i].direction = SIGNAL_NONE;
      g_lastSignalBarTime[i]    = 0;
      g_lastEligibility[i]      = ELIGIBILITY_ALLOW;
     }

   if(InpResearchMode)
      g_Logger.Info("RESEARCH MODE ENABLED. NOT a full virtual execution simulator.");

   g_Logger.Info("Initialization complete.");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   for(int i = 0; i < STRAT_COUNT; i++)
     {
      if(CheckPointer(g_Strategies[i]) == POINTER_DYNAMIC)
         delete g_Strategies[i];
     }

   g_Statistics.PrintAttributionReport();
   g_Statistics.PrintRegimeReport();
   g_Statistics.PrintStrategyByRegimeReport();
   g_Statistics.PrintInteractionAttributionReport();

   g_Journal.Deinit();
   g_Telemetry.Deinit();

   g_Logger.Info(StringFormat("%s deinitialized. reason=%d", QXE_SYSTEM_NAME, reason));
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_RiskEngine.OnTick(equity);

   if(!g_MarketData.RefreshAll())
      return;

   double atrH1ForManagement =
      g_MarketData.H1().IsReady() ? g_MarketData.H1().ATR(1) : 0.0;

   g_PositionManager.ManageAll(_Symbol, atrH1ForManagement);

   if(g_RiskEngine.ShouldForceCloseForWeekend())
      ForceCloseAllForWeekend();

   if(!g_MarketData.IsReady() ||
      g_MarketData.H1().Bars() < QXE_MIN_BARS_REQUIRED)
      return;

   bool isNewD1  = QXE_IsNewBar(_Symbol, PERIOD_D1,  g_lastBarD1);
   bool isNewH4  = QXE_IsNewBar(_Symbol, PERIOD_H4,  g_lastBarH4);
   bool isNewH1  = QXE_IsNewBar(_Symbol, PERIOD_H1,  g_lastBarH1);
   bool isNewM15 = QXE_IsNewBar(_Symbol, PERIOD_M15, g_lastBarM15);
   bool isNewM5  = QXE_IsNewBar(_Symbol, PERIOD_M5,  g_lastBarM5);

   if(!isNewD1 && !isNewH4 && !isNewH1 && !isNewM15 && !isNewM5)
      return;

   MarketState state;
   BuildMarketState(state);

   if(isNewH1)
     {
      g_RegimeEngine.Evaluate(GetPointer(g_MarketData), state);
      g_MetaClassifier.Classify(state);

      if(PrintSignals)
        {
         g_Logger.Debug(StringFormat(
            "Regime=%s Trend=%.1f Range=%.1f Vol=%.1f",
            QXE_RegimeToString(state.regime),
            state.trendScore,
            state.rangeScore,
            state.volatilityScore));

         g_Logger.Info(StringFormat(
            "[REGIME] state=%s confidence=%.2f adxH4=%.1f atrPct=%.2f efficiency=%.2f d1H4Aligned=%s",
            EnumToString(state.meta.regime),
            state.meta.confidence,
            state.adxH4,
            state.atrPercentile,
            state.rangeEfficiency,
            state.d1H4Aligned ? "true" : "false"));
        }

      LogHealthSnapshotOncePerDay(state);
     }
   else
     {
      g_RegimeEngine.Evaluate(GetPointer(g_MarketData), state);
      g_MetaClassifier.Classify(state);
     }

   g_lastKnownRegime = state.regime;

   // ---- Evaluate strategies whose cadence just closed ----
   bool anyFreshSignal = false;

   for(int i = 0; i < STRAT_COUNT; i++)
     {
      if(CheckPointer(g_Strategies[i]) != POINTER_DYNAMIC)
         continue;

      ENUM_TIMEFRAMES cad = g_Strategies[i].Cadence();

      bool cadenceClosed =
         (cad == PERIOD_D1  && isNewD1)  ||
         (cad == PERIOD_H4  && isNewH4)  ||
         (cad == PERIOD_H1  && isNewH1)  ||
         (cad == PERIOD_M15 && isNewM15) ||
         (cad == PERIOD_M5  && isNewM5);

      if(!cadenceClosed)
         continue;

      Signal s;

      if(g_Strategies[i].Evaluate(GetPointer(g_MarketData), state, s))
        {
         string eligReason;

         EligibilityDecision decision =
            g_EligibilityEngine.Evaluate(
               (StrategyType)i,
               state.meta,
               s.direction,
               eligReason);

         g_lastEligibility[i] = decision;

         if(PrintSignals)
            g_Logger.Info(StringFormat(
               "[ELIGIBILITY] strategy=%s decision=%s regime=%s reason=%s",
               g_Strategies[i].Name(),
               (decision == ELIGIBILITY_ALLOW)
                  ? "ALLOW"
                  : (decision == ELIGIBILITY_CONFIRMATION_ONLY)
                     ? "CONFIRMATION_ONLY"
                     : "BLOCK",
               EnumToString(state.meta.regime),
               eligReason));

         if(decision == ELIGIBILITY_BLOCK)
           {
            g_lastSignal[i].direction = SIGNAL_NONE;
           }
         else
           {
            g_lastSignal[i]        = s;
            g_lastSignalBarTime[i] = TimeCurrent();
            anyFreshSignal         = true;

            if(PrintSignals)
               g_Logger.Info(StringFormat(
                  "Signal: %s %s score=%.1f reason=%s",
                  g_Strategies[i].Name(),
                  QXE_DirectionToString(s.direction),
                  s.score,
                  s.reason));
           }
        }
      else
        {
         // Strategy cadence closed and it no longer qualifies.
         // Clear its cached signal so it cannot be reused later.
         g_lastSignal[i].direction = SIGNAL_NONE;
        }
     }

   // ================================================================
   // STABLE CACHE CLEANUP
   //
   // IMPORTANT:
   // Cached signals are allowed to contribute to aggregation ONLY when
   // this event includes at least one genuinely NEW strategy signal.
   // Cached signals by themselves must never cause another entry attempt.
   //
   // This removes the former hasFreshCachedSignal path that repeatedly
   // re-aggregated the same setup on M5/M15 closes within the same H1 hour.
   // ================================================================
   if(!anyFreshSignal)
      return;

   Signal eligibleSignals[];
   bool   confirmationOnly[];

   ArrayResize(eligibleSignals, STRAT_COUNT);
   ArrayResize(confirmationOnly, STRAT_COUNT);

   int eligibleCount = 0;

   for(int i = 0; i < STRAT_COUNT; i++)
     {
      if(g_lastSignal[i].direction == SIGNAL_NONE)
         continue;

      if(g_lastSignalBarTime[i] < g_lastBarH1)
         continue;

      // Eligibility was already decided at signal generation time.
      // Do NOT re-evaluate cached signals against a later MetaRegime.
      if(g_lastEligibility[i] == ELIGIBILITY_BLOCK)
         continue;

      eligibleSignals[eligibleCount] = g_lastSignal[i];

      confirmationOnly[eligibleCount] =
         (g_lastEligibility[i] == ELIGIBILITY_CONFIRMATION_ONLY);

      eligibleCount++;
     }

   if(eligibleCount == 0)
      return;

   TradeSetup setup =
      g_ScoreEngine.Aggregate(
         eligibleSignals,
         confirmationOnly,
         eligibleCount,
         state,
         GetPointer(g_InteractionMatrix));

   if(PrintSignals && setup.interactionReason != "")
      g_Logger.Info(StringFormat(
         "[INTERACTION] contributors=%s modifier=%.1f reason=%s",
         setup.contributingStrategies,
         setup.interactionModifier,
         setup.interactionReason));

   if(!setup.valid)
     {
      if(PrintSignals && setup.rejectReason != "")
         g_Logger.Debug("No trade: " + setup.rejectReason);
      return;
     }

   if(EnableSessionFilter && state.session == SESSION_OFF)
     {
      g_Logger.Debug("No trade: outside configured session windows.");
      return;
     }

   string spreadReject;

   double atrM5 =
      g_MarketData.M5().IsReady()
      ? g_MarketData.M5().ATR(1)
      : 0.0;

   if(!g_SpreadFilter.IsAcceptable(
         g_MarketData.CurrentSpreadPoints(),
         atrM5,
         _Symbol,
         spreadReject))
     {
      g_Logger.Debug("No trade: " + spreadReject);
      return;
     }

   if(InpOnePositionPerSymbol && HasOpenPosition())
     {
      HandlePossibleOppositeSignal(setup);
      return;
     }

   RiskParameters risk =
      g_RiskEngine.Validate(_Symbol, setup, equity);

   if(!risk.approved)
     {
      if(InpResearchMode)
         g_Journal.LogResearchSetup(
            setup,
            state,
            g_MarketData.CurrentSpreadPoints(),
            "rejected:" + risk.rejectReason);

      return;
     }

   if(InpResearchMode)
     {
      g_Journal.LogResearchSetup(
         setup,
         state,
         g_MarketData.CurrentSpreadPoints(),
         "would_execute");

      g_Logger.Info(StringFormat(
         "[RESEARCH] Setup logged: %s primary=%s score=%.1f entry=%.2f sl=%.2f lot=%.2f",
         QXE_DirectionToString(setup.direction),
         QXE_StrategyToString(setup.primaryStrategy),
         setup.compositeScore,
         setup.entry,
         setup.stopLoss,
         risk.lotSize));

      return;
     }

   ulong ticket = g_Executor.OpenPosition(setup, risk);

   if(ticket > 0)
     {
      // Execution truth: management and telemetry must anchor to the
      // broker's actual fill, not the theoretical strategy entry.
      TradeSetup executedSetup = setup;
      executedSetup.signalEntry = (setup.signalEntry > 0.0 ? setup.signalEntry : setup.entry);
      executedSetup.sizingEntry = risk.sizingEntryPrice;

      if(PositionSelectByTicket(ticket))
        {
         double fillPrice = PositionGetDouble(POSITION_PRICE_OPEN);

         if(fillPrice > 0.0)
            executedSetup.entry = fillPrice;

         g_Logger.Info(StringFormat(
            "[EXEC-TRUTH] ticket=%I64u identifier=%I64u theoretical=%.5f fill=%.5f drift=%.5f",
            ticket,
            (ulong)PositionGetInteger(POSITION_IDENTIFIER),
            setup.entry,
            executedSetup.entry,
            MathAbs(executedSetup.entry - setup.entry)));
        }
      else
        {
         g_Logger.Error(StringFormat(
            "[EXEC-TRUTH] live position ticket could not be selected after open ticket=%I64u",
            ticket));
         return;
        }

      g_PositionManager.RegisterOpen(
         ticket,
         executedSetup,
         risk,
         state.atrH1,
         state.adxH1,
         state.spreadPoints,
         state);

      g_lastKnownRegime = state.regime;
     }
  }

//+------------------------------------------------------------------+
//| Trade transaction handler                                       |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   if(!HistoryDealSelect(trans.deal))
      return;

   long dealMagic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   if((ulong)dealMagic != InpMagicNumber)
      return;

   long entryType = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);

   if(entryType != DEAL_ENTRY_OUT &&
      entryType != DEAL_ENTRY_OUT_BY)
      return;

   double dealProfit =
      HistoryDealGetDouble(trans.deal, DEAL_PROFIT) +
      HistoryDealGetDouble(trans.deal, DEAL_SWAP) +
      HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

   double dealVolume =
      HistoryDealGetDouble(trans.deal, DEAL_VOLUME);

   double dealPrice =
      HistoryDealGetDouble(trans.deal, DEAL_PRICE);

   datetime dealTime =
      (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);

   ulong positionId =
      (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);

   bool positionStillOpen = IsPositionIdentifierOpen(positionId);

   TradeResult finalResult;

   if(g_PositionManager.ProcessDeal(
         positionId,
         dealVolume,
         dealProfit,
         dealPrice,
         dealTime,
         positionStillOpen,
         g_lastKnownRegime,
         finalResult))
     {
      g_Statistics.Add(finalResult);
      g_Journal.LogTrade(finalResult);
      g_Telemetry.LogTelemetry(finalResult);
     }
  }

//+------------------------------------------------------------------+
//| Stable logical-position identifier lookup                        |
//+------------------------------------------------------------------+
bool IsPositionIdentifierOpen(const ulong positionIdentifier)
  {
   if(positionIdentifier == 0)
      return false;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      if((ulong)PositionGetInteger(POSITION_IDENTIFIER) == positionIdentifier)
         return true;
     }

   return false;
  }

//+------------------------------------------------------------------+
//| Config validation                                                |
//+------------------------------------------------------------------+
bool ValidateDrawdownConfig(void)
  {
   bool ok = true;
   string reason = "";

   if(!(InpModerateDDPct < InpHighDDPct))
     {
      ok = false;
      reason += "InpModerateDDPct must be < InpHighDDPct; ";
     }

   if(!(InpHighDDPct < InpCriticalDDPct))
     {
      ok = false;
      reason += "InpHighDDPct must be < InpCriticalDDPct; ";
     }

   if(!(InpCriticalDDPct < InpHardKillDDPct))
     {
      ok = false;
      reason += "InpCriticalDDPct must be < InpHardKillDDPct; ";
     }

   if(!(InpRecoveryExitDDPct < InpCriticalDDPct))
     {
      ok = false;
      reason += "InpRecoveryExitDDPct must be < InpCriticalDDPct; ";
     }

   if(!(InpCriticalCooldownDays >= 1))
     {
      ok = false;
      reason += "InpCriticalCooldownDays must be >= 1; ";
     }

   if(!(InpRecoveryRiskMultiplier >= 0.0 &&
        InpRecoveryRiskMultiplier <= InpHighDDMultiplier &&
        InpHighDDMultiplier <= InpModerateDDMultiplier &&
        InpModerateDDMultiplier <= 1.0))
     {
      ok = false;
      reason += "risk multipliers must satisfy 0 <= Recovery <= High <= Moderate <= 1; ";
     }

   if(!ok)
      g_Logger.Error(
         "[RISK] CONFIG_ERROR INVALID_DD_THRESHOLDS " + reason);

   return ok;
  }

//+------------------------------------------------------------------+
//| Build market state                                               |
//+------------------------------------------------------------------+
void BuildMarketState(MarketState &state)
  {
   CTimeframeData *m5  = g_MarketData.M5();
   CTimeframeData *m15 = g_MarketData.M15();
   CTimeframeData *h1  = g_MarketData.H1();
   CTimeframeData *h4  = g_MarketData.H4();
   CTimeframeData *d1  = g_MarketData.D1();

   state.barTime = h1.Time(1);
   state.close   = h1.Close(1);
   state.open    = h1.Open(1);
   state.high    = h1.High(1);
   state.low     = h1.Low(1);

   state.atrM5  = m5.ATR(1);
   state.atrM15 = m15.ATR(1);
   state.atrH1  = h1.ATR(1);
   state.atrH4  = h4.ATR(1);
   state.atrD1  = d1.ATR(1);

   state.adxH1 = h1.ADX(1);
   state.adxH4 = h4.ADX(1);

   state.ema20       = h1.EMA20(1);
   state.ema50       = h1.EMA50(1);
   state.ema200      = h1.EMA200(1);
   state.emaSlope200 = h1.EMA200SlopePoints(20);

   state.bbUpper  = h1.BBUpper(1);
   state.bbMiddle = h1.BBMiddle(1);
   state.bbLower  = h1.BBLower(1);

   state.stdDev =
      (state.bbUpper - state.bbMiddle) /
      MathMax(InpBBDeviation, QXE_EPS);

   state.vwap         = g_MarketData.VWAP();
   state.spreadPoints = g_MarketData.CurrentSpreadPoints();
   state.atrPercentile = 0.5;
   state.session       = QXE_CurrentSession();

   state.regime          = REGIME_NO_TRADE;
   state.trendScore      = 0.0;
   state.rangeScore      = 0.0;
   state.volatilityScore = 0.0;
   state.regimeScore     = 0.0;

   state.emaSlope20 = h1.EMA20SlopePoints(20);
   state.emaSlope50 = h1.EMA50SlopePoints(20);

   double closeD1  = d1.Close(1);
   double ema200D1 = d1.EMA200(1);
   double closeH4  = h4.Close(1);
   double ema200H4 = h4.EMA200(1);

   state.d1Bias =
      (closeD1 > ema200D1)
      ? 1
      : ((closeD1 < ema200D1) ? -1 : 0);

   state.h4Bias =
      (closeH4 > ema200H4)
      ? 1
      : ((closeH4 < ema200H4) ? -1 : 0);

   state.d1H4Aligned =
      (state.d1Bias != 0 &&
       state.d1Bias == state.h4Bias);

   state.rangeEfficiency = QXE_AverageRangeEfficiency(h1, 10);
   state.trendEfficiency = QXE_TrendEfficiency(h1, 10);

   state.distEMA20_ATR =
      (state.atrH1 > QXE_EPS)
      ? (state.close - state.ema20) / state.atrH1
      : 0.0;

   state.distEMA50_ATR =
      (state.atrH1 > QXE_EPS)
      ? (state.close - state.ema50) / state.atrH1
      : 0.0;

   state.distEMA200_ATR =
      (state.atrH1 > QXE_EPS)
      ? (state.close - state.ema200) / state.atrH1
      : 0.0;

   state.prevDayRange =
      d1.High(1) - d1.Low(1);

   double currDayRangeSoFar =
      d1.High(0) - d1.Low(0);

   state.currDayRangeRatio =
      (state.prevDayRange > QXE_EPS)
      ? currDayRangeSoFar / state.prevDayRange
      : 0.0;

   MqlDateTime dtNow;
   TimeToStruct(state.barTime, dtNow);

   state.dayOfWeek = dtNow.day_of_week;
   state.hourOfDay = dtNow.hour;

   state.spreadATRRatio =
      (state.atrM5 > QXE_EPS)
      ? QXE_PointsToPrice(_Symbol, state.spreadPoints) /
        state.atrM5
      : 0.0;

   static datetime lastStructureBar = 0;

   if(h1.Time(1) != lastStructureBar)
     {
      g_StateStructure.Update(h1);
      lastStructureBar = h1.Time(1);
     }

   state.structureBias = g_StateStructure.Bias();
   state.recentBOS     = g_StateStructure.IsRecentBOS();
   state.recentCHoCH   = g_StateStructure.IsRecentCHoCH();
  }

//+------------------------------------------------------------------+
//| Open-position check                                              |
//+------------------------------------------------------------------+
bool HasOpenPosition(void)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      return true;
     }

   return false;
  }

//+------------------------------------------------------------------+
//| Weekend close                                                    |
//+------------------------------------------------------------------+
void ForceCloseAllForWeekend(void)
  {
   static datetime lastForceCloseDay = 0;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;

   datetime dayAnchor = StructToTime(dt);

   if(dayAnchor == lastForceCloseDay)
      return;

   lastForceCloseDay = dayAnchor;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0 ||
         PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      g_PositionManager.TagPendingExit(ticket, EXIT_MANUAL);
      g_Executor.CloseFull(ticket);
     }
  }

//+------------------------------------------------------------------+
//| Opposite signal handling                                        |
//+------------------------------------------------------------------+
void HandlePossibleOppositeSignal(const TradeSetup &newSetup)
  {
   if(!InpAllowOppositeReversal)
      return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0 ||
         PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      long posType =
         PositionGetInteger(POSITION_TYPE);

      SignalDirection posDir =
         (posType == POSITION_TYPE_BUY)
         ? SIGNAL_BUY
         : SIGNAL_SELL;

      if(newSetup.direction != SIGNAL_NONE &&
         newSetup.direction != posDir &&
         newSetup.compositeScore > 60.0)
        {
         g_Logger.Info(StringFormat(
            "Opposite signal (score %.1f) - closing existing position %d",
            newSetup.compositeScore,
            ticket));

         g_PositionManager.TagPendingExit(
            ticket,
            EXIT_OPPOSITE_SIGNAL);

         g_Executor.CloseFull(ticket);
        }
     }
  }

//+------------------------------------------------------------------+
//| Daily health snapshot                                            |
//+------------------------------------------------------------------+
void LogHealthSnapshotOncePerDay(const MarketState &state)
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;

   datetime dayAnchor = StructToTime(dt);

   if(dayAnchor == g_lastHealthLogDay)
      return;

   g_lastHealthLogDay = dayAnchor;

   double equity =
      AccountInfoDouble(ACCOUNT_EQUITY);

   g_RiskEngine.LogHealthSnapshot(
      state.regime,
      equity);
  }
//+------------------------------------------------------------------+
