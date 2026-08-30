//+------------------------------------------------------------------+
//| Utilities.mqh                                                    |
//| QUANT_XAUUSD_ENGINE - Shared helper functions                    |
//+------------------------------------------------------------------+
#ifndef QXE_UTILITIES_MQH
#define QXE_UTILITIES_MQH

#include "Types.mqh"
#include "Config.mqh"
#include "Constants.mqh"

//--------------------------------------------------------------------
// Symbol / broker normalization helpers.
// Never assume fixed digits, point size, or suffix/prefix.
//--------------------------------------------------------------------
double QXE_SymbolPoint(string symbol)     { return SymbolInfoDouble(symbol, SYMBOL_POINT); }
int    QXE_SymbolDigits(string symbol)    { return (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS); }
double QXE_TickSize(string symbol)        { return SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE); }
double QXE_TickValue(string symbol)       { return SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE); }
double QXE_VolumeMin(string symbol)       { return SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN); }
double QXE_VolumeMax(string symbol)       { return SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX); }
double QXE_VolumeStep(string symbol)      { return SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP); }
double QXE_StopsLevelPoints(string symbol){ return (double)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL); }

// Converts a raw price distance to broker points for this symbol.
double QXE_PriceToPoints(string symbol, double priceDistance)
  {
   double point = QXE_SymbolPoint(symbol);
   if(point <= 0.0)
      return 0.0;
   return priceDistance / point;
  }

double QXE_PointsToPrice(string symbol, double points)
  {
   return points * QXE_SymbolPoint(symbol);
  }

// Normalizes a price to the symbol's tick size / digits.
double QXE_NormalizePrice(string symbol, double price)
  {
   double tickSize = QXE_TickSize(symbol);
   if(tickSize > 0.0)
      price = MathRound(price / tickSize) * tickSize;
   int digits = QXE_SymbolDigits(symbol);
   return NormalizeDouble(price, digits);
  }

// Normalizes a volume (lot) to the symbol's step / min / max, ROUNDING
// DOWN only. Never rounds a below-minimum volume UP to the minimum -
// that would silently increase risk beyond what was calculated
// (repair spec: "CRITICAL RISK BUG - MINIMUM LOT"). Returns 0.0 when
// the volume cannot be represented at or above the broker minimum;
// callers MUST treat 0.0 as "cannot trade / cannot close this size",
// never as "use the minimum anyway".
double QXE_NormalizeVolume(string symbol, double volume)
  {
   double step = QXE_VolumeStep(symbol);
   double vmin = QXE_VolumeMin(symbol);
   double vmax = QXE_VolumeMax(symbol);

   if(step <= 0.0)
      step = 0.01;
   if(volume <= 0.0)
      return 0.0;

   double normalized = MathFloor(volume / step + 1e-8) * step;

   if(normalized < vmin - QXE_EPS)
      return 0.0; // reject - never inflate risk to satisfy a minimum

   if(normalized > vmax)
      normalized = vmax; // capping DOWN to max is safe (reduces risk)

   int stepDigits = 0;
   double tmp = step;
   while(tmp < 1.0 && stepDigits < 8) { tmp *= 10.0; stepDigits++; }

   return NormalizeDouble(normalized, stepDigits);
  }

//--------------------------------------------------------------------
// New-bar detection (per timeframe). Signal generation must only run
// on a freshly closed candle - never on the current forming candle.
//--------------------------------------------------------------------
bool QXE_IsNewBar(string symbol, ENUM_TIMEFRAMES tf, datetime &lastBarTime)
  {
   datetime currentBarTime = iTime(symbol, tf, 0);
   if(currentBarTime == 0)
      return false; // data not ready

   if(currentBarTime != lastBarTime)
     {
      lastBarTime = currentBarTime;
      return true;
     }
   return false;
  }

//--------------------------------------------------------------------
// Basic statistics helpers used by mean-reversion / regime scoring.
//--------------------------------------------------------------------
double QXE_Mean(const double &values[], int count)
  {
   if(count <= 0)
      return 0.0;
   double sum = 0.0;
   for(int i = 0; i < count; i++)
      sum += values[i];
   return sum / count;
  }

double QXE_StdDev(const double &values[], int count, double mean)
  {
   if(count <= 1)
      return 0.0;
   double sumSq = 0.0;
   for(int i = 0; i < count; i++)
     {
      double d = values[i] - mean;
      sumSq += d * d;
     }
   return MathSqrt(sumSq / (count - 1));
  }

