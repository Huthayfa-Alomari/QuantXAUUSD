//+------------------------------------------------------------------+
//| Journal.mqh                                                      |
//| QUANT_XAUUSD_ENGINE - CSV/terminal trade & research journal      |
//| (spec sections 33-34)                                            |
//+------------------------------------------------------------------+
#ifndef QXE_JOURNAL_MQH
#define QXE_JOURNAL_MQH

#include "../Core/Types.mqh"
#include "../Core/Constants.mqh"
#include "../Core/Utilities.mqh"
#include "../Core/Logger.mqh"

class CJournal
  {
private:
   int               m_tradeFileHandle;
   int               m_researchFileHandle;
   bool              m_tradeHeaderWritten;
   bool              m_researchHeaderWritten;

public:
                     CJournal(void) : m_tradeFileHandle(INVALID_HANDLE),
                                       m_researchFileHandle(INVALID_HANDLE),
                                       m_tradeHeaderWritten(false),
                                       m_researchHeaderWritten(false) {}

   bool              Init(string tradeFileName, string researchFileName)
     {
      m_tradeFileHandle = FileOpen(tradeFileName, FILE_WRITE | FILE_READ | FILE_CSV | FILE_ANSI, QXE_CSV_DELIM);
      m_researchFileHandle = FileOpen(researchFileName, FILE_WRITE | FILE_READ | FILE_CSV | FILE_ANSI, QXE_CSV_DELIM);

      if(m_tradeFileHandle == INVALID_HANDLE || m_researchFileHandle == INVALID_HANDLE)
        {
         g_Logger.Error(StringFormat("Journal: failed to open CSV files, err=%d", GetLastError()));
         return false;
        }

      FileSeek(m_tradeFileHandle, 0, SEEK_END);
      FileSeek(m_researchFileHandle, 0, SEEK_END);

      if(FileSize(m_tradeFileHandle) == 0)
        {
         FileWrite(m_tradeFileHandle, "Ticket", "Date", "PrimaryStrategy", "ContributingStrategies", "Regime", "Direction",
                    "Entry", "SL", "TP", "Lot", "Risk", "Score", "ATR", "ADX", "Spread",
                    "Exit", "Profit", "R", "MAE", "MFE", "MAE_R", "MFE_R", "HoldingSeconds", "ExitReason",
                    "EquityAtEntry", "RequestedRiskPct", "SLDistancePrice", "LossPerLotBroker", "LossPerLotTickModel", "ExpectedLossAtSL");
        }
      if(FileSize(m_researchFileHandle) == 0)
        {
         FileWrite(m_researchFileHandle, "Timestamp", "PrimaryStrategy", "ContributingStrategies", "Regime", "Direction", "Score",
                    "Entry", "SL", "TP", "ATR", "ADX", "Spread", "Session", "Outcome");
        }
      return true;
     }

   void              Deinit(void)
     {
      if(m_tradeFileHandle != INVALID_HANDLE) FileClose(m_tradeFileHandle);
      if(m_researchFileHandle != INVALID_HANDLE) FileClose(m_researchFileHandle);
     }

   void              LogTrade(const TradeResult &tr)
     {
      if(m_tradeFileHandle == INVALID_HANDLE)
         return;
      FileSeek(m_tradeFileHandle, 0, SEEK_END);
      FileWrite(m_tradeFileHandle,
                 (string)tr.ticket,
                 TimeToString(tr.closeTime, TIME_DATE | TIME_MINUTES),
                 QXE_StrategyToString(tr.strategy),
                 tr.contributingStrategies,
                 QXE_RegimeToString(tr.regime),
                 QXE_DirectionToString(tr.direction),
                 DoubleToString(tr.entry, 2),
                 DoubleToString(tr.stopLoss, 2),
                 DoubleToString(tr.takeProfit, 2),
                 DoubleToString(tr.lot, 2),
                 DoubleToString(tr.riskMoney, 2),
                 DoubleToString(tr.score, 1),
                 DoubleToString(tr.atrAtEntry, 2),
                 DoubleToString(tr.adxAtEntry, 1),
                 DoubleToString(tr.spreadAtEntry, 1),
                 DoubleToString(tr.exitPrice, 2),
                 DoubleToString(tr.profit, 2),
                 DoubleToString(tr.rMultiple, 2),
                 DoubleToString(tr.mae, 2),
                 DoubleToString(tr.mfe, 2),
                 DoubleToString(tr.maeR, 2),
                 DoubleToString(tr.mfeR, 2),
                 (string)tr.holdingSeconds,
                 QXE_ExitReasonToString(tr.exitReason),
                 DoubleToString(tr.equityAtEntry, 2),
                 DoubleToString(tr.requestedRiskPercent, 4),
                 DoubleToString(tr.slDistancePriceAtEntry, 5),
                 DoubleToString(tr.lossPerLotBrokerAtEntry, 5),
                 DoubleToString(tr.lossPerLotTickModelAtEntry, 5),
                 DoubleToString(tr.expectedLossAtSL, 2));

      g_Logger.Info(StringFormat("TRADE CLOSED ticket=%d %s %s profit=%.2f R=%.2f MFE_R=%.2f MAE_R=%.2f reason=%s",
                     tr.ticket, QXE_StrategyToString(tr.strategy), QXE_DirectionToString(tr.direction),
                     tr.profit, tr.rMultiple, tr.mfeR, tr.maeR, QXE_ExitReasonToString(tr.exitReason)));
     }

   // Research mode: log every setup that WOULD have been taken, whether
   // or not a real trade is opened.
   void              LogResearchSetup(const TradeSetup &setup, const MarketState &state, double spread, string outcome)
     {
      if(m_researchFileHandle == INVALID_HANDLE)
         return;
      FileSeek(m_researchFileHandle, 0, SEEK_END);
      FileWrite(m_researchFileHandle,
                 TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES),
                 QXE_StrategyToString(setup.primaryStrategy),
                 setup.contributingStrategies,
                 QXE_RegimeToString(setup.regime),
                 QXE_DirectionToString(setup.direction),
                 DoubleToString(setup.compositeScore, 1),
                 DoubleToString(setup.entry, 2),
                 DoubleToString(setup.stopLoss, 2),
                 DoubleToString(setup.takeProfit2, 2),
                 DoubleToString(state.atrH1, 2),
                 DoubleToString(state.adxH1, 1),
                 DoubleToString(spread, 1),
                 QXE_SessionToString(state.session),
                 outcome);
     }
  };

#endif // QXE_JOURNAL_MQH
