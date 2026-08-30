//+------------------------------------------------------------------+
//| Config.mqh                                                       |
//| QUANT_XAUUSD_ENGINE - All configurable inputs                    |
//|                                                                   |
//| Every parameter that influences trading logic is declared here   |
//| as an `input`. Nothing in Strategies/Regime/Risk/etc should ever |
//| hardcode a threshold - it must read from here.                   |
//+------------------------------------------------------------------+
#ifndef QXE_CONFIG_MQH
#define QXE_CONFIG_MQH

//====================== GENERAL ======================
input string   InpSectionGeneral        = "==== GENERAL ====";   // ---
input ulong    InpMagicNumber           = 774411;                 // Magic number (base)
input bool     InpResearchMode          = true;                   // Research mode (log only, no real trades)
input bool     InpOnePositionPerSymbol  = true;                   // Only one net position per symbol
input bool     InpAllowOppositeReversal = false;                  // Allow auto-reverse on opposite signal

//====================== REGIME ======================
input string   InpSectionRegime         = "==== REGIME ====";     // ---
input bool     EnableRegimeFilter       = true;                   // Require regime gating before trading
input int      InpEMA200Period          = 200;                    // EMA200 period (trend baseline)
input int      InpEMA50Period           = 50;                     // EMA50 period
input int      InpEMA20Period           = 20;                     // EMA20 period
input int      InpADXPeriod             = 14;                     // ADX period
input double   InpADXTrendThreshold     = 22.0;                   // ADX above this = trending
input double   InpADXRangeThreshold     = 18.0;                   // ADX below this = ranging
input int      InpATRPeriod             = 14;                     // ATR period (all timeframes)
input int      InpATRPercentileLookback = 100;                    // Bars used to rank current ATR
input double   InpVolExpansionPct       = 0.75;                   // ATR percentile above => expansion
input double   InpVolContractionPct     = 0.25;                   // ATR percentile below => contraction
input double   InpEMASlopeMinPoints     = 15.0;                   // Min EMA200 slope (points/bar*1000) to call it trending

//====================== STRATEGY TOGGLES (ablation) ======================
input string   InpSectionToggles        = "==== STRATEGY TOGGLES ====";  // ---
input bool     EnableTrend              = true;
input bool     EnableMomentum           = true;
input bool     EnableDonchian           = true;
input bool     EnableBreakout           = true;
input bool     EnablePullback           = true;
input bool     EnableMeanReversion      = true;
input bool     EnableStructure          = true;
input bool     EnableLiquidity          = true;
input bool     EnableORB                = true;
input bool     EnableVWAP               = true;
input bool     EnableScoreFilter        = true;
input bool     EnableATRFilter          = true;
input bool     EnableSessionFilter      = true;

//====================== TREND / MOMENTUM ======================
input string   InpSectionTrend          = "==== TREND & MOMENTUM ====";  // ---
input int      InpMomentumLookbackH4    = 20;                     // H4 momentum lookback (bars)
input int      InpMomentumLookbackH1    = 20;                     // H1 momentum lookback (bars)
input int      InpMomentumLookbackM15   = 20;                     // M15 confirmation lookback (bars)
input int      InpPullbackSwingLeft     = 3;                      // Swing detector left bars (pullback)
input int      InpPullbackSwingRight    = 3;                      // Swing detector right bars (pullback)

//====================== DONCHIAN / BREAKOUT ======================
input string   InpSectionDonchian       = "==== DONCHIAN / BREAKOUT ===="; // ---
input int      InpDonchianEntry         = 20;                     // Donchian entry channel period
input int      InpDonchianExit          = 10;                     // Donchian exit channel period
input double   InpVolBreakoutATRRatio   = 1.3;                    // ATR ratio threshold for vol breakout
input int      InpVolBreakoutRangeBars  = 20;                     // Range lookback for breakout level

