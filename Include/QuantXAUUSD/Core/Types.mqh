//+------------------------------------------------------------------+
//| Types.mqh                                                        |
//| QUANT_XAUUSD_ENGINE - Core Types                                 |
//|                                                                   |
//| All shared enums and structs used across the entire system.      |
//| No trading logic lives here - definitions only.                  |
//+------------------------------------------------------------------+
#ifndef QXE_TYPES_MQH
#define QXE_TYPES_MQH

//====================================================================
// ENUMS
//====================================================================

enum RegimeType
  {
   REGIME_TREND_BULL = 0,
   REGIME_TREND_BEAR = 1,
   REGIME_RANGE = 2,
   REGIME_VOL_EXPANSION = 3,
   REGIME_VOL_CONTRACTION = 4,
   REGIME_TRANSITION = 5,
   REGIME_NO_TRADE = 6
  };

enum StrategyType
  {
   STRAT_TREND_FOLLOWING = 0,
   STRAT_TIME_SERIES_MOMENTUM = 1,
   STRAT_DONCHIAN_BREAKOUT = 2,
   STRAT_VOLATILITY_BREAKOUT = 3,
   STRAT_MOMENTUM_PULLBACK = 4,
   STRAT_MARKET_STRUCTURE = 5,
   STRAT_LIQUIDITY_SWEEP = 6,
   STRAT_MEAN_REVERSION = 7,
   STRAT_BOLLINGER_ZSCORE = 8,
   STRAT_VWAP = 9,
   STRAT_OPENING_RANGE_BREAKOUT = 10,
   STRAT_COUNT = 11 // keep last - used for array sizing
  };

enum SignalDirection
  {
   SIGNAL_NONE = 0,
   SIGNAL_BUY = 1,
   SIGNAL_SELL = -1
  };

enum SignalStrength
  {
   STRENGTH_WEAK = 0,
   STRENGTH_MODERATE = 1,
   STRENGTH_STRONG = 2,
   STRENGTH_EXTREME = 3
  };

enum TradeState
  {
   TRADE_STATE_NONE = 0,
   TRADE_STATE_PENDING = 1,
   TRADE_STATE_OPEN = 2,
   TRADE_STATE_PARTIAL = 3,
   TRADE_STATE_CLOSED = 4
  };

enum ExitReason
  {
   EXIT_NONE = 0,
   EXIT_STOP_LOSS = 1,
   EXIT_TAKE_PROFIT_1 = 2,
   EXIT_TAKE_PROFIT_2 = 3,
   EXIT_RUNNER = 4,
   EXIT_BREAK_EVEN = 5,
   EXIT_TRAILING_STOP = 6,
   EXIT_MANUAL = 7,
   EXIT_OPPOSITE_SIGNAL = 8,
   EXIT_DRAWDOWN_PROTECTION = 9,
   EXIT_DAILY_LIMIT = 10,
   EXIT_STRUCTURE_INVALIDATION = 11
  };

enum SessionType
  {
   SESSION_ASIAN = 0,
   SESSION_LONDON = 1,
   SESSION_NEWYORK = 2,
   SESSION_LONDON_NY_OVERLAP = 3,
   SESSION_OFF = 4
  };

enum SwingType
  {
   SWING_NONE = 0,
   SWING_HIGH = 1,
   SWING_LOW = 2
  };

// Tri-state structural bias. An uninitialized market must never be
// implicitly treated as bullish (repair spec: "INITIAL STRUCTURE BIAS").
enum StructBias
  {
   BIAS_UNKNOWN = 0,
   BIAS_BULLISH = 1,
   BIAS_BEARISH = 2
  };

