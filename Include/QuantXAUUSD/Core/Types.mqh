#ifndef QXE_TYPES_MQH
#define QXE_TYPES_MQH

enum RegimeType { REGIME_TREND_BULL=0, REGIME_TREND_BEAR=1, REGIME_RANGE=2, REGIME_VOL_EXPANSION=3, REGIME_VOL_CONTRACTION=4, REGIME_TRANSITION=5, REGIME_NO_TRADE=6 };
enum StrategyType { STRAT_TREND_FOLLOWING=0, STRAT_TIME_SERIES_MOMENTUM=1, STRAT_DONCHIAN_BREAKOUT=2, STRAT_VOLATILITY_BREAKOUT=3, STRAT_MOMENTUM_PULLBACK=4, STRAT_MARKET_STRUCTURE=5, STRAT_LIQUIDITY_SWEEP=6, STRAT_MEAN_REVERSION=7, STRAT_BOLLINGER_ZSCORE=8, STRAT_VWAP=9, STRAT_OPENING_RANGE_BREAKOUT=10, STRAT_COUNT=11 };
enum SignalDirection { SIGNAL_NONE=0, SIGNAL_BUY=1, SIGNAL_SELL=-1 };
enum SignalStrength { STRENGTH_WEAK=0, STRENGTH_MODERATE=1, STRENGTH_STRONG=2, STRENGTH_EXTREME=3 };
enum TradeState { TRADE_STATE_NONE=0, TRADE_STATE_PENDING=1, TRADE_STATE_OPEN=2, TRADE_STATE_PARTIAL=3, TRADE_STATE_CLOSED=4 };
enum ExitReason { EXIT_NONE=0, EXIT_STOP_LOSS=1, EXIT_TAKE_PROFIT_1=2, EXIT_TAKE_PROFIT_2=3, EXIT_RUNNER=4, EXIT_BREAK_EVEN=5, EXIT_TRAILING_STOP=6, EXIT_MANUAL=7, EXIT_OPPOSITE_SIGNAL=8, EXIT_DRAWDOWN_PROTECTION=9, EXIT_DAILY_LIMIT=10, EXIT_STRUCTURE_INVALIDATION=11 };
enum SessionType { SESSION_ASIAN=0, SESSION_LONDON=1, SESSION_NEWYORK=2, SESSION_LONDON_NY_OVERLAP=3, SESSION_OFF=4 };
enum SwingType { SWING_NONE=0, SWING_HIGH=1, SWING_LOW=2 };
enum StructBias { BIAS_UNKNOWN=0, BIAS_BULLISH=1, BIAS_BEARISH=2 };

enum ENUM_META_REGIME { META_TREND_EXPANSION_BULL=0, META_TREND_EXPANSION_BEAR=1, META_TREND_MATURE_BULL=2, META_TREND_MATURE_BEAR=3, META_RANGE_LOW_VOL=4, META_RANGE_NORMAL_VOL=5, META_HIGH_VOL_CHOP=6, META_BREAKOUT_TRANSITION=7, META_VOL_CONTRACTION=8, META_VOL_EXPANSION=9, META_UNCERTAIN=10, META_REGIME_COUNT=11 };
struct MetaRegimeState { ENUM_META_REGIME regime; int direction; double confidence; double trendStrength; double volatilityScore; double efficiencyScore; bool d1H4Aligned; };
enum EligibilityDecision { ELIGIBILITY_ALLOW=0, ELIGIBILITY_CONFIRMATION_ONLY=1, ELIGIBILITY_BLOCK=2 };
enum StructureEventType { STRUCT_NONE=0, STRUCT_HH=1, STRUCT_HL=2, STRUCT_LH=3, STRUCT_LL=4, STRUCT_BOS_BULL=5, STRUCT_BOS_BEAR=6, STRUCT_CHOCH_BULL=7, STRUCT_CHOCH_BEAR=8 };
enum LiquidityLevelType { LIQ_PDH=0, LIQ_PDL=1, LIQ_PWH=2, LIQ_PWL=3, LIQ_SWING_HIGH=4, LIQ_SWING_LOW=5, LIQ_EQUAL_HIGH=6, LIQ_EQUAL_LOW=7 };

