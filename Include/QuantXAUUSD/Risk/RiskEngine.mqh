//+------------------------------------------------------------------+
//| RiskEngine.mqh                                                   |
//| QUANT_XAUUSD_ENGINE - Risk validation and sizing (spec 24-29)    |
//|                                                                   |
//| REPAIR PASS changes:                                             |
//| 1. Daily trade counter now increments ONLY on RegisterTradeOpened|
//|    - partial closes / TP1 / TP2 no longer inflate it (previously |
//|    RegisterTradeResult() was called from every closed deal,      |
//|    silently exhausting InpMaxDailyTrades on partials alone).     |
//| 2. Consecutive-loss counter increments/resets ONLY on            |
//|    RegisterTradeClosed() (final logical-trade close), not on     |
//|    every deal.                                                   |
//| 3. Critical account drawdown (CDrawdownProtection) is explicitly |
//|    NOT reset on the daily rollover - it is account-level and     |
//|    persists for as long as equity remains below the critical     |
//|    threshold, by design (see "IMPORTANT: DAILY HALT SEMANTICS"). |
//| 4. Every rejection now logs a structured [RISK] REJECT <CODE>    |
//|    line so deadlocks are diagnosable directly from the log.      |
//| 5. Explicit directional SL validation, defense-in-depth (also    |
//|    checked earlier in ScoreEngine - this is a second, independent|
//|    check right before sizing).                                   |
//| 6. Lightweight health/deadlock watchdog, diagnostic only - never |
//|    bypasses a risk rule.                                          |
//+------------------------------------------------------------------+
#ifndef QXE_RISKENGINE_MQH
#define QXE_RISKENGINE_MQH

#include "PositionSizing.mqh"
#include "DrawdownProtection.mqh"
#include "WeekendGuard.mqh"
#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Utilities.mqh"
#include "../Core/Logger.mqh"

