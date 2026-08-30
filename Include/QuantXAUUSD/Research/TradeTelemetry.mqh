//+------------------------------------------------------------------+
//| TradeTelemetry.mqh                                               |
//| QUANT_XAUUSD_ENGINE - Architecture v2 Trade Telemetry (sec. 14)  |
//|                                                                   |
//| One row per LOGICAL position (never a partial close) - built      |
//| directly from a finalized TradeResult, which itself carries a     |
//| full MarketState snapshot taken at entry (`entryState`), so every  |
//| feature here is point-in-time correct by construction (it is the  |
//| exact state BuildMarketState computed before the trade opened,    |
//| never recomputed with hindsight).                                 |
//+------------------------------------------------------------------+
#ifndef QXE_TRADETELEMETRY_MQH
#define QXE_TRADETELEMETRY_MQH

#include "../Core/Types.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Utilities.mqh"
#include "../Core/Logger.mqh"

class CTradeTelemetry
  {
private:
   int               m_handle;

public:
                     CTradeTelemetry(void) : m_handle(INVALID_HANDLE) {}

   bool              Init(string fileName)
     {
      m_handle = FileOpen(fileName, FILE_WRITE | FILE_READ | FILE_CSV | FILE_ANSI, QXE_CSV_DELIM);
      if(m_handle == INVALID_HANDLE)
        {
         g_Logger.Error(StringFormat("TradeTelemetry: failed to open %s, err=%d", fileName, GetLastError()));
         return false;
        }
      FileSeek(m_handle, 0, SEEK_END);
      if(FileSize(m_handle) == 0)
        {
         FileWrite(m_handle,
            // Identity
            "PositionIdentifier", "EntryTime", "ExitTime", "Direction", "PrimaryStrategy",
            "ContributorStrategies", "ContributorCount", "ContributorEligibility", "RegimeAtEntry", "RegimeAtExit",
            "MetaRegimeAtEntry", "MetaRegimeConfidence",
            // Market State
            "ADX_H1", "ADX_H4", "ATR_H1", "ATRPercentile", "ATRPriceRatio",
            "EMA20Slope", "EMA50Slope", "EMA200Slope",
            "D1Bias", "H4Bias", "D1H4Aligned",
            "RangeEfficiency", "TrendEfficiency", "VolatilityScore",
            "DistEMA20_ATR", "DistEMA50_ATR", "DistEMA200_ATR",
            "PrevDayRange", "CurrDayRangeRatio",
            "Session", "DayOfWeek", "Hour",
            "SpreadPoints", "SpreadATRRatio",
            "StructureBias", "RecentBOS", "RecentCHOCH",
            // Signal State
            "RawStrategyScore", "InteractionModifier", "FinalScore", "InteractionReason",
            "EligibilityDecision", "EligibilityReason",
            // Risk
            "EquityAtEntry", "RequestedRiskPct", "InitialRiskMoney",
            "EntryPrice", "InitialSL", "SLDistancePrice", "Lot", "ExpectedLossAtSL",
            // Outcome
            "ExitReason", "RealizedPnL", "FinalR", "MFE_Price", "MAE_Price",
            "MFE_R", "MAE_R", "HoldingMinutes");
        }
      return true;
     }

   void              Deinit(void)
     {
      if(m_handle != INVALID_HANDLE)
         FileClose(m_handle);
     }

   void              LogTelemetry(const TradeResult &tr)
     {
      if(m_handle == INVALID_HANDLE)
         return;

      const MarketState st = tr.entryState;

      FileSeek(m_handle, 0, SEEK_END);
      FileWrite(m_handle,
         // Identity
         (string)tr.ticket,
         TimeToString(tr.openTime, TIME_DATE | TIME_MINUTES),
         TimeToString(tr.closeTime, TIME_DATE | TIME_MINUTES),
         QXE_DirectionToString(tr.direction),
         QXE_StrategyToString(tr.strategy),
         tr.contributingStrategies,
         (string)tr.contributorCount,
         tr.contributorEligibility,
         QXE_RegimeToString(tr.regime),
         QXE_RegimeToString(tr.regimeAtExit),
         EnumToString(st.meta.regime),
         DoubleToString(st.meta.confidence, 3),
         // Market State
         DoubleToString(st.adxH1, 2),
         DoubleToString(st.adxH4, 2),
         DoubleToString(st.atrH1, 5),
         DoubleToString(st.atrPercentile, 3),
         DoubleToString((st.close > QXE_EPS) ? st.atrH1 / st.close : 0.0, 6),
         DoubleToString(st.emaSlope20, 2),
         DoubleToString(st.emaSlope50, 2),
         DoubleToString(st.emaSlope200, 2),
         (string)st.d1Bias,
         (string)st.h4Bias,
         st.d1H4Aligned ? "true" : "false",
         DoubleToString(st.rangeEfficiency, 3),
         DoubleToString(st.trendEfficiency, 3),
         DoubleToString(st.meta.volatilityScore, 2),
         DoubleToString(st.distEMA20_ATR, 3),
         DoubleToString(st.distEMA50_ATR, 3),
         DoubleToString(st.distEMA200_ATR, 3),
         DoubleToString(st.prevDayRange, 5),
         DoubleToString(st.currDayRangeRatio, 3),
         QXE_SessionToString(st.session),
         (string)st.dayOfWeek,
         (string)st.hourOfDay,
         DoubleToString(st.spreadPoints, 1),
         DoubleToString(st.spreadATRRatio, 4),
         (st.structureBias == BIAS_BULLISH) ? "BULLISH" : (st.structureBias == BIAS_BEARISH) ? "BEARISH" : "UNKNOWN",
         st.recentBOS ? "true" : "false",
         st.recentCHoCH ? "true" : "false",
         // Signal State
         DoubleToString(tr.rawScore, 2),
         DoubleToString(tr.interactionModifier, 2),
         DoubleToString(tr.score, 2),
         tr.interactionReason,
         (tr.eligibilityDecision == ELIGIBILITY_ALLOW) ? "ALLOW" :
            (tr.eligibilityDecision == ELIGIBILITY_CONFIRMATION_ONLY) ? "CONFIRMATION_ONLY" : "BLOCK",
         tr.eligibilityReason,
         // Risk
         DoubleToString(tr.equityAtEntry, 2),
         DoubleToString(tr.requestedRiskPercent, 4),
         DoubleToString(tr.riskMoney, 2),
         DoubleToString(tr.entry, 2),
         DoubleToString(tr.stopLoss, 2),
         DoubleToString(tr.slDistancePriceAtEntry, 5),
         DoubleToString(tr.lot, 4),
         DoubleToString(tr.expectedLossAtSL, 2),
         // Outcome
         QXE_ExitReasonToString(tr.exitReason),
         DoubleToString(tr.profit, 2),
         DoubleToString(tr.rMultiple, 3),
         DoubleToString(tr.mfe, 5),
         DoubleToString(tr.mae, 5),
         DoubleToString(tr.mfeR, 3),
         DoubleToString(tr.maeR, 3),
         DoubleToString(tr.holdingSeconds / 60.0, 1));
     }
  };

#endif // QXE_TRADETELEMETRY_MQH
