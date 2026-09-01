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
   CPositionSizing m_sizing;
   CDrawdownProtection m_drawdown;
   CWeekendGuard m_weekendGuard;
   string m_symbol;
   ulong m_magic;
   double m_dayStartEquity;
   datetime m_currentDayAnchor;
   int m_tradesToday;
   int m_consecutiveLosses;
   bool m_dailyHalted;
   datetime m_lastTradeOpenTime;
   string m_lastRejectReason;
   bool m_persistenceEnabled;
   string m_keyDay,m_keyDayEquity,m_keyTrades,m_keyConsecutive,m_keyHalted,m_keyLastTrade;

public:
   void Init(double startingEquity,string symbol,ulong magic)
     {
      m_symbol=symbol; m_magic=magic;
      m_drawdown.Init(startingEquity,symbol,magic);
      bool isTester=(bool)MQLInfoInteger(MQL_TESTER);
      bool isOptimization=(bool)MQLInfoInteger(MQL_OPTIMIZATION);
      m_persistenceEnabled=!(isTester||isOptimization);
      long login=AccountInfoInteger(ACCOUNT_LOGIN);
      string prefix=StringFormat("QXE_%d_%d_%s_RISK_",login,magic,symbol);
      m_keyDay=prefix+"DAY"; m_keyDayEquity=prefix+"DAY_EQ"; m_keyTrades=prefix+"TRADES";
      m_keyConsecutive=prefix+"CONSEC"; m_keyHalted=prefix+"HALTED"; m_keyLastTrade=prefix+"LAST_OPEN";

      m_dayStartEquity=startingEquity; m_currentDayAnchor=0; m_tradesToday=0; m_consecutiveLosses=0;
      m_dailyHalted=false; m_lastTradeOpenTime=0; m_lastRejectReason="";

      datetime today=DayAnchor(TimeCurrent());
      if(m_persistenceEnabled && TryLoadDaily() && m_currentDayAnchor==today)
        {
         g_Logger.Info(StringFormat("[RISK] RESTORED day=%s startEq=%.2f trades=%d consecutive=%d halted=%s",
            TimeToString(m_currentDayAnchor,TIME_DATE),m_dayStartEquity,m_tradesToday,m_consecutiveLosses,m_dailyHalted?"true":"false"));
        }
      else
        {
         m_currentDayAnchor=today; m_dayStartEquity=startingEquity; m_tradesToday=0; m_consecutiveLosses=0; m_dailyHalted=false;
         PersistDaily();
        }
     }

   void OnTick(double currentEquity)
     {
      datetime now=TimeCurrent();
      m_drawdown.Evaluate(currentEquity,now);
      datetime day=DayAnchor(now);
      if(day!=m_currentDayAnchor)
        {
         int oldConsecutive=m_consecutiveLosses;
         m_currentDayAnchor=day; m_dayStartEquity=currentEquity; m_tradesToday=0; m_dailyHalted=false; m_consecutiveLosses=0;
         m_drawdown.OnNewTradingDay(day);
         PersistDaily();
         g_Logger.Info(StringFormat("[RISK] NEW_DAY date=%s tradesToday_reset=0 consecutiveLosses_old=%d consecutiveLosses_new=0 dailyHalted=false",
            TimeToString(day,TIME_DATE),oldConsecutive));
        }
     }

   bool ManualResetDrawdown(double currentEquity) { return m_drawdown.ManualReset(currentEquity); }
   DrawdownState DrawdownStateNow(void) const { return m_drawdown.State(); }

   void RegisterTradeOpened(void)
     {
      m_tradesToday++; m_lastTradeOpenTime=TimeCurrent(); PersistDaily();
     }
   void RegisterTradeClosed(double totalProfit)
     {
      if(totalProfit<0.0) m_consecutiveLosses++;
      else if(totalProfit>0.0) m_consecutiveLosses=0;
      PersistDaily();
     }

   RiskParameters Validate(string symbol,const TradeSetup &setup,double currentEquity)
     {
      RiskParameters rp; ResetRisk(rp,currentEquity);
      if(!setup.valid) return Reject(rp,"SETUP_INVALID","Setup not valid: "+setup.rejectReason);
      if(m_drawdown.IsTradingHalted(currentEquity)) return Reject(rp,m_drawdown.StateToString(m_drawdown.State()),StringFormat("dd=%.2f%%",m_drawdown.CurrentDrawdownPct(currentEquity)));
      if(m_dailyHalted) return Reject(rp,"DAILY_LOSS","already halted for today");

      double dailyLossPct=(m_dayStartEquity>0.0)?(m_dayStartEquity-currentEquity)/m_dayStartEquity*100.0:0.0;
      if(dailyLossPct>=InpMaxDailyLossPct)
        { m_dailyHalted=true; PersistDaily(); return Reject(rp,"DAILY_LOSS",StringFormat("%.2f%% >= limit %.2f%%",dailyLossPct,InpMaxDailyLossPct)); }
      if(m_tradesToday>=InpMaxDailyTrades) return Reject(rp,"MAX_DAILY_TRADES",StringFormat("%d/%d",m_tradesToday,InpMaxDailyTrades));
      if(m_consecutiveLosses>=InpMaxConsecutiveLosses) return Reject(rp,"DAILY_CONSECUTIVE_LOSSES",StringFormat("%d/%d",m_consecutiveLosses,InpMaxConsecutiveLosses));
      if(m_weekendGuard.BlocksNewEntry(TimeCurrent())) return Reject(rp,"WEEKEND_GUARD","no new entries in the pre-weekend window");

      double liveEntry=(setup.direction==SIGNAL_BUY)?SymbolInfoDouble(symbol,SYMBOL_ASK):SymbolInfoDouble(symbol,SYMBOL_BID);
      if(liveEntry<=0.0) return Reject(rp,"LIVE_PRICE_INVALID","Ask/Bid unavailable");
      double signalEntry=(setup.signalEntry>0.0)?setup.signalEntry:setup.entry;
      double entryDrift=MathAbs(liveEntry-signalEntry);

      if(setup.direction==SIGNAL_BUY && setup.stopLoss>=liveEntry)
         return Reject(rp,"INVALID_DIRECTIONAL_SL",StringFormat("BUY sl=%.2f liveAsk=%.2f signalEntry=%.2f",setup.stopLoss,liveEntry,signalEntry));
      if(setup.direction==SIGNAL_SELL && setup.stopLoss<=liveEntry)
         return Reject(rp,"INVALID_DIRECTIONAL_SL",StringFormat("SELL sl=%.2f liveBid=%.2f signalEntry=%.2f",setup.stopLoss,liveEntry,signalEntry));

      double slDistance=MathAbs(liveEntry-setup.stopLoss);
      double slPoints=QXE_PriceToPoints(symbol,slDistance);
      if(slPoints<InpMinStopDistancePoints || slPoints>InpMaxStopDistancePoints)
         return Reject(rp,"SL_DISTANCE_OUT_OF_RANGE",StringFormat("%.0f pts, allowed [%.0f, %.0f]",slPoints,InpMinStopDistancePoints,InpMaxStopDistancePoints));
      double stopsLevel=QXE_StopsLevelPoints(symbol);
      if(stopsLevel>0.0 && slPoints<stopsLevel) return Reject(rp,"SL_BELOW_BROKER_MIN",StringFormat("%.0f pts < min %.0f pts",slPoints,stopsLevel));

      // Optional drift guard: off by default. Always log drift for measurement.
      double atrH1=0.0;
      if(InpMaxEntryDriftATR>0.0 && setup.direction!=SIGNAL_NONE)
        {
         // No market-data dependency inside RiskEngine; caller can keep this guard disabled until drift distribution is measured.
        }

      double riskMultiplier=m_drawdown.RiskMultiplier(currentEquity)*m_weekendGuard.RiskMultiplier(TimeCurrent());
      double effectiveRiskPercent=InpRiskPercent*riskMultiplier;
      double moneyAtRisk=0.0,lossPerLotBroker=0.0,lossPerLotTickModel=0.0;
      double lot=m_sizing.CalculateLot(symbol,currentEquity,effectiveRiskPercent,setup.direction,liveEntry,setup.stopLoss,
                                        moneyAtRisk,lossPerLotBroker,lossPerLotTickModel);
      double riskBudget=currentEquity*(effectiveRiskPercent/100.0);

      g_Logger.Info(StringFormat(
         "[RISK-INTEGRITY] equity=%.2f reqRisk%%=%.4f riskBudget=%.2f signalEntry=%.5f sizingEntry=%.5f entryDrift=%.5f sl=%.5f slDistPrice=%.5f lossPerLotBroker=%.4f lossPerLotTickModel=%.4f normalizedLot=%.4f expectedLossAtNormalizedLot=%.2f",
         currentEquity,effectiveRiskPercent,riskBudget,signalEntry,liveEntry,entryDrift,setup.stopLoss,slDistance,
         lossPerLotBroker,lossPerLotTickModel,lot,moneyAtRisk));

      if(lot<=0.0) return Reject(rp,"LOT_BELOW_MINIMUM","calculated lot rounds to 0 at target risk% (or OrderCalcProfit failed)");

      rp.approved=true; rp.riskPercent=effectiveRiskPercent; rp.riskMultiplier=riskMultiplier;
      rp.slDistancePoints=slPoints; rp.slDistancePrice=slDistance; rp.lossPerLotBroker=lossPerLotBroker;
      rp.lossPerLotTickModel=lossPerLotTickModel; rp.lotSize=lot; rp.moneyAtRisk=moneyAtRisk;
      rp.signalEntryPrice=signalEntry; rp.sizingEntryPrice=liveEntry; rp.entryDriftPrice=entryDrift; rp.riskBudgetMoney=riskBudget;
      m_lastRejectReason=""; return rp;
     }

   int TradesToday(void) const { return m_tradesToday; }
   int ConsecutiveLosses(void) const { return m_consecutiveLosses; }
   double CurrentDrawdownPct(double equity) const { return m_drawdown.CurrentDrawdownPct(equity); }
   bool ShouldForceCloseForWeekend(void) const { return m_weekendGuard.ShouldForceClose(TimeCurrent()); }

   void LogHealthSnapshot(RegimeType currentRegime,double currentEquity) const
     {
      int daysSinceLastTrade=(m_lastTradeOpenTime>0)?(int)((TimeCurrent()-m_lastTradeOpenTime)/86400):-1;
      g_Logger.Info(StringFormat("[HEALTH] DaysSinceLastTrade=%d CurrentRegime=%s DailyHalted=%s ConsecutiveLosses=%d TradesToday=%d DD=%.2f%% DDState=%s LastReject=%s",
         daysSinceLastTrade,QXE_RegimeToString(currentRegime),m_dailyHalted?"true":"false",m_consecutiveLosses,m_tradesToday,
         m_drawdown.CurrentDrawdownPct(currentEquity),m_drawdown.StateToString(m_drawdown.State()),m_lastRejectReason));
     }