class CRiskEngine
  {
private:
   CPositionSizing   m_sizing;
   CDrawdownProtection m_drawdown;
   CWeekendGuard     m_weekendGuard;

   double            m_dayStartEquity;
   datetime          m_currentDayAnchor;
   int               m_tradesToday;       // OPENED positions only
   int               m_consecutiveLosses; // updated on CLOSED logical trades only
   bool              m_dailyHalted;

   datetime          m_lastTradeOpenTime; // health watchdog
   string            m_lastRejectReason;

public:
   void              Init(double startingEquity, string symbol, ulong magic)
     {
      m_drawdown.Init(startingEquity, symbol, magic);
      m_dayStartEquity = startingEquity;
      m_currentDayAnchor = 0;
      m_tradesToday = 0;
      m_consecutiveLosses = 0;
      m_dailyHalted = false;
      m_lastTradeOpenTime = 0;
      m_lastRejectReason = "";
     }

   // Call EVERY tick. This is now the ONLY place drawdown thresholds are
   // evaluated (CDrawdownProtection::Evaluate) - a DD spike is caught
   // intraday, not on the next day boundary. Day-boundary bookkeeping
   // (daily counters, consecutive-loss reset, and cooldown-day counting)
   // still only happens once per new day, inside the day-change branch.
   void              OnTick(double currentEquity)
     {
      m_drawdown.Evaluate(currentEquity, TimeCurrent());

      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      datetime dayAnchor = StructToTime(dt);

      if(dayAnchor != m_currentDayAnchor)
        {
         int oldConsecutive = m_consecutiveLosses;
         m_currentDayAnchor = dayAnchor;
         m_dayStartEquity = currentEquity;
         m_tradesToday = 0;
         m_dailyHalted = false;
         m_consecutiveLosses = 0; // daily guard (spec section 28) - resets
                                   // every day; the Recovery State Machine
                                   // is evaluated independently, every tick.
         g_Logger.Info(StringFormat(
            "[RISK] NEW_DAY date=%s tradesToday_reset=0 consecutiveLosses_old=%d consecutiveLosses_new=0 dailyHalted=false",
            TimeToString(dayAnchor, TIME_DATE), oldConsecutive));

         m_drawdown.OnNewTradingDay(dayAnchor); // cooldown-day accounting ONLY
        }
     }

   // The ONLY way to exit HARD_KILL. Never called automatically by the
   // engine itself - exposed for an operator/administrator action.
   bool              ManualResetDrawdown(double currentEquity)
     {
      return m_drawdown.ManualReset(currentEquity);
     }

   DrawdownState     DrawdownStateNow(void) const { return m_drawdown.State(); }

   // Call the moment a new logical position is successfully opened.
   // This is the ONLY place m_tradesToday increments (repair spec:
   // "InpMaxDailyTrades means trades OPENED per day, not exit deals").
   void              RegisterTradeOpened(void)
     {
      m_tradesToday++;
      m_lastTradeOpenTime = TimeCurrent();
     }

   // Call ONLY when a logical position is FULLY closed (final exit, all
   // partials aggregated) - never on an intermediate partial close.
   void              RegisterTradeClosed(double totalProfit)
     {
      if(totalProfit < 0.0)
         m_consecutiveLosses++;
      else if(totalProfit > 0.0)
         m_consecutiveLosses = 0;
     }

   // Validates a TradeSetup end-to-end and produces final RiskParameters.
   RiskParameters    Validate(string symbol, const TradeSetup &setup, double currentEquity)
     {
      RiskParameters rp;
      rp.approved = false;
      rp.riskPercent = InpRiskPercent;
      rp.equity = currentEquity;
      rp.lotSize = 0.0;
      rp.moneyAtRisk = 0.0;
      rp.riskMultiplier = 1.0;
      rp.slDistancePoints = 0.0;
      rp.slDistancePrice = 0.0;
      rp.lossPerLotBroker = 0.0;
      rp.lossPerLotTickModel = 0.0;
      rp.rejectReason = "";

      if(!setup.valid)
         return Reject(rp, "SETUP_INVALID", "Setup not valid: " + setup.rejectReason);

      if(m_drawdown.IsTradingHalted(currentEquity))
         return Reject(rp, m_drawdown.StateToString(m_drawdown.State()),
                        StringFormat("dd=%.2f%%", m_drawdown.CurrentDrawdownPct(currentEquity)));

      if(m_dailyHalted)
         return Reject(rp, "DAILY_LOSS", "already halted for today");

      double dailyLossPct = (m_dayStartEquity > 0.0) ?
         (m_dayStartEquity - currentEquity) / m_dayStartEquity * 100.0 : 0.0;
      if(dailyLossPct >= InpMaxDailyLossPct)
        {
         m_dailyHalted = true;
         return Reject(rp, "DAILY_LOSS", StringFormat("%.2f%% >= limit %.2f%%", dailyLossPct, InpMaxDailyLossPct));
        }

      if(m_tradesToday >= InpMaxDailyTrades)
         return Reject(rp, "MAX_DAILY_TRADES", StringFormat("%d/%d", m_tradesToday, InpMaxDailyTrades));

      if(m_consecutiveLosses >= InpMaxConsecutiveLosses)
         return Reject(rp, "DAILY_CONSECUTIVE_LOSSES", StringFormat("%d/%d", m_consecutiveLosses, InpMaxConsecutiveLosses));

      // Weekend / gap risk guard (spec section 19) - blocks NEW entries
      // near the weekly close regardless of how good the setup scored.
      if(m_weekendGuard.BlocksNewEntry(TimeCurrent()))
         return Reject(rp, "WEEKEND_GUARD", "no new entries in the pre-weekend window");

      // Directional SL validation - defense-in-depth (also checked in
      // ScoreEngine before this point; re-checked independently here).
      if(setup.direction == SIGNAL_BUY && setup.stopLoss >= setup.entry)
         return Reject(rp, "INVALID_DIRECTIONAL_SL", StringFormat("BUY sl=%.2f entry=%.2f", setup.stopLoss, setup.entry));
      if(setup.direction == SIGNAL_SELL && setup.stopLoss <= setup.entry)
         return Reject(rp, "INVALID_DIRECTIONAL_SL", StringFormat("SELL sl=%.2f entry=%.2f", setup.stopLoss, setup.entry));

      // Stop-distance sanity check (spec section 25).
      double slDistance = MathAbs(setup.entry - setup.stopLoss);
      double slPoints = QXE_PriceToPoints(symbol, slDistance);
      if(slPoints < InpMinStopDistancePoints || slPoints > InpMaxStopDistancePoints)
         return Reject(rp, "SL_DISTANCE_OUT_OF_RANGE",
                        StringFormat("%.0f pts, allowed [%.0f, %.0f]", slPoints, InpMinStopDistancePoints, InpMaxStopDistancePoints));

      double stopsLevel = QXE_StopsLevelPoints(symbol);
      if(stopsLevel > 0.0 && slPoints < stopsLevel)
         return Reject(rp, "SL_BELOW_BROKER_MIN", StringFormat("%.0f pts < min %.0f pts", slPoints, stopsLevel));

      double riskMultiplier = m_drawdown.RiskMultiplier(currentEquity) * m_weekendGuard.RiskMultiplier(TimeCurrent());
      double effectiveRiskPercent = InpRiskPercent * riskMultiplier;

      double moneyAtRisk = 0.0;
      double lossPerLotBroker = 0.0, lossPerLotTickModel = 0.0;
      double lot = m_sizing.CalculateLot(symbol, currentEquity, effectiveRiskPercent,
                                          setup.direction, setup.entry, setup.stopLoss,
                                          moneyAtRisk, lossPerLotBroker, lossPerLotTickModel);

      // [RISK-INTEGRITY] Log every sizing input RAW, unrounded, the
      // moment it is computed - this is what lets us confirm or refute
      // whether a configured risk% actually maps to the expected loss
      // at SL, independent of whatever the trade eventually does.
      // lossPerLotBroker (from OrderCalcProfit) is the value actually
      // used for sizing; lossPerLotTickModel is diagnostic only.
      double expectedMoneyToRisk = currentEquity * (effectiveRiskPercent / 100.0);
      g_Logger.Info(StringFormat(
         "[RISK-INTEGRITY] equity=%.2f reqRisk%%=%.4f expectedMoney=%.2f slDistPrice=%.5f lossPerLotBroker=%.4f lossPerLotTickModel=%.4f normalizedLot=%.4f expectedLossAtNormalizedLot=%.2f",
         currentEquity, effectiveRiskPercent, expectedMoneyToRisk, slDistance,
         lossPerLotBroker, lossPerLotTickModel, lot, moneyAtRisk));

      if(lot <= 0.0)
         return Reject(rp, "LOT_BELOW_MINIMUM", "calculated lot rounds to 0 at target risk% (or OrderCalcProfit failed) - NOT inflated to broker minimum");

      rp.approved = true;
      rp.riskPercent = effectiveRiskPercent;
      rp.riskMultiplier = riskMultiplier;
      rp.slDistancePoints = slPoints;
      rp.slDistancePrice = slDistance;
      rp.lossPerLotBroker = lossPerLotBroker;
      rp.lossPerLotTickModel = lossPerLotTickModel;
      rp.lotSize = lot;
      rp.moneyAtRisk = moneyAtRisk;
      m_lastRejectReason = "";
      return rp;
     }

   int               TradesToday(void) const { return m_tradesToday; }
   int               ConsecutiveLosses(void) const { return m_consecutiveLosses; }
   double            CurrentDrawdownPct(double equity) const { return m_drawdown.CurrentDrawdownPct(equity); }
   bool              ShouldForceCloseForWeekend(void) const { return m_weekendGuard.ShouldForceClose(TimeCurrent()); }

   // Diagnostic-only health snapshot. Never bypasses a risk rule - it
   // only helps distinguish "no market setups" from "risk engine deadlock"
   // (repair spec: "HEALTH / DEADLOCK WATCHDOG").
   void              LogHealthSnapshot(RegimeType currentRegime, double currentEquity) const
     {
      int daysSinceLastTrade = (m_lastTradeOpenTime > 0) ?
         (int)((TimeCurrent() - m_lastTradeOpenTime) / 86400) : -1;

      g_Logger.Info(StringFormat(
         "[HEALTH] DaysSinceLastTrade=%d CurrentRegime=%s DailyHalted=%s ConsecutiveLosses=%d/%d TradesToday=%d/%d Drawdown=%.2f%% LastRejectReason=%s",
         daysSinceLastTrade, QXE_RegimeToString(currentRegime),
         m_dailyHalted ? "true" : "false",
         m_consecutiveLosses, InpMaxConsecutiveLosses,
         m_tradesToday, InpMaxDailyTrades,
         m_drawdown.CurrentDrawdownPct(currentEquity),
         (m_lastRejectReason == "") ? "none" : m_lastRejectReason));
     }

private:
   RiskParameters    Reject(RiskParameters &rp, string code, string detail)
     {
      rp.approved = false;
      rp.rejectReason = code + ": " + detail;
      m_lastRejectReason = rp.rejectReason;
      g_Logger.Info(StringFormat("[RISK] REJECT %s %s", code, detail));
      return rp;
     }
  };

#endif // QXE_RISKENGINE_MQH