//====================== MEAN REVERSION ======================
input string   InpSectionMeanRev        = "==== MEAN REVERSION ===="; // ---
input int      InpBBPeriod              = 20;                     // Bollinger period
input double   InpBBDeviation           = 2.0;                    // Bollinger deviation
input double   InpZScoreEntry           = 2.0;                    // |Z| threshold to consider entry
input int      InpZScoreLookback        = 20;                     // Lookback for mean/stddev (Z-score)

//====================== VWAP / ORB ======================
input string   InpSectionVwapOrb        = "==== VWAP / ORB ====";  // ---
input int      InpORBMinutes            = 30;                     // Opening range length in minutes
input int      InpORBSessionStartHour   = 9;                      // ORB session start hour (broker time)
input int      InpORBSessionStartMin    = 0;                      // ORB session start minute

//====================== MARKET STRUCTURE / LIQUIDITY ======================
input string   InpSectionStructure      = "==== STRUCTURE / LIQUIDITY ===="; // ---
input int      InpSwingLeft             = 3;                      // Swing detection: bars to the left
input int      InpSwingRight            = 3;                      // Swing detection: bars to the right
input double   InpEqualLevelTolPoints   = 50.0;                   // Tolerance (points) for equal highs/lows
input double   InpDisplacementBodyRatio = 0.6;                    // Min body/range ratio for displacement
input double   InpDisplacementATRMult   = 1.2;                    // Min candle range vs ATR for displacement
input bool     InpRequireDisplacementForSweep = false;            // Require displacement to confirm sweep

//====================== SCORING ======================
input string   InpSectionScoring        = "==== SCORING ====";     // ---
input double   InpWeightHTFTrend        = 20.0;
input double   InpWeightMomentum        = 10.0;
input double   InpWeightStructure       = 15.0;
input double   InpWeightLiquidity       = 15.0;
input double   InpWeightDisplacement    = 10.0;
input double   InpWeightFVG             = 10.0;
input double   InpWeightVolatility      = 10.0;
input double   InpWeightSession         = 5.0;
input double   InpWeightEntryQuality    = 5.0;
input double   InpMinScore              = 70.0;                   // Minimum composite score to trade

//====================== RISK ======================
input string   InpSectionRisk           = "==== RISK ====";        // ---
input double   InpRiskPercent           = 0.5;                     // % equity risked per trade
input double   InpATRStopMultiplier     = 1.5;                     // ATR multiple for stop distance
input double   InpMaxStopDistancePoints = 6000;                    // Hard cap on SL distance (points)
input double   InpMinStopDistancePoints = 150;                     // Hard floor on SL distance (points)
input double   InpTP1R                  = 1.0;                     // TP1 in R multiples
input double   InpTP2R                  = 2.0;                     // TP2 in R multiples
input double   InpTP1Pct                = 30.0;                    // % of position closed at TP1
input double   InpTP2Pct                = 30.0;                    // % of position closed at TP2
                                                                     // remainder = runner

//====================== DAILY RISK / DRAWDOWN ======================
input string   InpSectionDaily          = "==== DAILY RISK / DRAWDOWN ===="; // ---
input double   InpMaxDailyLossPct       = 2.0;                     // Max daily loss (% starting equity)
input int      InpMaxDailyTrades        = 6;                       // Max trades opened per day
input int      InpMaxConsecutiveLosses  = 4;                       // Max consecutive losses before pause
input double   InpModerateDDPct         = 5.0;                     // Drawdown % -> moderate risk cut
input double   InpHighDDPct             = 10.0;                    // Drawdown % -> high risk cut
input double   InpCriticalDDPct         = 15.0;                    // Drawdown % -> trading halted
input double   InpModerateDDMultiplier  = 0.75;
input double   InpHighDDMultiplier      = 0.50;

//====================== EXECUTION / FILTERS ======================
input string   InpSectionExec           = "==== EXECUTION / FILTERS ===="; // ---
input double   InpMaxSpreadPoints       = 350;                     // Max allowed spread (points)
input double   InpMaxSpreadATRRatio     = 0.35;                    // Max spread as fraction of ATR(M5)
input int      InpMaxSlippagePoints     = 100;                     // Max slippage tolerance (points)
input int      InpBreakEvenTriggerR     = 1;                       // R multiple to trigger break-even
input double   InpTrailingATRMultiplier = 2.0;                     // ATR multiplier for trailing stop
input double   InpMinProfitRForTrailing = 1.0;                     // Min R before trailing starts
input bool     InpEnableNewsFilter      = false;                   // Enable news blackout (interface only, off by default)

