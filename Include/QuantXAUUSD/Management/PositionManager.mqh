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
   ulong positionTicket;
   ulong positionIdentifier;
   datetime openTime;
   SignalDirection direction;
   RegimeType regime;
   StrategyType primaryStrategy;
   string contributingStrategies;
   string contributorEligibility;
   double signalEntryPrice,sizingEntryPrice,entryPrice;
   double initialStop,currentStopPrice,takeProfit1,takeProfit2;
   double initialRiskDistance,initialRiskMoney,initialVolume;
   double entryATR,entryADX,entrySpread,entryScore;
   MarketState entryState;
   double rawScore,interactionModifier;
   double primarySignalScore,allowAggregateScore,confirmationScore,confirmationBonus,sessionBonus,volatilityBonus,entryQualityBonus;
   int contributorCount;
   string interactionReason;
   EligibilityDecision primaryEligibilityDecision;
   string primaryEligibilityReason;
   double equityAtEntry,requestedRiskPercent,lossPerLotBrokerAtEntry,lossPerLotTickModelAtEntry,riskBudgetMoney;
   double realizedProfit,closedVolume;
   double highestPriceSeen,lowestPriceSeen,mae,mfe;
   bool tp1Taken,tp2Taken,breakEvenApplied;
   ExitReason pendingExitReason;
   bool recovered;
   bool active;
  };

