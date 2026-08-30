//+------------------------------------------------------------------+
//| DrawdownProtection.mqh                                           |
//| QUANT_XAUUSD_ENGINE - Drawdown Recovery State Machine             |
//|                                                                   |
//| FINAL INTEGRATION PASS changes:                                  |
//| 1. State transitions (including entry into CRITICAL_COOLDOWN and |
//|    HARD_KILL) now happen in `Evaluate()`, called every tick -     |
//|    NOT only once per day. A DD spike from 4% to 15.1% intraday    |
//|    enters CRITICAL_COOLDOWN immediately, it does not wait for the |
//|    next day boundary.                                              |
//| 2. `OnNewTradingDay()` now does ONLY cooldown-day accounting       |
//|    (incrementing the trading-day counter while in                 |
//|    CRITICAL_COOLDOWN and promoting to RECOVERY once the configured|
//|    number of days has elapsed) - it no longer evaluates DD         |
//|    thresholds itself.                                              |
//| 3. State persists across terminal/EA restarts via                 |
//|    GlobalVariableSet/Get, keyed by account login + magic number + |
//|    symbol, so a HARD_KILL (or any other state) survives a restart |
//|    instead of silently resetting to NORMAL with a fresh equity    |
//|    peak - which would defeat the entire point of a "permanent"    |
//|    halt. NOTE: this uses MetaTrader's terminal-wide global         |
//|    variable store; its exact behavior across separate Strategy    |
//|    Tester runs (vs a live/demo terminal restart) was not verified |
//|    against a running MetaTrader instance in this environment and  |
//|    should be confirmed by the user before relying on it live.     |
//| 4. `ManualReset()` is the ONLY way out of HARD_KILL - there is no  |
//|    automatic path, by design.                                     |
//+------------------------------------------------------------------+
#ifndef QXE_DRAWDOWNPROTECTION_MQH
#define QXE_DRAWDOWNPROTECTION_MQH

#include "../Core/Config.mqh"
#include "../Core/Logger.mqh"

enum DrawdownState
  {
   DD_STATE_NORMAL = 0,
   DD_STATE_MODERATE = 1,
   DD_STATE_HIGH = 2,
   DD_STATE_CRITICAL_COOLDOWN = 3,
   DD_STATE_RECOVERY = 4,
   DD_STATE_HARD_KILL = 5
  };

