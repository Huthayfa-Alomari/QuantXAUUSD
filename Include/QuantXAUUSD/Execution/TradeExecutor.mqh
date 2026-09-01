//+------------------------------------------------------------------+
//| TradeExecutor.mqh                                                |
//| QUANT_XAUUSD_ENGINE - Execution safety layer (spec section 40)   |
//| Wraps CTrade, verifies every retcode, normalizes prices/volumes, |
//| and enforces execution safety at order/modify time.               |
//|                                                                   |
//| TRAILING / MODIFY-STOPS FIX:                                     |
//| 1. PositionModify now validates BOTH broker StopsLevel and        |
//|    FreezeLevel before sending a request.                          |
//| 2. Tiny/no-op stop improvements are skipped instead of sending    |
//|    a modification every tick.                                    |
//| 3. Rejected near-market candidates are skipped locally, avoiding  |
//|    retcode=10016 Invalid stops retry spam.                        |
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

   ulong             ResolveLivePositionTicket(const ulong positionIdentifier,
                                                   const ulong resultOrder)
     {
      // Primary identity path: DEAL_POSITION_ID maps to POSITION_IDENTIFIER.
      // Then resolve the CURRENT POSITION_TICKET used by management APIs.
      if(positionIdentifier > 0)
        {
         for(int i = PositionsTotal() - 1; i >= 0; i--)
           {
            ulong ticket = PositionGetTicket(i);

            if(ticket == 0)
               continue;

            if(PositionGetString(POSITION_SYMBOL) != m_symbol)
               continue;

            if((ulong)PositionGetInteger(POSITION_MAGIC) != m_magic)
               continue;

            if((ulong)PositionGetInteger(POSITION_IDENTIFIER) == positionIdentifier)
               return ticket;
           }
        }

      // Compatibility fallback only. ResultOrder() is not treated as the
      // authoritative logical position identity.
      if(resultOrder > 0 && PositionSelectByTicket(resultOrder))
        {
         if(PositionGetString(POSITION_SYMBOL) == m_symbol &&
            (ulong)PositionGetInteger(POSITION_MAGIC) == m_magic)
            return resultOrder;
        }

      return 0;
     }

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

      double price = (setup.direction == SIGNAL_BUY)
                     ? SymbolInfoDouble(m_symbol, SYMBOL_ASK)
                     : SymbolInfoDouble(m_symbol, SYMBOL_BID);

      double sl = QXE_NormalizePrice(m_symbol, setup.stopLoss);
      double tp = QXE_NormalizePrice(m_symbol, setup.takeProfit2);
      double lot = QXE_NormalizeVolume(m_symbol, risk.lotSize);

      if(lot <= 0.0)
        {
         g_Logger.Error("OpenPosition aborted: normalized lot rounds to 0 - never inflated to broker minimum.");
         return 0;
        }

      // Directional SL validation - defense-in-depth.
      if(setup.direction == SIGNAL_BUY && sl >= price)
        {
         g_Logger.Error(StringFormat(
            "OpenPosition aborted: BUY sl=%.2f is not below price=%.2f",
            sl, price));
         return 0;
        }

      if(setup.direction == SIGNAL_SELL && sl <= price)
        {
         g_Logger.Error(StringFormat(
            "OpenPosition aborted: SELL sl=%.2f is not above price=%.2f",
            sl, price));
         return 0;
        }

      if(!ValidateStopsDistance(price, sl, setup.direction))
        {
         g_Logger.Error("OpenPosition aborted: stop distance invalid relative to broker stops level.");
         return 0;
        }

      bool sent;
      if(setup.direction == SIGNAL_BUY)
         sent = m_trade.Buy(lot, m_symbol, price, sl, tp,
                            "QXE:" + setup.contributingStrategies);
      else
         sent = m_trade.Sell(lot, m_symbol, price, sl, tp,
                             "QXE:" + setup.contributingStrategies);

      uint retcode = m_trade.ResultRetcode();
      if(!sent || !QXE_CheckTradeRetcode(retcode, "OpenPosition"))
        {
         g_Logger.Error(StringFormat(
            "OpenPosition failed. retcode=%d comment=%s",
            retcode, m_trade.ResultComment()));
         return 0;
        }

      ulong resultOrder = m_trade.ResultOrder();
      ulong resultDeal  = m_trade.ResultDeal();
      ulong positionIdentifier = 0;

      if(resultDeal > 0 && HistoryDealSelect(resultDeal))
         positionIdentifier =
            (ulong)HistoryDealGetInteger(resultDeal, DEAL_POSITION_ID);

      ulong ticket =
         ResolveLivePositionTicket(positionIdentifier, resultOrder);

      if(ticket == 0)
        {
         g_Logger.Error(StringFormat(
            "[EXEC-IDENTITY] accepted order but live position ticket could not be resolved order=%I64u deal=%I64u identifier=%I64u",
            resultOrder,
            resultDeal,
            positionIdentifier));
         return 0;
        }

      double fillPrice = 0.0;

      if(PositionSelectByTicket(ticket))
         fillPrice = PositionGetDouble(POSITION_PRICE_OPEN);

      g_Logger.Info(StringFormat(
         "Position opened: ticket=%I64u identifier=%I64u order=%I64u deal=%I64u dir=%s lot=%.2f requested=%.5f fill=%.5f sl=%.5f tp=%.5f",
         ticket,
         positionIdentifier,
         resultOrder,
         resultDeal,
         QXE_DirectionToString(setup.direction),
         lot,
         price,
         fillPrice,
         sl,
         tp));

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

   // Safe SL/TP modification.
   //
   // IMPORTANT:
   // Returning false here does NOT necessarily mean a broker error.
   // A modification may be intentionally skipped because:
   // - the requested SL is inside StopsLevel / FreezeLevel;
   // - the new SL is effectively unchanged;
   // - the improvement is too small to justify another broker request.
   //
   // This prevents the old every-tick modify spam and retcode=10016 loops.
   bool              ModifyStops(ulong ticket, double sl, double tp)
     {
      if(!PositionSelectByTicket(ticket))
        {
         g_Logger.Debug(StringFormat(
            "[MODIFY-SKIP] ticket=%d reason=POSITION_NOT_FOUND",
            ticket));
         return false;
        }

      double nsl = (sl > 0.0) ? QXE_NormalizePrice(m_symbol, sl) : 0.0;
      double ntp = (tp > 0.0) ? QXE_NormalizePrice(m_symbol, tp) : 0.0;

      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);

      long positionType = PositionGetInteger(POSITION_TYPE);

      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);

      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double tickSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);

      if(point <= 0.0)
         point = 0.00001;
      if(tickSize <= 0.0)
         tickSize = point;

      // ---------------------------------------------------------------
      // 1. Suppress no-op / micro modifications.
      //
      // Five ticks is intentionally conservative: it removes the
      // 0.01/0.02 XAUUSD modification spam observed in the tester while
      // preserving the ATR trailing logic itself.
      // ---------------------------------------------------------------
      double minModifyStep = tickSize * 5.0;

      if(nsl > 0.0 && currentSL > 0.0)
        {
         double improvement = (positionType == POSITION_TYPE_BUY)
                              ? (nsl - currentSL)
                              : (currentSL - nsl);

         // Never worsen a protective stop.
         if(improvement <= 0.0)
           {
            return false;
           }

         if(improvement + QXE_EPS < minModifyStep)
           {
            return false;
           }
        }

      // If both normalized values are already effectively unchanged,
      // there is nothing to send.
      bool sameSL = (MathAbs(nsl - currentSL) < tickSize * 0.5);
      bool sameTP = (MathAbs(ntp - currentTP) < tickSize * 0.5);

      if(sameSL && sameTP)
         return false;

      // ---------------------------------------------------------------
      // 2. Validate StopsLevel AND FreezeLevel before PositionModify.
      //
      // MetaTrader can reject an otherwise directional stop if it lies
      // too close to market. We use the stricter of both broker limits.
      // ---------------------------------------------------------------
      long stopsLevelPoints  =
         SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);

      long freezeLevelPoints =
         SymbolInfoInteger(m_symbol, SYMBOL_TRADE_FREEZE_LEVEL);

      long protectionPoints =
         (stopsLevelPoints > freezeLevelPoints)
         ? stopsLevelPoints
         : freezeLevelPoints;

      // Add one tick of safety so rounding at the exact boundary cannot
      // turn a nominally-valid candidate into retcode 10016.
      double minDistance =
         protectionPoints * point + tickSize;

      if(nsl > 0.0)
        {
         if(positionType == POSITION_TYPE_BUY)
           {
            double maxAllowedSL = bid - minDistance;

            if(nsl > maxAllowedSL + QXE_EPS)
              {
               g_Logger.Debug(StringFormat(
                  "[MODIFY-SKIP] ticket=%d reason=SL_INSIDE_PROTECTION_ZONE "
                  "type=BUY requestedSL=%.5f bid=%.5f maxAllowedSL=%.5f "
                  "stopsLevel=%d freezeLevel=%d",
                  ticket,
                  nsl,
                  bid,
                  maxAllowedSL,
                  (int)stopsLevelPoints,
                  (int)freezeLevelPoints));

               return false;
              }
           }
         else if(positionType == POSITION_TYPE_SELL)
           {
            double minAllowedSL = ask + minDistance;

            if(nsl < minAllowedSL - QXE_EPS)
              {
               g_Logger.Debug(StringFormat(
                  "[MODIFY-SKIP] ticket=%d reason=SL_INSIDE_PROTECTION_ZONE "
                  "type=SELL requestedSL=%.5f ask=%.5f minAllowedSL=%.5f "
                  "stopsLevel=%d freezeLevel=%d",
                  ticket,
                  nsl,
                  ask,
                  minAllowedSL,
                  (int)stopsLevelPoints,
                  (int)freezeLevelPoints));

               return false;
              }
           }
        }

      // ---------------------------------------------------------------
      // 3. Optional TP safety when the TP itself is actually changing.
      //
      // Existing unchanged TP is left alone. Only validate a newly
      // requested TP so an old valid position is not disturbed.
      // ---------------------------------------------------------------
      bool tpChanging = !sameTP && ntp > 0.0;

      if(tpChanging)
        {
         if(positionType == POSITION_TYPE_BUY)
           {
            double minAllowedTP = ask + minDistance;
            if(ntp < minAllowedTP - QXE_EPS)
              {
               g_Logger.Debug(StringFormat(
                  "[MODIFY-SKIP] ticket=%d reason=TP_INSIDE_PROTECTION_ZONE "
                  "type=BUY requestedTP=%.5f ask=%.5f minAllowedTP=%.5f",
                  ticket,
                  ntp,
                  ask,
                  minAllowedTP));
               return false;
              }
           }
         else if(positionType == POSITION_TYPE_SELL)
           {
            double maxAllowedTP = bid - minDistance;
            if(ntp > maxAllowedTP + QXE_EPS)
              {
               g_Logger.Debug(StringFormat(
                  "[MODIFY-SKIP] ticket=%d reason=TP_INSIDE_PROTECTION_ZONE "
                  "type=SELL requestedTP=%.5f bid=%.5f maxAllowedTP=%.5f",
                  ticket,
                  ntp,
                  bid,
                  maxAllowedTP));
               return false;
              }
           }
        }

      bool ok = m_trade.PositionModify(ticket, nsl, ntp);
      uint retcode = m_trade.ResultRetcode();

      if(!ok || !QXE_CheckTradeRetcode(retcode, "ModifyStops"))
        {
         g_Logger.Error(StringFormat(
            "ModifyStops failed ticket=%d sl=%.5f tp=%.5f retcode=%d comment=%s",
            ticket,
            nsl,
            ntp,
            retcode,
            m_trade.ResultComment()));

         return false;
        }

      return true;
     }

private:
   bool              ValidateStopsDistance(double price,
                                           double sl,
                                           SignalDirection dir) const
     {
      double stopsLevelPoints = QXE_StopsLevelPoints(m_symbol);

      if(stopsLevelPoints <= 0.0)
         return true;

      double distPoints =
         QXE_PriceToPoints(m_symbol, MathAbs(price - sl));

      return (distPoints >= stopsLevelPoints);
     }
  };

#endif // QXE_TRADEEXECUTOR_MQH