class CPositionManager
  {
private:
   CTradeExecutor *m_executor;
   CRiskEngine *m_risk;
   PositionContext m_contexts[];

public:
   void Init(CTradeExecutor *executor,CRiskEngine *risk)
     { m_executor=executor; m_risk=risk; ArrayResize(m_contexts,0); }

   void RecoverOpenPositions(string symbol,ulong magic)
     {
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong ticket=PositionGetTicket(i); if(ticket==0) continue;
         if(PositionGetString(POSITION_SYMBOL)!=symbol) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC)!=magic) continue;
         ulong identifier=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
         if(FindByIdentifier(identifier)>=0) continue;

         PositionContext ctx; ResetContext(ctx);
         ctx.positionTicket=ticket; ctx.positionIdentifier=identifier;
         ctx.openTime=(datetime)PositionGetInteger(POSITION_TIME);
         ctx.direction=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?SIGNAL_BUY:SIGNAL_SELL;
         ctx.entryPrice=PositionGetDouble(POSITION_PRICE_OPEN);
         ctx.signalEntryPrice=ctx.entryPrice; ctx.sizingEntryPrice=ctx.entryPrice;
         ctx.currentStopPrice=PositionGetDouble(POSITION_SL);
         ctx.initialStop=ctx.currentStopPrice;
         ctx.takeProfit2=PositionGetDouble(POSITION_TP);
         ctx.initialVolume=PositionGetDouble(POSITION_VOLUME);
         ctx.highestPriceSeen=ctx.entryPrice; ctx.lowestPriceSeen=ctx.entryPrice;
         ctx.primaryStrategy=STRAT_TREND_FOLLOWING;
         ctx.contributingStrategies="RECOVERED_AFTER_RESTART";
         ctx.contributorEligibility="RECOVERED";
         ctx.recovered=true; ctx.active=true;

         // Recover original opening SL/TP and volume when broker history exposes them.
         if(identifier>0 && HistorySelectByPosition(identifier))
           {
            double inVol=0.0;
            for(int d=0;d<HistoryDealsTotal();d++)
              {
               ulong deal=HistoryDealGetTicket(d); if(deal==0) continue;
               long et=HistoryDealGetInteger(deal,DEAL_ENTRY);
               if(et==DEAL_ENTRY_IN || et==DEAL_ENTRY_INOUT)
                 {
                  inVol+=HistoryDealGetDouble(deal,DEAL_VOLUME);
                  double dsl=HistoryDealGetDouble(deal,DEAL_SL);
                  double dtp=HistoryDealGetDouble(deal,DEAL_TP);
                  if(dsl>0.0) ctx.initialStop=dsl;
                  if(dtp>0.0 && ctx.takeProfit2<=0.0) ctx.takeProfit2=dtp;
                 }
              }
            if(inVol>0.0) ctx.initialVolume=inVol;
           }
         ctx.initialRiskDistance=MathAbs(ctx.entryPrice-ctx.initialStop);
         AppendContext(ctx);
         g_Logger.Warn(StringFormat("[POSITION-RECOVERY] ticket=%I64u identifier=%I64u entry=%.5f initialSL=%.5f volume=%.4f attribution=RECOVERED_AFTER_RESTART",
            ticket,identifier,ctx.entryPrice,ctx.initialStop,ctx.initialVolume));
        }
     }

   void RegisterOpen(ulong ticket,const TradeSetup &setup,const RiskParameters &risk,
                     double entryATR,double entryADX,double entrySpread,const MarketState &entryState)
     {
      if(!PositionSelectByTicket(ticket))
        { g_Logger.Error(StringFormat("RegisterOpen: position ticket %I64u not selectable",ticket)); return; }
      PositionContext ctx; ResetContext(ctx);
      ctx.positionTicket=ticket;
      ctx.positionIdentifier=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      ctx.openTime=(datetime)PositionGetInteger(POSITION_TIME);
      ctx.direction=setup.direction; ctx.regime=setup.regime; ctx.primaryStrategy=setup.primaryStrategy;
      ctx.contributingStrategies=setup.contributingStrategies; ctx.contributorEligibility=setup.contributorEligibility;
      ctx.signalEntryPrice=(risk.signalEntryPrice>0.0)?risk.signalEntryPrice:setup.entry;
      ctx.sizingEntryPrice=(risk.sizingEntryPrice>0.0)?risk.sizingEntryPrice:ctx.signalEntryPrice;
      ctx.entryPrice=PositionGetDouble(POSITION_PRICE_OPEN);
      ctx.initialStop=setup.stopLoss; ctx.currentStopPrice=setup.stopLoss;
      ctx.takeProfit1=setup.takeProfit1; ctx.takeProfit2=setup.takeProfit2;
      ctx.initialRiskDistance=MathAbs(ctx.entryPrice-ctx.initialStop);
      ctx.initialRiskMoney=risk.moneyAtRisk; ctx.initialVolume=PositionGetDouble(POSITION_VOLUME);
      ctx.entryATR=entryATR; ctx.entryADX=entryADX; ctx.entrySpread=entrySpread; ctx.entryScore=setup.compositeScore;
      ctx.entryState=entryState; ctx.rawScore=setup.rawScore; ctx.interactionModifier=setup.interactionModifier;
      ctx.primarySignalScore=setup.primarySignalScore; ctx.allowAggregateScore=setup.allowAggregateScore; ctx.confirmationScore=setup.confirmationScore;
      ctx.confirmationBonus=setup.confirmationBonus; ctx.sessionBonus=setup.sessionBonus; ctx.volatilityBonus=setup.volatilityBonus; ctx.entryQualityBonus=setup.entryQualityBonus;
      ctx.contributorCount=setup.contributorCount; ctx.interactionReason=setup.interactionReason;
      ctx.primaryEligibilityDecision=setup.primaryEligibilityDecision; ctx.primaryEligibilityReason=setup.primaryEligibilityReason;
      ctx.equityAtEntry=risk.equity; ctx.requestedRiskPercent=risk.riskPercent;
      ctx.lossPerLotBrokerAtEntry=risk.lossPerLotBroker; ctx.lossPerLotTickModelAtEntry=risk.lossPerLotTickModel; ctx.riskBudgetMoney=risk.riskBudgetMoney;
      ctx.highestPriceSeen=ctx.entryPrice; ctx.lowestPriceSeen=ctx.entryPrice; ctx.active=true;
      AppendContext(ctx); m_risk.RegisterTradeOpened();
     }

   void TagPendingExit(ulong ticket,ExitReason reason)
     { int idx=FindByTicket(ticket); if(idx>=0) m_contexts[idx].pendingExitReason=reason; }

   void ManageAll(string symbol,double atrH1)
     {
      for(int i=ArraySize(m_contexts)-1;i>=0;i--)
        {
         if(!m_contexts[i].active) continue;
         if(!RefreshTicketByIdentifier(m_contexts[i])) continue;
         if(!PositionSelectByTicket(m_contexts[i].positionTicket)) continue;
         UpdateExcursion(m_contexts[i],symbol);
         ManageOne(m_contexts[i],symbol,atrH1);
        }
     }

   bool ProcessDeal(ulong positionIdentifier,double dealVolume,double dealProfit,double dealPrice,datetime dealTime,
                    bool positionStillOpen,RegimeType regimeAtExit,TradeResult &outResult)
     {
      int idx=FindByIdentifier(positionIdentifier); if(idx<0) return false;
      m_contexts[idx].realizedProfit+=dealProfit; m_contexts[idx].closedVolume+=dealVolume;
      if(positionStillOpen) { RefreshTicketByIdentifier(m_contexts[idx]); return false; }
      outResult=BuildFinalResult(m_contexts[idx],dealPrice,dealTime,regimeAtExit);
      AggregateHistory(positionIdentifier,outResult);
      m_risk.RegisterTradeClosed(outResult.profit);
      RemoveContext(idx); return true;
     }

   int Count(void) const { return ArraySize(m_contexts); }

