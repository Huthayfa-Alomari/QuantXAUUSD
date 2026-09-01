#ifndef QXE_CONFIG_MQH
#define QXE_CONFIG_MQH

input string InpSectionGeneral="==== GENERAL ====";
input ulong InpMagicNumber=774411;
input bool InpResearchMode=true;
input bool InpOnePositionPerSymbol=true;
input bool InpAllowOppositeReversal=false;

input string InpSectionRegime="==== REGIME ====";
input bool EnableRegimeFilter=true;
input int InpEMA200Period=200;
input int InpEMA50Period=50;
input int InpEMA20Period=20;
input int InpADXPeriod=14;
input double InpADXTrendThreshold=22.0;
input double InpADXRangeThreshold=18.0;
input int InpATRPeriod=14;
input int InpATRPercentileLookback=100;
input double InpVolExpansionPct=0.75;
input double InpVolContractionPct=0.25;
input double InpEMASlopeMinPoints=15.0; // broker points per bar
// Stability thresholds: enter stricter than exit to prevent boundary flapping.
input double InpTrendEnterScore=60.0;
input double InpTrendExitScore=45.0;
input double InpRangeEnterScore=70.0;
input double InpRangeExitScore=55.0;
input double InpVolExpansionExitPct=0.65;
input double InpVolContractionExitPct=0.35;
input int InpRegimeEfficiencyLookback=10;
input double InpRangeEfficiencyMax=0.35;
input double InpTrendEfficiencyMin=0.65;

input string InpSectionToggles="==== STRATEGY TOGGLES ====";
input bool EnableTrend=true;
input bool EnableMomentum=true;
input bool EnableDonchian=true;
input bool EnableBreakout=true;
input bool EnablePullback=true;
input bool EnableMeanReversion=true;
input bool EnableStructure=true;
input bool EnableLiquidity=true;
input bool EnableORB=true;
input bool EnableVWAP=true;
input bool EnableScoreFilter=true;
input bool EnableATRFilter=true;
input bool EnableSessionFilter=true;

input string InpSectionTrend="==== TREND & MOMENTUM ====";
input int InpMomentumLookbackH4=20;
input int InpMomentumLookbackH1=20;
input int InpMomentumLookbackM15=20;
input int InpPullbackSwingLeft=3;
input int InpPullbackSwingRight=3;

input string InpSectionDonchian="==== DONCHIAN / BREAKOUT ====";
input int InpDonchianEntry=20;
input int InpDonchianExit=10;
input double InpVolBreakoutATRRatio=1.3;
input int InpVolBreakoutRangeBars=20;

input string InpSectionMeanRev="==== MEAN REVERSION ====";
input int InpBBPeriod=20;
input double InpBBDeviation=2.0;
input double InpZScoreEntry=2.0;
input int InpZScoreLookback=20;

input string InpSectionVwapOrb="==== VWAP / ORB ====";
input int InpORBMinutes=30;
input int InpORBSessionStartHour=9;
input int InpORBSessionStartMin=0;

input string InpSectionStructure="==== STRUCTURE / LIQUIDITY ====";
input int InpSwingLeft=3;
input int InpSwingRight=3;
input double InpEqualLevelTolPoints=50.0;
input double InpDisplacementBodyRatio=0.6;
input double InpDisplacementATRMult=1.2;
input bool InpRequireDisplacementForSweep=false;

input string InpSectionScoring="==== SCORING ====";
input double InpWeightHTFTrend=20.0;
input double InpWeightMomentum=10.0;
input double InpWeightStructure=15.0;
input double InpWeightLiquidity=15.0;
input double InpWeightDisplacement=10.0;
input double InpWeightFVG=10.0;
input double InpWeightVolatility=10.0;
input double InpWeightSession=5.0;
input double InpWeightEntryQuality=5.0;
input double InpMinScore=70.0;
input double InpSignalDominanceRatio=1.50;
input double InpMaxConfirmationBonus=10.0;
input double InpConfirmationScoreFactor=0.10;