private:
   datetime DayAnchor(datetime t) const { MqlDateTime dt; TimeToStruct(t,dt); dt.hour=0;dt.min=0;dt.sec=0; return StructToTime(dt); }
   void ResetRisk(RiskParameters &rp,double equity) const
     {
      rp.approved=false; rp.riskPercent=InpRiskPercent; rp.equity=equity; rp.slDistancePoints=0.0; rp.slDistancePrice=0.0;
      rp.lotSize=0.0; rp.moneyAtRisk=0.0; rp.riskMultiplier=1.0; rp.lossPerLotBroker=0.0; rp.lossPerLotTickModel=0.0;
      rp.signalEntryPrice=0.0; rp.sizingEntryPrice=0.0; rp.entryDriftPrice=0.0; rp.riskBudgetMoney=0.0; rp.rejectReason="";
     }
   RiskParameters Reject(RiskParameters &rp,string code,string detail)
     {
      rp.approved=false; rp.rejectReason=code+": "+detail; m_lastRejectReason=rp.rejectReason;
      g_Logger.Info(StringFormat("[RISK] REJECT %s %s",code,detail)); return rp;
     }

   void PersistDaily(void)
     {
      if(!m_persistenceEnabled) return;
      GlobalVariableSet(m_keyDay,(double)m_currentDayAnchor); GlobalVariableSet(m_keyDayEquity,m_dayStartEquity);
      GlobalVariableSet(m_keyTrades,(double)m_tradesToday); GlobalVariableSet(m_keyConsecutive,(double)m_consecutiveLosses);
      GlobalVariableSet(m_keyHalted,m_dailyHalted?1.0:0.0); GlobalVariableSet(m_keyLastTrade,(double)m_lastTradeOpenTime);
     }
   bool TryLoadDaily(void)
     {
      if(!GlobalVariableCheck(m_keyDay) || !GlobalVariableCheck(m_keyDayEquity) || !GlobalVariableCheck(m_keyTrades) ||
         !GlobalVariableCheck(m_keyConsecutive) || !GlobalVariableCheck(m_keyHalted)) return false;
      m_currentDayAnchor=(datetime)GlobalVariableGet(m_keyDay); m_dayStartEquity=GlobalVariableGet(m_keyDayEquity);
      m_tradesToday=(int)GlobalVariableGet(m_keyTrades); m_consecutiveLosses=(int)GlobalVariableGet(m_keyConsecutive);
      m_dailyHalted=(GlobalVariableGet(m_keyHalted)>0.5);
      if(GlobalVariableCheck(m_keyLastTrade)) m_lastTradeOpenTime=(datetime)GlobalVariableGet(m_keyLastTrade);
      return true;
     }
  };

#endif