//====================================================================
// META-REGIME (Architecture v2) - a richer, multi-dimensional
// classification layered ON TOP of the existing RegimeType/RegimeEngine
// (which is preserved unchanged, per spec: "Preserve Existing
// Architecture"). MetaRegimeClassifier consumes MarketState (which
// already carries the base RegimeType) and produces this finer read.
//====================================================================
enum ENUM_META_REGIME
  {
   META_TREND_EXPANSION_BULL = 0,
   META_TREND_EXPANSION_BEAR = 1,
   META_TREND_MATURE_BULL = 2,
   META_TREND_MATURE_BEAR = 3,
   META_RANGE_LOW_VOL = 4,
   META_RANGE_NORMAL_VOL = 5,
   META_HIGH_VOL_CHOP = 6,
   META_BREAKOUT_TRANSITION = 7,
   META_VOL_CONTRACTION = 8,
   META_VOL_EXPANSION = 9,
   META_UNCERTAIN = 10,
   META_REGIME_COUNT = 11 // keep last - used for array sizing
  };

struct MetaRegimeState
  {
   ENUM_META_REGIME  regime;
   int               direction;       // +1 bull, -1 bear, 0 neutral
   double            confidence;      // 0..1
   double            trendStrength;   // 0..100
   double            volatilityScore; // 0..100
   double            efficiencyScore; // 0..1 (range efficiency)
   bool              d1H4Aligned;
  };

// Eligibility decision for one strategy under the current meta-regime.
enum EligibilityDecision
  {
   ELIGIBILITY_ALLOW = 0,
   ELIGIBILITY_CONFIRMATION_ONLY = 1, // may contribute to interaction bonus but not lead a trade alone
   ELIGIBILITY_BLOCK = 2
  };

enum StructureEventType
  {
   STRUCT_NONE = 0,
   STRUCT_HH = 1,
   STRUCT_HL = 2,
   STRUCT_LH = 3,
   STRUCT_LL = 4,
   STRUCT_BOS_BULL = 5,
   STRUCT_BOS_BEAR = 6,
   STRUCT_CHOCH_BULL = 7,
   STRUCT_CHOCH_BEAR = 8
  };

enum LiquidityLevelType
  {
   LIQ_PDH = 0,
   LIQ_PDL = 1,
   LIQ_PWH = 2,
   LIQ_PWL = 3,
   LIQ_SWING_HIGH = 4,
   LIQ_SWING_LOW = 5,
   LIQ_EQUAL_HIGH = 6,
   LIQ_EQUAL_LOW = 7
  };

//====================================================================
// STRUCTS
//====================================================================

// Snapshot of market conditions at the moment of evaluation.
struct MarketState
  {
   datetime          barTime;
   double            close, open, high, low;
   double            atrM5, atrM15, atrH1, atrH4, atrD1;
   double            adxH1, adxH4;
   double            ema20, ema50, ema200;
   double            emaSlope200;
   double            bbUpper, bbMiddle, bbLower;
   double            stdDev;
   double            vwap;
   double            spreadPoints;
   double            atrPercentile;      // 0..1, current ATR rank vs lookback
   SessionType       session;
   RegimeType        regime;
   double            trendScore;
   double            rangeScore;
   double            volatilityScore;
   double            regimeScore;

   // ---- Architecture v2 Market State Engine additions (spec sec. 11) ----
   double            emaSlope20;
   double            emaSlope50;
   int               d1Bias;             // +1/-1/0 vs D1 EMA200
   int               h4Bias;             // +1/-1/0 vs H4 EMA200
   bool              d1H4Aligned;
   double            rangeEfficiency;    // 0..1, |close-open|/(high-low) avg
   double            trendEfficiency;    // 0..1, net displacement / summed range over lookback
   double            distEMA20_ATR;      // (close-EMA20)/ATR
   double            distEMA50_ATR;
   double            distEMA200_ATR;
   double            prevDayRange;
   double            currDayRangeRatio;  // today's range so far / previous day's full range
   int               dayOfWeek;          // 0=Sunday .. 6=Saturday (MqlDateTime convention)
   int               hourOfDay;
   double            spreadATRRatio;
   StructBias        structureBias;
   bool              recentBOS;
   bool              recentCHoCH;
   MetaRegimeState   meta;               // filled by CMetaRegimeClassifier
  };

// A single strategy vote/output.
struct Signal
  {
   StrategyType      strategy;
   SignalDirection   direction;
   double            score;         // 0..100 contribution
   double            confidence;    // 0..1
   double            entry;
   double            stop;
   double            target;
   datetime          timestamp;
   RegimeType        regime;
   string            reason;
  };