class CDrawdownProtection
  {
private:
   double            m_equityPeak;
   DrawdownState     m_state;
   datetime          m_cooldownEnteredDay;   // day-anchor (midnight) the cooldown started
   int               m_cooldownTradingDaysElapsed;
   datetime          m_lastCountedDay;       // last day-anchor already counted toward cooldown

   string            m_keyPeak;
   string            m_keyState;
   string            m_keyCooldownEnteredDay;
   string            m_keyCooldownDaysElapsed;
   string            m_keyLastCountedDay;
   bool              m_persistenceEnabled;

public:
   // `symbol` and `magic` make the persistence key unique per EA
   // instance/symbol; account login makes it unique per account. If
   // GlobalVariable access is unavailable for any reason, persistence is
   // silently disabled (falls back to in-memory-only, same as before)
   // rather than failing EA init over it.
   void              Init(double startingEquity, string symbol, ulong magic)
     {
      long login = AccountInfoInteger(ACCOUNT_LOGIN);
      string prefix = StringFormat("QXE_%d_%d_%s_", login, magic, symbol);
      m_keyPeak = prefix + "DD_PEAK";
      m_keyState = prefix + "DD_STATE";
      m_keyCooldownEnteredDay = prefix + "DD_COOLDOWN_ENTERED_DAY";
      m_keyCooldownDaysElapsed = prefix + "DD_COOLDOWN_DAYS_ELAPSED";
      m_keyLastCountedDay = prefix + "DD_LAST_COUNTED_DAY";
      m_persistenceEnabled = true;

      if(TryLoad())
        {
         g_Logger.Info(StringFormat("[RECOVERY] Restored persisted state=%s peak=%.2f (restart/init survived)",
                        StateToString(m_state), m_equityPeak));
         return;
        }

      // No persisted state found - fresh start.
      m_equityPeak = startingEquity;
      m_state = DD_STATE_NORMAL;
      m_cooldownEnteredDay = 0;
      m_cooldownTradingDaysElapsed = 0;
      m_lastCountedDay = 0;
      Persist();
     }

   // Call every tick (or at minimum before validating any new entry) -
   // this is the ONLY place state transitions into CRITICAL_COOLDOWN or
   // HARD_KILL happen, so a DD spike is caught intraday, not on the next
   // day boundary.
   void              Evaluate(double currentEquity, datetime now)
     {
      if(currentEquity > m_equityPeak)
        {
         m_equityPeak = currentEquity;
         Persist();
        }

      double dd = CurrentDrawdownPct(currentEquity);
      DrawdownState before = m_state;

      if(m_state == DD_STATE_HARD_KILL)
         return; // permanent - only ManualReset() can leave this state

      if(dd >= InpHardKillDDPct)
        {
         m_state = DD_STATE_HARD_KILL;
         FinishTransition(before, dd);
         return;
        }

      if(m_state == DD_STATE_CRITICAL_COOLDOWN)
         return; // day-counting and the eventual promotion to RECOVERY is OnNewTradingDay()'s job

      if(m_state == DD_STATE_RECOVERY)
        {
         // Hysteresis: RECOVERY only exits once DD has genuinely
         // improved to InpRecoveryExitDDPct or better - never on a
         // single-tick dip back under InpCriticalDDPct.
         if(dd <= InpRecoveryExitDDPct)
           {
            m_state = ResolveLadderState(dd);
            FinishTransition(before, dd);
           }
         return;
        }

      // NORMAL / MODERATE / HIGH ladder, and immediate entry into
      // CRITICAL_COOLDOWN the instant DD crosses the threshold.
      if(dd >= InpCriticalDDPct)
        {
         m_state = DD_STATE_CRITICAL_COOLDOWN;
         m_cooldownEnteredDay = ToDayAnchor(now);
         m_cooldownTradingDaysElapsed = 0;
         m_lastCountedDay = m_cooldownEnteredDay;
        }
      else
        {
         m_state = ResolveLadderState(dd);
        }

      FinishTransition(before, dd);
     }

   // Call once per new trading day. ONLY responsible for cooldown-day
   // accounting - it does NOT evaluate DD thresholds itself anymore
   // (Evaluate() does that, every tick).
   void              OnNewTradingDay(datetime dayAnchor)
     {
      if(m_state != DD_STATE_CRITICAL_COOLDOWN)
         return;

      if(dayAnchor != m_lastCountedDay)
        {
         m_cooldownTradingDaysElapsed++;
         m_lastCountedDay = dayAnchor;
         Persist();
        }

      if(m_cooldownTradingDaysElapsed >= InpCriticalCooldownDays)
        {
         DrawdownState before = m_state;
         m_state = DD_STATE_RECOVERY;
         g_Logger.Info(StringFormat("[RECOVERY] state=%s->%s cooldown complete (%d trading days)",
                        StateToString(before), StateToString(m_state), m_cooldownTradingDaysElapsed));
         Persist();
        }
     }

   // The ONLY way out of HARD_KILL. Never called automatically. Returns
   // false (and does nothing) if not currently in HARD_KILL, so callers
   // cannot accidentally use it as a generic "reset drawdown" shortcut.
   bool              ManualReset(double currentEquity)
     {
      if(m_state != DD_STATE_HARD_KILL)
        {
         g_Logger.Warn("ManualReset() called but state is not HARD_KILL - ignored.");
         return false;
        }

      DrawdownState before = m_state;
      m_state = DD_STATE_NORMAL;
      m_equityPeak = currentEquity;
      m_cooldownEnteredDay = 0;
      m_cooldownTradingDaysElapsed = 0;
      m_lastCountedDay = 0;
      Persist();

      g_Logger.Info(StringFormat("[RECOVERY] MANUAL_RESET state=%s->%s newPeak=%.2f",
                     StateToString(before), StateToString(m_state), m_equityPeak));
      return true;
     }

   double            CurrentDrawdownPct(double currentEquity) const
     {
      if(m_equityPeak <= 0.0)
         return 0.0;
      return (m_equityPeak - currentEquity) / m_equityPeak * 100.0;
     }

   DrawdownState     State(void) const { return m_state; }

   string            StateToString(DrawdownState s) const
     {
      switch(s)
        {
         case DD_STATE_NORMAL:            return "NORMAL";
         case DD_STATE_MODERATE:          return "MODERATE_DD";
         case DD_STATE_HIGH:              return "HIGH_DD";
         case DD_STATE_CRITICAL_COOLDOWN: return "CRITICAL_COOLDOWN";
         case DD_STATE_RECOVERY:          return "RECOVERY";
         case DD_STATE_HARD_KILL:         return "HARD_KILL";
         default:                         return "UNKNOWN";
        }
     }

   double            RiskMultiplier(double currentEquity) const
     {
      switch(m_state)
        {
         case DD_STATE_NORMAL:            return 1.0;
         case DD_STATE_MODERATE:          return InpModerateDDMultiplier;
         case DD_STATE_HIGH:              return InpHighDDMultiplier;
         case DD_STATE_CRITICAL_COOLDOWN: return 0.0; // no new trades at all during cooldown
         case DD_STATE_RECOVERY:          return InpRecoveryRiskMultiplier;
         case DD_STATE_HARD_KILL:         return 0.0;
         default:                         return 0.0;
        }
     }

   bool              IsTradingHalted(double currentEquity) const
     {
      return (m_state == DD_STATE_CRITICAL_COOLDOWN || m_state == DD_STATE_HARD_KILL);
     }

private:
   datetime          ToDayAnchor(datetime t) const
     {
      MqlDateTime dt;
      TimeToStruct(t, dt);
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      return StructToTime(dt);
     }

   DrawdownState     ResolveLadderState(double dd) const
     {
      if(dd >= InpHighDDPct)     return DD_STATE_HIGH;
      if(dd >= InpModerateDDPct) return DD_STATE_MODERATE;
      return DD_STATE_NORMAL;
     }

   void              FinishTransition(DrawdownState before, double dd)
     {
      if(m_state != before)
        {
         g_Logger.Info(StringFormat("[RECOVERY] state=%s->%s dd=%.2f%%",
                        StateToString(before), StateToString(m_state), dd));
         Persist();
        }
     }

   void              Persist(void)
     {
      if(!m_persistenceEnabled)
         return;
      GlobalVariableSet(m_keyPeak, m_equityPeak);
      GlobalVariableSet(m_keyState, (double)m_state);
      GlobalVariableSet(m_keyCooldownEnteredDay, (double)m_cooldownEnteredDay);
      GlobalVariableSet(m_keyCooldownDaysElapsed, (double)m_cooldownTradingDaysElapsed);
      GlobalVariableSet(m_keyLastCountedDay, (double)m_lastCountedDay);
     }

   bool              TryLoad(void)
     {
      if(!GlobalVariableCheck(m_keyState))
         return false;

      m_state = (DrawdownState)(int)GlobalVariableGet(m_keyState);
      m_equityPeak = GlobalVariableCheck(m_keyPeak) ? GlobalVariableGet(m_keyPeak) : 0.0;
      m_cooldownEnteredDay = GlobalVariableCheck(m_keyCooldownEnteredDay) ?
         (datetime)GlobalVariableGet(m_keyCooldownEnteredDay) : 0;
      m_cooldownTradingDaysElapsed = GlobalVariableCheck(m_keyCooldownDaysElapsed) ?
         (int)GlobalVariableGet(m_keyCooldownDaysElapsed) : 0;
      m_lastCountedDay = GlobalVariableCheck(m_keyLastCountedDay) ?
         (datetime)GlobalVariableGet(m_keyLastCountedDay) : 0;

      return (m_equityPeak > 0.0);
     }
  };

#endif // QXE_DRAWDOWNPROTECTION_MQH