private:
   void ResetContext(PositionContext &c)
     {
      c.positionTicket=0;c.positionIdentifier=0;c.openTime=0;c.direction=SIGNAL_NONE;c.regime=REGIME_NO_TRADE;c.primaryStrategy=STRAT_TREND_FOLLOWING;
      c.contributingStrategies="";c.contributorEligibility="";c.signalEntryPrice=0;c.sizingEntryPrice=0;c.entryPrice=0;c.initialStop=0;c.currentStopPrice=0;c.takeProfit1=0;c.takeProfit2=0;
      c.initialRiskDistance=0;c.initialRiskMoney=0;c.initialVolume=0;c.entryATR=0;c.entryADX=0;c.entrySpread=0;c.entryScore=0;c.rawScore=0;c.interactionModifier=0;
      c.primarySignalScore=0;c.allowAggregateScore=0;c.confirmationScore=0;c.confirmationBonus=0;c.sessionBonus=0;c.volatilityBonus=0;c.entryQualityBonus=0;c.contributorCount=0;c.interactionReason="";
      c.primaryEligibilityDecision=ELIGIBILITY_ALLOW;c.primaryEligibilityReason="";c.equityAtEntry=0;c.requestedRiskPercent=0;c.lossPerLotBrokerAtEntry=0;c.lossPerLotTickModelAtEntry=0;c.riskBudgetMoney=0;
      c.realizedProfit=0;c.closedVolume=0;c.highestPriceSeen=0;c.lowestPriceSeen=0;c.mae=0;c.mfe=0;c.tp1Taken=false;c.tp2Taken=false;c.breakEvenApplied=false;c.pendingExitReason=EXIT_NONE;c.recovered=false;c.active=false;
     }
   void AppendContext(const PositionContext &ctx) { int n=ArraySize(m_contexts);ArrayResize(m_contexts,n+1);m_contexts[n]=ctx; }
   int FindByTicket(ulong ticket) const { for(int i=0;i<ArraySize(m_contexts);i++) if(m_contexts[i].active && m_contexts[i].positionTicket==ticket) return i; return -1; }
   int FindByIdentifier(ulong id) const { for(int i=0;i<ArraySize(m_contexts);i++) if(m_contexts[i].active && m_contexts[i].positionIdentifier==id) return i; return -1; }

   bool RefreshTicketByIdentifier(PositionContext &ctx)
     {
      if(ctx.positionTicket>0 && PositionSelectByTicket(ctx.positionTicket) && (ulong)PositionGetInteger(POSITION_IDENTIFIER)==ctx.positionIdentifier) return true;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong t=PositionGetTicket(i); if(t==0) continue;
         if((ulong)PositionGetInteger(POSITION_IDENTIFIER)==ctx.positionIdentifier) { ctx.positionTicket=t; return true; }
        }
      return false;
     }

   void UpdateExcursion(PositionContext &ctx,string symbol)
     {
      double bid=SymbolInfoDouble(symbol,SYMBOL_BID),ask=SymbolInfoDouble(symbol,SYMBOL_ASK);
      double currentPrice=(ctx.direction==SIGNAL_BUY)?bid:ask;
      if(currentPrice>ctx.highestPriceSeen)ctx.highestPriceSeen=currentPrice;
      if(currentPrice<ctx.lowestPriceSeen)ctx.lowestPriceSeen=currentPrice;
      double adverse=0,favorable=0;
      if(ctx.direction==SIGNAL_BUY){adverse=ctx.entryPrice-ctx.lowestPriceSeen;favorable=ctx.highestPriceSeen-ctx.entryPrice;}
      else {adverse=ctx.highestPriceSeen-ctx.entryPrice;favorable=ctx.entryPrice-ctx.lowestPriceSeen;}
      ctx.mae=MathMax(ctx.mae,adverse);ctx.mfe=MathMax(ctx.mfe,favorable);
     }

   void ManageOne(PositionContext &ctx,string symbol,double atrH1)
     {
      double currentPrice=(ctx.direction==SIGNAL_BUY)?SymbolInfoDouble(symbol,SYMBOL_BID):SymbolInfoDouble(symbol,SYMBOL_ASK);
      if(ctx.initialRiskDistance<=QXE_EPS) return;
      double profitDistance=(ctx.direction==SIGNAL_BUY)?currentPrice-ctx.entryPrice:ctx.entryPrice-currentPrice;
      double rMultiple=profitDistance/ctx.initialRiskDistance;
      double positionVolume=PositionGetDouble(POSITION_VOLUME),volMin=QXE_VolumeMin(symbol);

      if(!ctx.tp1Taken && rMultiple>=InpTP1R)
        {
         double requested=ctx.initialVolume*(InpTP1Pct/100.0);
         int res=ExecuteSafePartial(ctx,requested,positionVolume,volMin,symbol);
         if(res!=0) ctx.tp1Taken=true;
         if(res==2) return;
        }
      else if(ctx.tp1Taken && !ctx.tp2Taken && rMultiple>=InpTP2R)
        {
         double requested=ctx.initialVolume*(InpTP2Pct/100.0);
         requested=MathMin(requested,PositionGetDouble(POSITION_VOLUME));
         int res=ExecuteSafePartial(ctx,requested,PositionGetDouble(POSITION_VOLUME),volMin,symbol);
         if(res!=0) ctx.tp2Taken=true;
         if(res==2) return;
        }

      if(!ctx.breakEvenApplied && rMultiple>=InpBreakEvenTriggerR)
        {
         double point=QXE_SymbolPoint(symbol);
         double buffer=InpBreakEvenBufferPoints*point;
         double newStop=(ctx.direction==SIGNAL_BUY)?ctx.entryPrice+buffer:ctx.entryPrice-buffer;
         double currentTp=PositionGetDouble(POSITION_TP);
         if(m_executor.ModifyStops(ctx.positionTicket,newStop,currentTp)) {ctx.breakEvenApplied=true;ctx.currentStopPrice=newStop;}
        }

      // Avoid BE and trailing competing on the exact same trigger tick.
      if(rMultiple>InpMinProfitRForTrailing && atrH1>QXE_EPS)
        {
         double currentStop=PositionGetDouble(POSITION_SL),trailDistance=atrH1*InpTrailingATRMultiplier;
         double candidate=(ctx.direction==SIGNAL_BUY)?currentPrice-trailDistance:currentPrice+trailDistance;
         bool improves=(ctx.direction==SIGNAL_BUY)?candidate>currentStop:(candidate<currentStop || currentStop<=0.0);
         if(improves && m_executor.ModifyStops(ctx.positionTicket,candidate,PositionGetDouble(POSITION_TP))) ctx.currentStopPrice=candidate;
        }
     }

   // 0=failed/skipped, 1=partial executed, 2=full close issued.
   int ExecuteSafePartial(PositionContext &ctx,double requested,double positionVolume,double volMin,string symbol)
     {
      double floored=QXE_NormalizeVolume(symbol,requested); if(floored<=0.0) return 0;
      double remainder=positionVolume-floored;
      if(remainder>QXE_EPS && remainder<volMin) return m_executor.CloseFull(ctx.positionTicket)?2:0;
      return m_executor.ClosePartial(ctx.positionTicket,floored)?1:0;
     }

   TradeResult BuildFinalResult(const PositionContext &ctx,double exitPrice,datetime exitTime,RegimeType regimeAtExit)
     {
      TradeResult tr;
      tr.ticket=ctx.positionTicket;tr.positionTicket=ctx.positionTicket;tr.positionIdentifier=ctx.positionIdentifier;tr.entryOrderTicket=0;tr.entryDealTicket=0;
      tr.openTime=ctx.openTime;tr.closeTime=exitTime;tr.strategy=ctx.primaryStrategy;tr.contributingStrategies=ctx.contributingStrategies;tr.regime=ctx.regime;tr.direction=ctx.direction;
      tr.entry=ctx.entryPrice;tr.signalEntry=ctx.signalEntryPrice;tr.sizingEntry=ctx.sizingEntryPrice;tr.fillEntry=ctx.entryPrice;
      tr.signalToSizingDrift=MathAbs(ctx.sizingEntryPrice-ctx.signalEntryPrice);tr.sizingToFillSlippage=MathAbs(ctx.entryPrice-ctx.sizingEntryPrice);tr.totalEntryDrift=MathAbs(ctx.entryPrice-ctx.signalEntryPrice);
      tr.stopLoss=ctx.initialStop;tr.takeProfit=ctx.takeProfit2;tr.lot=ctx.initialVolume;tr.riskMoney=ctx.initialRiskMoney;tr.riskBudgetMoney=ctx.riskBudgetMoney;tr.score=ctx.entryScore;
      tr.atrAtEntry=ctx.entryATR;tr.adxAtEntry=ctx.entryADX;tr.spreadAtEntry=ctx.entrySpread;tr.session=ctx.entryState.session;
      tr.equityAtEntry=ctx.equityAtEntry;tr.requestedRiskPercent=ctx.requestedRiskPercent;tr.slDistancePriceAtEntry=ctx.initialRiskDistance;
      tr.lossPerLotBrokerAtEntry=ctx.lossPerLotBrokerAtEntry;tr.lossPerLotTickModelAtEntry=ctx.lossPerLotTickModelAtEntry;tr.expectedLossAtSL=ctx.initialRiskMoney;
      tr.exitPrice=exitPrice;tr.grossProfit=0;tr.commission=0;tr.swap=0;tr.fees=0;tr.netProfit=ctx.realizedProfit;tr.profit=ctx.realizedProfit;
      tr.rMultiple=(ctx.initialRiskMoney>QXE_EPS)?tr.profit/ctx.initialRiskMoney:0.0;
      tr.mae=ctx.mae;tr.mfe=ctx.mfe;tr.maeR=(ctx.initialRiskDistance>QXE_EPS)?-(ctx.mae/ctx.initialRiskDistance):0.0;tr.mfeR=(ctx.initialRiskDistance>QXE_EPS)?ctx.mfe/ctx.initialRiskDistance:0.0;
      tr.holdingSeconds=(int)(exitTime-ctx.openTime);tr.exitReason=InferExitReason(ctx,exitPrice);tr.brokerExitReason=0;
      tr.entryState=ctx.entryState;tr.regimeAtExit=regimeAtExit;tr.rawScore=ctx.rawScore;tr.interactionModifier=ctx.interactionModifier;
      tr.primarySignalScore=ctx.primarySignalScore;tr.allowAggregateScore=ctx.allowAggregateScore;tr.confirmationScore=ctx.confirmationScore;tr.confirmationBonus=ctx.confirmationBonus;
      tr.sessionBonus=ctx.sessionBonus;tr.volatilityBonus=ctx.volatilityBonus;tr.entryQualityBonus=ctx.entryQualityBonus;
      tr.contributorCount=ctx.contributorCount;tr.interactionReason=ctx.interactionReason;tr.contributorEligibility=ctx.contributorEligibility;
      tr.eligibilityDecision=ctx.primaryEligibilityDecision;tr.eligibilityReason=ctx.primaryEligibilityReason;
      return tr;
     }

   void AggregateHistory(ulong identifier,TradeResult &tr)
     {
      if(identifier==0 || !HistorySelectByPosition(identifier)) return;
      double gp=0,comm=0,sw=0,fee=0; datetime latest=0;
      for(int i=0;i<HistoryDealsTotal();i++)
        {
         ulong d=HistoryDealGetTicket(i);if(d==0)continue;
         gp+=HistoryDealGetDouble(d,DEAL_PROFIT);comm+=HistoryDealGetDouble(d,DEAL_COMMISSION);sw+=HistoryDealGetDouble(d,DEAL_SWAP);fee+=HistoryDealGetDouble(d,DEAL_FEE);
         long et=HistoryDealGetInteger(d,DEAL_ENTRY);datetime tm=(datetime)HistoryDealGetInteger(d,DEAL_TIME);
         if((et==DEAL_ENTRY_OUT || et==DEAL_ENTRY_OUT_BY) && tm>=latest){latest=tm;tr.brokerExitReason=HistoryDealGetInteger(d,DEAL_REASON);tr.exitPrice=HistoryDealGetDouble(d,DEAL_PRICE);}
         if((et==DEAL_ENTRY_IN || et==DEAL_ENTRY_INOUT) && tr.entryDealTicket==0) tr.entryDealTicket=d;
        }
      tr.grossProfit=gp;tr.commission=comm;tr.swap=sw;tr.fees=fee;tr.netProfit=gp+comm+sw+fee;tr.profit=tr.netProfit;
      tr.rMultiple=(tr.riskMoney>QXE_EPS)?tr.netProfit/tr.riskMoney:0.0;
      if(tr.exitReason==EXIT_STOP_LOSS && tr.riskMoney>QXE_EPS)
        {
         double deviation=MathAbs(tr.rMultiple+1.0);
         if(deviation>0.60) g_Logger.Error(StringFormat("[RISK VIOLATION] identifier=%I64u expected~-1R actual=%.2fR net=%.2f",identifier,tr.rMultiple,tr.netProfit));
         else if(deviation>0.30) g_Logger.Warn(StringFormat("[RISK WARNING] identifier=%I64u expected~-1R actual=%.2fR net=%.2f",identifier,tr.rMultiple,tr.netProfit));
        }
     }

   ExitReason InferExitReason(const PositionContext &ctx,double exitPrice) const
     {
      if(ctx.pendingExitReason!=EXIT_NONE)return ctx.pendingExitReason;
      double tol=MathMax(ctx.initialRiskDistance*0.05,QXE_EPS*10.0);
      if(ctx.breakEvenApplied && MathAbs(exitPrice-ctx.currentStopPrice)<=tol) return EXIT_BREAK_EVEN;
      if(MathAbs(exitPrice-ctx.currentStopPrice)<=tol && MathAbs(ctx.currentStopPrice-ctx.initialStop)>QXE_EPS) return EXIT_TRAILING_STOP;
      if(MathAbs(exitPrice-ctx.initialStop)<=tol)return EXIT_STOP_LOSS;
      if(MathAbs(exitPrice-ctx.takeProfit2)<=tol)return ctx.tp2Taken?EXIT_RUNNER:EXIT_TAKE_PROFIT_2;
      if(MathAbs(exitPrice-ctx.takeProfit1)<=tol)return EXIT_TAKE_PROFIT_1;
      return EXIT_MANUAL;
     }

   void RemoveContext(int index){int n=ArraySize(m_contexts);for(int i=index;i<n-1;i++)m_contexts[i]=m_contexts[i+1];ArrayResize(m_contexts,n-1);}
  };

#endif
