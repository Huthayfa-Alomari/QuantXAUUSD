//+------------------------------------------------------------------+
//| TradeExecutor.mqh                                                |
//| QUANT_XAUUSD_ENGINE - Execution safety layer (spec section 40)  |
//| Wraps CTrade, verifies every retcode, normalizes prices/volumes, |
//| and enforces the slippage tolerance (SlippageFilter role from    |
//| the spec tree folded in here since it only matters at the exact  |
//| moment of order placement - documented in README).               |
//+------------------------------------------------------------------+
#ifndef QXE_TRADEEXECUTOR_MQH
#define QXE_TRADEEXECUTOR_MQH

#include <Trade/Trade.mqh>
#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/ErrorHandler.mqh"
#include "../Core/Utilities.mqh"

class CTradeExecutor
  {
private:
   CTrade            m_trade;
   string            m_symbol;
   ulong             m_magic;

public:
   void              Init(string symbol, ulong magic)
     {
      m_symbol = symbol;
      m_magic = magic;
      m_trade.SetExpertMagicNumber(magic);
      m_trade.SetDeviationInPoints(InpMaxSlippagePoints);
      m_trade.SetTypeFillingBySymbol(symbol);
      m_trade.LogLevel(LOG_LEVEL_ERRORS);
     }

   // Opens a market position sized/priced per the validated setup+risk.
   // Returns the resulting position ticket, or 0 on failure.
   ulong             OpenPosition(const TradeSetup &setup, const RiskParameters &risk)
     {
      if(!risk.approved || risk.lotSize <= 0.0)
        {
         g_Logger.Error("OpenPosition called with unapproved risk parameters - aborting.");
         return 0;
        }

      double price = (setup.direction == SIGNAL_BUY) ? SymbolInfoDouble(m_symbol, SYMBOL_ASK)
                                                       : SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double sl = QXE_NormalizePrice(m_symbol, setup.stopLoss);
      double tp = QXE_NormalizePrice(m_symbol, setup.takeProfit2);
      double lot = QXE_NormalizeVolume(m_symbol, risk.lotSize);

      if(lot <= 0.0)
        {
         g_Logger.Error("OpenPosition aborted: normalized lot rounds to 0 - never inflated to broker minimum.");
         return 0;
        }

      // Directional SL validation - defense-in-depth, third and final
      // check (also validated in ScoreEngine and RiskEngine before this
      // point). MathAbs(entry-stop) alone is not sufficient.
      if(setup.direction == SIGNAL_BUY && sl >= price)
        {
         g_Logger.Error(StringFormat("OpenPosition aborted: BUY sl=%.2f is not below price=%.2f", sl, price));
         return 0;
        }
      if(setup.direction == SIGNAL_SELL && sl <= price)
        {
         g_Logger.Error(StringFormat("OpenPosition aborted: SELL sl=%.2f is not above price=%.2f", sl, price));
         return 0;
        }

      if(!ValidateStopsDistance(price, sl, setup.direction))
        {
         g_Logger.Error("OpenPosition aborted: stop distance invalid relative to broker stops level.");
         return 0;
        }

      bool sent;
      if(setup.direction == SIGNAL_BUY)
         sent = m_trade.Buy(lot, m_symbol, price, sl, tp, "QXE:" + setup.contributingStrategies);
      else
         sent = m_trade.Sell(lot, m_symbol, price, sl, tp, "QXE:" + setup.contributingStrategies);

      uint retcode = m_trade.ResultRetcode();
      if(!sent || !QXE_CheckTradeRetcode(retcode, "OpenPosition"))
        {
         g_Logger.Error(StringFormat("OpenPosition failed. retcode=%d comment=%s", retcode, m_trade.ResultComment()));
         return 0;
        }

      ulong ticket = m_trade.ResultOrder();
      g_Logger.Info(StringFormat("Position opened: ticket=%d dir=%s lot=%.2f entry=%.2f sl=%.2f tp=%.2f",
                     ticket, QXE_DirectionToString(setup.direction), lot, price, sl, tp));
      return ticket;
     }

   bool              ClosePartial(ulong ticket, double volume)
     {
      double normVol = QXE_NormalizeVolume(m_symbol, volume);
      if(normVol <= 0.0)
         return false;
      bool ok = m_trade.PositionClosePartial(ticket, normVol);
      uint retcode = m_trade.ResultRetcode();
      QXE_CheckTradeRetcode(retcode, "ClosePartial");
      return ok;
     }

   bool              CloseFull(ulong ticket)
     {
      bool ok = m_trade.PositionClose(ticket);
      uint retcode = m_trade.ResultRetcode();
      QXE_CheckTradeRetcode(retcode, "CloseFull");
      return ok;
     }

   bool              ModifyStops(ulong ticket, double sl, double tp)
     {
      double nsl = QXE_NormalizePrice(m_symbol, sl);
      double ntp = QXE_NormalizePrice(m_symbol, tp);
      bool ok = m_trade.PositionModify(ticket, nsl, ntp);
      uint retcode = m_trade.ResultRetcode();
      if(!ok)
         QXE_CheckTradeRetcode(retcode, "ModifyStops");
      return ok;
     }

private:
   bool              ValidateStopsDistance(double price, double sl, SignalDirection dir) const
     {
      double stopsLevelPoints = QXE_StopsLevelPoints(m_symbol);
      if(stopsLevelPoints <= 0.0)
         return true;
      double distPoints = QXE_PriceToPoints(m_symbol, MathAbs(price - sl));
      return (distPoints >= stopsLevelPoints);
     }
  };

#endif // QXE_TRADEEXECUTOR_MQH