//====================== SESSIONS (broker/server time, hour 0-23) ======================
input string   InpSectionSessions       = "==== SESSIONS (server time) ===="; // ---
input int      InpAsianStartHour        = 0;
input int      InpAsianEndHour          = 7;
input int      InpLondonStartHour       = 7;
input int      InpLondonEndHour         = 16;
input int      InpNewYorkStartHour      = 13;
input int      InpNewYorkEndHour        = 22;

//====================== ARCHITECTURE v2: META-REGIME / ELIGIBILITY / INTERACTION ======================
input string   InpSectionV2             = "==== ARCHITECTURE V2 ====";  // ---
input bool     InpEnableEligibilityEngine = true;                  // Enable the finer meta-regime eligibility gate
input bool     InpAllowStandaloneStructureLiquidity = false;        // Let Structure/Liquidity lead a trade alone (else confirmation-only)
input bool     InpEnableInteractionMatrix = true;                   // Enable pairwise interaction scoring

// The following pairwise rules are OPT-IN and default OFF. They encode
// specific multi-year ablation findings (Momentum+Structure looked
// synergistic, Momentum+VWAP looked adverse, Momentum+Donchian looked
// regime-dependent) that were derived from the FULL 2022-2026 sample,
// not from an out-of-sample validation split. Enabling them applies
// them as live scoring rules; leaving them off keeps the engine at its
// pre-v2 neutral (purely additive) scoring behavior. See README.
input bool     InpInteraction_MomentumStructure_Bonus = false;
input double   InpInteraction_MomentumStructure_BonusPts = 8.0;
input bool     InpInteraction_MomentumVWAP_Penalty = false;
input double   InpInteraction_MomentumVWAP_PenaltyPts = -10.0;
input bool     InpInteraction_MomentumDonchian_RestrictToExpansion = false;

//====================== DRAWDOWN RECOVERY STATE MACHINE ======================
input string   InpSectionRecovery       = "==== DRAWDOWN RECOVERY STATE MACHINE ====";  // ---
input double   InpHardKillDDPct         = 25.0;                    // Permanent stop threshold (manual reset required)
input int      InpCriticalCooldownDays  = 5;                       // Trading days blocked after entering CRITICAL_COOLDOWN
input double   InpRecoveryRiskMultiplier = 0.20;                   // Risk multiplier while in RECOVERY
input double   InpRecoveryExitDDPct     = 10.0;                    // Must recover to this DD (or better) to exit RECOVERY

//====================== WEEKEND / GAP RISK GUARD ======================
input string   InpSectionWeekend        = "==== WEEKEND / GAP RISK GUARD ====";  // ---
input bool     InpEnableWeekendGuard    = true;                    // Master switch
input int      InpFridayNoNewTradesHour = 20;                      // Server-time hour (Friday) after which NO new entries
input int      InpFridayReduceRiskHour  = 16;                      // Server-time hour (Friday) after which risk is reduced
input double   InpFridayRiskMultiplier  = 0.5;                     // Risk multiplier during the reduce-risk window
input bool     InpCloseBeforeWeekend    = false;                   // Force-close all positions before the weekend (off by default)
input int      InpFridayForceCloseHour  = 21;                      // Server-time hour to force-close, if enabled

//====================== VISUAL / DEBUG ======================
input string   InpSectionVisual         = "==== VISUAL / DEBUG ===="; // ---
input bool     DrawRegime               = true;
input bool     DrawStructure            = true;
input bool     DrawLiquidity            = true;
input bool     DrawFVG                  = true;
input bool     DrawEntries              = true;
input bool     DrawStops                = true;
input bool     DrawTargets              = true;
input bool     PrintSignals             = true;
input bool     DebugMode                = false;

#endif // QXE_CONFIG_MQH