struct MarketState
  {
   datetime barTime;
   double close,open,high,low;
   double atrM5,atrM15,atrH1,atrH4,atrD1;
   double adxH1,adxH4;
   double plusDIH1,minusDIH1,plusDIH4,minusDIH4;
   double ema20,ema50,ema200;
   double emaSlope200;
   double bbUpper,bbMiddle,bbLower;
   double stdDev,vwap,spreadPoints,atrPercentile;
   SessionType session;
   RegimeType regime;
   RegimeType rawRegime;
   RegimeType stableRegime;
   double trendScore,rangeScore,volatilityScore,regimeScore;
   double emaSlope20,emaSlope50;
   int d1Bias,h4Bias;
   bool d1H4Aligned;
   double rangeEfficiency,trendEfficiency;
   double distEMA20_ATR,distEMA50_ATR,distEMA200_ATR;
   double prevDayRange,currDayRangeRatio;
   int dayOfWeek,hourOfDay;
   double spreadATRRatio;
   StructBias structureBias;
   bool recentBOS,recentCHoCH;
   MetaRegimeState meta;
  };

struct Signal
  {
   StrategyType strategy;
   SignalDirection direction;
   double score,confidence,entry,stop,target;
   datetime timestamp;
   RegimeType regime;
   string reason;
  };

struct TradeSetup
  {
   SignalDirection direction;
   double rawScore,interactionModifier,compositeScore;
   // Execution truth: entry remains signal entry for compatibility.
   double entry;
   double signalEntry;
   double sizingEntry;
   double stopLoss,takeProfit1,takeProfit2,runnerTarget;
   RegimeType regime;
   ENUM_META_REGIME metaRegime;
   double metaRegimeConfidence;
   StrategyType primaryStrategy;
   string contributingStrategies;
   string contributorEligibility;
   int contributorCount;
   string interactionReason;
   // Score decomposition for research integrity.
   double primarySignalScore;
   double allowAggregateScore;
   double confirmationScore;
   double confirmationBonus;
   double sessionBonus;
   double volatilityBonus;
   double entryQualityBonus;
   EligibilityDecision primaryEligibilityDecision;
   string primaryEligibilityReason;
   bool valid;
   string rejectReason;
  };

struct RiskParameters
  {
   double riskPercent,equity,slDistancePoints,slDistancePrice,lotSize,moneyAtRisk,riskMultiplier;
   double lossPerLotBroker,lossPerLotTickModel;
   double signalEntryPrice;
   double sizingEntryPrice;
   double entryDriftPrice;
   double riskBudgetMoney;
   bool approved;
   string rejectReason;
  };

struct TradeResult
  {
   // ticket retained for compatibility; new code should prefer positionTicket / positionIdentifier.
   ulong ticket;
   ulong positionTicket;
   ulong positionIdentifier;
   ulong entryOrderTicket;
   ulong entryDealTicket;
   datetime openTime,closeTime;
   StrategyType strategy;
   string contributingStrategies;
   RegimeType regime;
   SignalDirection direction;
   double entry,stopLoss,takeProfit,lot,riskMoney,score,atrAtEntry,adxAtEntry,spreadAtEntry;
   SessionType session;
   double equityAtEntry,requestedRiskPercent,slDistancePriceAtEntry,lossPerLotBrokerAtEntry,lossPerLotTickModelAtEntry,expectedLossAtSL;
   double signalEntry,sizingEntry,fillEntry;
   double signalToSizingDrift,sizingToFillSlippage,totalEntryDrift;
   double riskBudgetMoney;
   double exitPrice;
   double grossProfit,commission,swap,fees,netProfit;
   double profit; // compatibility alias: should equal netProfit
   double rMultiple,mae,mfe,maeR,mfeR;
   int holdingSeconds;
   ExitReason exitReason;
   long brokerExitReason;
   MarketState entryState;
   RegimeType regimeAtExit;
   double rawScore,interactionModifier;
   double primarySignalScore,allowAggregateScore,confirmationScore,confirmationBonus,sessionBonus,volatilityBonus,entryQualityBonus;
   int contributorCount;
   string interactionReason,contributorEligibility;
   EligibilityDecision eligibilityDecision;
   string eligibilityReason;
  };

struct StrategyResult
  {
   StrategyType strategy;
   int trades,wins,losses,breakevens;
   double grossProfit,grossLoss,netProfit,profitFactor,expectancyR,avgR,maxDrawdown;
  };

#endif