// Percentile rank (0..1) of `value` within `values[0..count-1]`.
double QXE_PercentileRank(const double &values[], int count, double value)
  {
   if(count <= 0)
      return 0.5;
   int below = 0;
   for(int i = 0; i < count; i++)
      if(values[i] <= value)
         below++;
   return (double)below / (double)count;
  }

double QXE_Clamp(double value, double lo, double hi)
  {
   if(value < lo) return lo;
   if(value > hi) return hi;
   return value;
  }

//--------------------------------------------------------------------
// Session helpers (broker/server time based on TimeCurrent()).
//--------------------------------------------------------------------
SessionType QXE_CurrentSession(void)
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hour = dt.hour;

   bool inLondon = (hour >= InpLondonStartHour && hour < InpLondonEndHour);
   bool inNY     = (hour >= InpNewYorkStartHour && hour < InpNewYorkEndHour);
   bool inAsian  = (hour >= InpAsianStartHour && hour < InpAsianEndHour);

   if(inLondon && inNY)
      return SESSION_LONDON_NY_OVERLAP;
   if(inLondon)
      return SESSION_LONDON;
   if(inNY)
      return SESSION_NEWYORK;
   if(inAsian)
      return SESSION_ASIAN;
   return SESSION_OFF;
  }

string QXE_SessionToString(SessionType s)
  {
   switch(s)
     {
      case SESSION_ASIAN:              return "ASIAN";
      case SESSION_LONDON:             return "LONDON";
      case SESSION_NEWYORK:            return "NEWYORK";
      case SESSION_LONDON_NY_OVERLAP:  return "LONDON_NY_OVERLAP";
      default:                         return "OFF";
     }
  }

string QXE_RegimeToString(RegimeType r)
  {
   switch(r)
     {
      case REGIME_TREND_BULL:      return "TREND_BULL";
      case REGIME_TREND_BEAR:      return "TREND_BEAR";
      case REGIME_RANGE:           return "RANGE";
      case REGIME_VOL_EXPANSION:   return "VOL_EXPANSION";
      case REGIME_VOL_CONTRACTION: return "VOL_CONTRACTION";
      case REGIME_TRANSITION:      return "TRANSITION";
      default:                     return "NO_TRADE";
     }
  }

string QXE_StrategyToString(StrategyType s)
  {
   switch(s)
     {
      case STRAT_TREND_FOLLOWING:        return "TrendFollowing";
      case STRAT_TIME_SERIES_MOMENTUM:   return "TimeSeriesMomentum";
      case STRAT_DONCHIAN_BREAKOUT:      return "DonchianBreakout";
      case STRAT_VOLATILITY_BREAKOUT:    return "VolatilityBreakout";
      case STRAT_MOMENTUM_PULLBACK:      return "MomentumPullback";
      case STRAT_MARKET_STRUCTURE:       return "MarketStructure";
      case STRAT_LIQUIDITY_SWEEP:        return "LiquiditySweep";
      case STRAT_MEAN_REVERSION:         return "MeanReversion";
      case STRAT_BOLLINGER_ZSCORE:       return "BollingerZScore";
      case STRAT_VWAP:                   return "VWAP";
      case STRAT_OPENING_RANGE_BREAKOUT: return "OpeningRangeBreakout";
      default:                           return "Unknown";
     }
  }

string QXE_DirectionToString(SignalDirection d)
  {
   if(d == SIGNAL_BUY)  return "BUY";
   if(d == SIGNAL_SELL) return "SELL";
   return "NONE";
  }

string QXE_ExitReasonToString(ExitReason e)
  {
   switch(e)
     {
      case EXIT_STOP_LOSS:               return "StopLoss";
      case EXIT_TAKE_PROFIT_1:           return "TP1";
      case EXIT_TAKE_PROFIT_2:           return "TP2";
      case EXIT_RUNNER:                  return "Runner";
      case EXIT_BREAK_EVEN:              return "BreakEven";
      case EXIT_TRAILING_STOP:           return "TrailingStop";
      case EXIT_MANUAL:                  return "Manual";
      case EXIT_OPPOSITE_SIGNAL:         return "OppositeSignal";
      case EXIT_DRAWDOWN_PROTECTION:     return "DrawdownProtection";
      case EXIT_DAILY_LIMIT:             return "DailyLimit";
      case EXIT_STRUCTURE_INVALIDATION:  return "StructureInvalidation";
      default:                           return "None";
     }
  }

#endif // QXE_UTILITIES_MQH
