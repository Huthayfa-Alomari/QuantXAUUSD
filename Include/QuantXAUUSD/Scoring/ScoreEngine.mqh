#ifndef QXE_SCOREENGINE_MQH
#define QXE_SCOREENGINE_MQH

#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Utilities.mqh"
#include "StrategyInteractionMatrix.mqh"

class CScoreEngine
  {
public:
   TradeSetup Aggregate(const Signal &signals[], const bool &confirmationOnly[], int count,
                        const MarketState &state, CStrategyInteractionMatrix *interactionMatrix)
     {
      TradeSetup setup;
      ResetSetup(setup, state);

      if(state.regime == REGIME_NO_TRADE) { setup.rejectReason="Regime = NO_TRADE"; return setup; }
      if(state.regime == REGIME_TRANSITION) { setup.rejectReason="Regime = TRANSITION (no trade)"; return setup; }

      double buyAllowSum=0.0,sellAllowSum=0.0,buyConfirmSum=0.0,sellConfirmSum=0.0;
      int buyAllowVotes=0,sellAllowVotes=0,buyConfirmVotes=0,sellConfirmVotes=0;
      string buyContributors="",sellContributors="",buyEligibility="",sellEligibility="";
      bool buyPresent[],sellPresent[]; ArrayResize(buyPresent,STRAT_COUNT); ArrayResize(sellPresent,STRAT_COUNT);
      ArrayInitialize(buyPresent,false); ArrayInitialize(sellPresent,false);
      double buyPrimaryWeighted=-1.0,sellPrimaryWeighted=-1.0; int buyPrimaryIdx=-1,sellPrimaryIdx=-1;

      for(int i=0;i<count;i++)
        {
         if(signals[i].direction==SIGNAL_NONE) continue;
         if(!IsEligibleInRegime(signals[i].strategy,state.regime)) continue;
         double weighted=WeightedScore(signals[i]);
         bool isConfirmOnly=confirmationOnly[i];

         if(signals[i].direction==SIGNAL_BUY)
           {
            buyPresent[signals[i].strategy]=true;
            buyContributors+=(buyContributors==""?"":"+")+QXE_StrategyToString(signals[i].strategy);
            buyEligibility+=(buyEligibility==""?"":"|")+QXE_StrategyToString(signals[i].strategy)+":"+(isConfirmOnly?"CONFIRMATION_ONLY":"ALLOW");
            if(isConfirmOnly) { buyConfirmSum+=weighted; buyConfirmVotes++; }
            else { buyAllowSum+=weighted; buyAllowVotes++; if(weighted>buyPrimaryWeighted){buyPrimaryWeighted=weighted;buyPrimaryIdx=i;} }
           }
         else
           {
            sellPresent[signals[i].strategy]=true;
            sellContributors+=(sellContributors==""?"":"+")+QXE_StrategyToString(signals[i].strategy);
            sellEligibility+=(sellEligibility==""?"":"|")+QXE_StrategyToString(signals[i].strategy)+":"+(isConfirmOnly?"CONFIRMATION_ONLY":"ALLOW");
            if(isConfirmOnly) { sellConfirmSum+=weighted; sellConfirmVotes++; }
            else { sellAllowSum+=weighted; sellAllowVotes++; if(weighted>sellPrimaryWeighted){sellPrimaryWeighted=weighted;sellPrimaryIdx=i;} }
           }
        }

      SignalDirection finalDir=SIGNAL_NONE;
      int primaryIdx=-1,allowVotes=0,confirmVotes=0;
      double allowSum=0.0,confirmSum=0.0;
      string contributors="",eligibilityStr="";
      bool present[]; ArrayResize(present,STRAT_COUNT);

      if(buyAllowVotes>0 && sellAllowVotes==0)
        { finalDir=SIGNAL_BUY; primaryIdx=buyPrimaryIdx; allowVotes=buyAllowVotes; confirmVotes=buyConfirmVotes; allowSum=buyAllowSum; confirmSum=buyConfirmSum; contributors=buyContributors; eligibilityStr=buyEligibility; ArrayCopy(present,buyPresent); }
      else if(sellAllowVotes>0 && buyAllowVotes==0)
        { finalDir=SIGNAL_SELL; primaryIdx=sellPrimaryIdx; allowVotes=sellAllowVotes; confirmVotes=sellConfirmVotes; allowSum=sellAllowSum; confirmSum=sellConfirmSum; contributors=sellContributors; eligibilityStr=sellEligibility; ArrayCopy(present,sellPresent); }
      else if(buyAllowVotes>0 && sellAllowVotes>0)
        {
         // Direction dominance is based ONLY on ALLOW-tier evidence.
         double buyAllowAvg=buyAllowSum/buyAllowVotes;
         double sellAllowAvg=sellAllowSum/sellAllowVotes;
         if(buyAllowAvg > sellAllowAvg*InpSignalDominanceRatio)
           { finalDir=SIGNAL_BUY; primaryIdx=buyPrimaryIdx; allowVotes=buyAllowVotes; confirmVotes=buyConfirmVotes; allowSum=buyAllowSum; confirmSum=buyConfirmSum; contributors=buyContributors; eligibilityStr=buyEligibility; ArrayCopy(present,buyPresent); }
         else if(sellAllowAvg > buyAllowAvg*InpSignalDominanceRatio)
           { finalDir=SIGNAL_SELL; primaryIdx=sellPrimaryIdx; allowVotes=sellAllowVotes; confirmVotes=sellConfirmVotes; allowSum=sellAllowSum; confirmSum=sellConfirmSum; contributors=sellContributors; eligibilityStr=sellEligibility; ArrayCopy(present,sellPresent); }
         else { setup.rejectReason="Conflicting ALLOW-tier signals (no clear dominance)"; return setup; }
        }
      else { setup.rejectReason="No qualifying ALLOW-tier signals"; return setup; }

      if(primaryIdx<0) { setup.rejectReason="Internal error: no primary contributor resolved"; return setup; }

      double entry=signals[primaryIdx].entry,stop=signals[primaryIdx].stop,target=signals[primaryIdx].target;
      if(finalDir==SIGNAL_BUY && stop>=entry) { setup.rejectReason=StringFormat("Invalid BUY stop: SL %.2f is not below entry %.2f",stop,entry); return setup; }
      if(finalDir==SIGNAL_SELL && stop<=entry) { setup.rejectReason=StringFormat("Invalid SELL stop: SL %.2f is not above entry %.2f",stop,entry); return setup; }

      bool interactionBlocked=false; string interactionReason=""; double interactionModifier=0.0;
      if(CheckPointer(interactionMatrix)!=POINTER_INVALID)
         interactionModifier=interactionMatrix.Evaluate(present,state.meta,interactionBlocked,interactionReason);
      if(interactionBlocked) { setup.rejectReason="Blocked by Interaction Matrix: "+interactionReason; setup.interactionReason=interactionReason; return setup; }

      double allowAverage=allowSum/allowVotes;
      double confirmationAverage=(confirmVotes>0)?confirmSum/confirmVotes:0.0;
      double confirmationBonus=(confirmVotes>0)?MathMin(InpMaxConfirmationBonus,confirmationAverage*InpConfirmationScoreFactor):0.0;
      double sessionBonus=IsFavorableSession(state.session)?InpWeightSession:0.0;
      double volBonus=(state.regime==REGIME_VOL_EXPANSION)?InpWeightVolatility:InpWeightVolatility*0.5;
      double entryQualityBonus=MathMin(InpWeightEntryQuality,allowVotes*1.5);
      double rawTotal=allowAverage+confirmationBonus+sessionBonus+volBonus+entryQualityBonus;
      double composite=QXE_Clamp(rawTotal+interactionModifier,QXE_SCORE_MIN,QXE_SCORE_MAX);

      setup.direction=finalDir;
      setup.rawScore=rawTotal;
      setup.interactionModifier=interactionModifier;
      setup.interactionReason=interactionReason;
      setup.compositeScore=composite;
      setup.entry=entry; setup.signalEntry=entry; setup.sizingEntry=0.0;
      setup.stopLoss=stop;
      setup.primaryStrategy=signals[primaryIdx].strategy;
      setup.primarySignalScore=signals[primaryIdx].score;
      setup.allowAggregateScore=allowAverage;
      setup.confirmationScore=confirmationAverage;
      setup.confirmationBonus=confirmationBonus;
      setup.sessionBonus=sessionBonus;
      setup.volatilityBonus=volBonus;
      setup.entryQualityBonus=entryQualityBonus;
      setup.primaryEligibilityDecision=ELIGIBILITY_ALLOW;
      setup.primaryEligibilityReason="primary contributor is ALLOW-tier at aggregation";
      setup.contributorCount=allowVotes+confirmVotes;

      double risk=MathAbs(entry-stop);
      setup.takeProfit1=(finalDir==SIGNAL_BUY)?entry+risk*InpTP1R:entry-risk*InpTP1R;
      setup.takeProfit2=(finalDir==SIGNAL_BUY)?entry+risk*InpTP2R:entry-risk*InpTP2R;
      setup.runnerTarget=target;
      setup.contributingStrategies=contributors;
      setup.contributorEligibility=eligibilityStr;

      if(EnableScoreFilter && composite<InpMinScore)
        { setup.valid=false; setup.rejectReason=StringFormat("Composite score %.1f below minimum %.1f",composite,InpMinScore); return setup; }
      setup.valid=true; return setup;
     }

private:
   void ResetSetup(TradeSetup &setup,const MarketState &state) const
     {
      setup.valid=false; setup.direction=SIGNAL_NONE; setup.rawScore=0.0; setup.interactionModifier=0.0; setup.compositeScore=0.0;
      setup.entry=0.0; setup.signalEntry=0.0; setup.sizingEntry=0.0; setup.stopLoss=0.0; setup.takeProfit1=0.0; setup.takeProfit2=0.0; setup.runnerTarget=0.0;
      setup.regime=state.regime; setup.metaRegime=state.meta.regime; setup.metaRegimeConfidence=state.meta.confidence;
      setup.primaryStrategy=STRAT_TREND_FOLLOWING; setup.contributingStrategies=""; setup.contributorEligibility=""; setup.contributorCount=0;
      setup.interactionReason=""; setup.primarySignalScore=0.0; setup.allowAggregateScore=0.0; setup.confirmationScore=0.0; setup.confirmationBonus=0.0;
      setup.sessionBonus=0.0; setup.volatilityBonus=0.0; setup.entryQualityBonus=0.0; setup.primaryEligibilityDecision=ELIGIBILITY_BLOCK; setup.primaryEligibilityReason=""; setup.rejectReason="";
     }

   bool IsEligibleInRegime(StrategyType strat,RegimeType regime) const
     {
      switch(regime)
        {
         case REGIME_TREND_BULL:
         case REGIME_TREND_BEAR:
            return (strat==STRAT_TREND_FOLLOWING || strat==STRAT_TIME_SERIES_MOMENTUM || strat==STRAT_MOMENTUM_PULLBACK || strat==STRAT_MARKET_STRUCTURE || strat==STRAT_LIQUIDITY_SWEEP || strat==STRAT_VWAP);
         case REGIME_RANGE:
            return (strat==STRAT_MEAN_REVERSION || strat==STRAT_BOLLINGER_ZSCORE || strat==STRAT_VWAP);
         case REGIME_VOL_EXPANSION:
            return (strat==STRAT_VOLATILITY_BREAKOUT || strat==STRAT_TIME_SERIES_MOMENTUM || strat==STRAT_DONCHIAN_BREAKOUT || strat==STRAT_OPENING_RANGE_BREAKOUT);
         case REGIME_VOL_CONTRACTION: return false;
         default: return false;
        }
     }

   double WeightedScore(const Signal &s) const { return s.score; }
   bool IsFavorableSession(SessionType s) const { return (s==SESSION_LONDON || s==SESSION_NEWYORK || s==SESSION_LONDON_NY_OVERLAP); }
  };

#endif