input string InpSectionRisk="==== RISK ====";
input double InpRiskPercent=0.5;
input double InpATRStopMultiplier=1.5;
input double InpMaxStopDistancePoints=6000;
input double InpMinStopDistancePoints=150;
input double InpTP1R=1.0;
input double InpTP2R=2.0;
input double InpTP1Pct=30.0;
input double InpTP2Pct=30.0;

input string InpSectionDaily="==== DAILY RISK / DRAWDOWN ====";
input double InpMaxDailyLossPct=2.0;
input int InpMaxDailyTrades=6;
input int InpMaxConsecutiveLosses=4;
input double InpModerateDDPct=5.0;
input double InpHighDDPct=10.0;
input double InpCriticalDDPct=15.0;
input double InpModerateDDMultiplier=0.75;
input double InpHighDDMultiplier=0.50;

input string InpSectionExec="==== EXECUTION / FILTERS ====";
input double InpMaxSpreadPoints=350;
input double InpMaxSpreadATRRatio=0.35;
input int InpMaxSlippagePoints=100;
input double InpBreakEvenTriggerR=1.0;
input double InpBreakEvenBufferPoints=0.0;
input double InpTrailingATRMultiplier=2.0;
input double InpMinProfitRForTrailing=1.0;
input bool InpEnableNewsFilter=false;
// Diagnostic by default: <=0 disables rejection; drift is still logged.
input double InpMaxEntryDriftATR=0.0;

input string InpSectionSessions="==== SESSIONS (server time) ====";
input int InpAsianStartHour=0;
input int InpAsianEndHour=7;
input int InpLondonStartHour=7;
input int InpLondonEndHour=16;
input int InpNewYorkStartHour=13;
input int InpNewYorkEndHour=22;

input string InpSectionV2="==== ARCHITECTURE V2 ====";
input bool InpEnableEligibilityEngine=true;
input bool InpAllowStandaloneStructureLiquidity=false;
input bool InpEnableInteractionMatrix=true;
// Research-derived eligibility rules: OPT-IN / default OFF.
input bool InpEligibility_TSM_BlockMatureBearSell=false;
input bool InpEligibility_TSM_BlockBreakoutTransitionBuy=false;
input bool InpEligibility_TSM_BlockMatureBullSell=false;

// Wick reversal stays shadow-only unless explicitly enabled.
// Max=8 reproduces the prior v2.1 score cap when enabled.
input bool InpEnableWickScoreBoost=false;
input double InpWickMaxScoreBoost=8.0;
input bool InpInteraction_MomentumStructure_Bonus=false;
input double InpInteraction_MomentumStructure_BonusPts=8.0;
input bool InpInteraction_MomentumVWAP_Penalty=false;
input double InpInteraction_MomentumVWAP_PenaltyPts=-10.0;
input bool InpInteraction_MomentumDonchian_RestrictToExpansion=false;

input string InpSectionRecovery="==== DRAWDOWN RECOVERY STATE MACHINE ====";
input double InpHardKillDDPct=25.0;
input int InpCriticalCooldownDays=5;
input double InpRecoveryRiskMultiplier=0.20;
input double InpRecoveryExitDDPct=10.0;

input string InpSectionWeekend="==== WEEKEND / GAP RISK GUARD ====";
input bool InpEnableWeekendGuard=true;
input int InpFridayNoNewTradesHour=20;
input int InpFridayReduceRiskHour=16;
input double InpFridayRiskMultiplier=0.5;
input bool InpCloseBeforeWeekend=false;
input int InpFridayForceCloseHour=21;

input string InpSectionVisual="==== VISUAL / DEBUG ====";
input bool DrawRegime=true;
input bool DrawStructure=true;
input bool DrawLiquidity=true;
input bool DrawFVG=true;
input bool DrawEntries=true;
input bool DrawStops=true;
input bool DrawTargets=true;
input bool PrintSignals=true;
input bool DebugMode=false;

#endif