// Final aggregated setup ready for risk validation / execution.
struct TradeSetup
  {
   SignalDirection   direction;
   double            rawScore;             // sum before interaction/regime modifiers
   double            interactionModifier;  // from CStrategyInteractionMatrix
   double            compositeScore;       // final score used for InpMinScore gating
   double            entry;
   double            stopLoss;
   double            takeProfit1;
   double            takeProfit2;
   double            runnerTarget;
   RegimeType        regime;
   ENUM_META_REGIME  metaRegime;
   double            metaRegimeConfidence;
   StrategyType      primaryStrategy;      // deterministic: highest-weighted contributor
   string            contributingStrategies;
   string            contributorEligibility; // e.g. "TimeSeriesMomentum:ALLOW|MarketStructure:CONFIRMATION_ONLY"
   int               contributorCount;
   string            interactionReason;    // e.g. "STRUCTURE_CONFIRMATION" / "MOMENTUM_VWAP_PENALTY"
   bool              valid;
   string            rejectReason;
  };

// Computed risk/sizing for a validated setup.
struct RiskParameters
  {
   double            riskPercent;
   double            equity;
   double            slDistancePoints;
   double            slDistancePrice;    // raw price-unit distance, for the audit trail
   double            lotSize;
   double            moneyAtRisk;
   double            riskMultiplier;   // from drawdown control, 0..1
   double            lossPerLotBroker;    // OrderCalcProfit()-based loss for 1.0 lot - the value used for sizing
   double            lossPerLotTickModel; // old tick_size/tick_value formula's result - diagnostic only
   bool              approved;
   string            rejectReason;
  };

// Result of a closed trade, used for research/statistics.
struct TradeResult
  {
   ulong             ticket;
   datetime          openTime;
   datetime          closeTime;
   StrategyType      strategy;
   string            contributingStrategies;
   RegimeType        regime;
   SignalDirection   direction;
   double            entry;
   double            stopLoss;
   double            takeProfit;
   double            lot;
   double            riskMoney;
   double            score;
   double            atrAtEntry;
   double            adxAtEntry;
   double            spreadAtEntry;
   SessionType       session;

   // Risk-integrity audit trail (added to prove/disprove that a
   // configured risk% actually produces the expected loss at SL - a
   // trade risking a nominal 0.5% booked a ~10x larger real loss, so
   // every input to the sizing math is now logged raw, unrounded).
   double            equityAtEntry;
   double            requestedRiskPercent;
   double            slDistancePriceAtEntry;
   double            lossPerLotBrokerAtEntry;    // OrderCalcProfit()-based, the value actually used for sizing
   double            lossPerLotTickModelAtEntry; // old tick_size/tick_value formula's result - diagnostic only
   double            expectedLossAtSL;   // restates riskMoney explicitly for the audit trail

   double            exitPrice;
   double            profit;
   double            rMultiple;
   double            mae;              // max adverse excursion (price units)
   double            mfe;              // max favorable excursion (price units)
   double            maeR;             // MAE expressed in R multiples
   double            mfeR;             // MFE expressed in R multiples
   int               holdingSeconds;
   ExitReason        exitReason;

   // ---- Architecture v2 telemetry additions (spec sec. 14) ----
   MarketState       entryState;         // full point-in-time snapshot at entry (incl. meta-regime)
   RegimeType        regimeAtExit;
   double            rawScore;
   double            interactionModifier;
   int               contributorCount;
   string            interactionReason;
   string            contributorEligibility;
   EligibilityDecision eligibilityDecision;
   string            eligibilityReason;
  };

// Aggregated performance for one strategy (attribution).
struct StrategyResult
  {
   StrategyType      strategy;
   int               trades;
   int               wins;
   int               losses;
   double            grossProfit;
   double            grossLoss;
   double            netProfit;
   double            profitFactor;
   double            expectancyR;
   double            avgR;
   double            maxDrawdown;
  };

#endif // QXE_TYPES_MQH
