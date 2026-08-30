//+------------------------------------------------------------------+
//| PositionSizing.mqh                                               |
//| QUANT_XAUUSD_ENGINE - Lot size calculation (spec section 24)     |
//| Never uses a fixed lot in live logic. Always derives size from   |
//| equity, risk %, and the REAL broker-calculated loss at SL.       |
//|                                                                   |
//| REPAIR PASS (confirmed ×10 bug): manual tick_size/tick_value      |
//| arithmetic was mathematically self-consistent but silently wrong |
//| on this broker's XAUUSD spec - SYMBOL_TRADE_TICK_VALUE=0.10 did   |
//| not match the real economic PnL of a 1.0-unit price move on a    |
//| 100oz contract ($1.00/tick), producing lot sizes ~10x too large  |
//| and real risk ~10x the configured InpRiskPercent. This is now    |
//| broker-agnostic: OrderCalcProfit() - the SAME engine MT5 itself  |
//| uses to price the trade - is the PRIMARY sizing source. The old  |
//| tick-based formula is kept ONLY as a diagnostic cross-check that |
//| logs a loud [RISK-MODEL-MISMATCH] warning if the two disagree by |
//| more than 5%, so a future broker/symbol spec oddity is caught    |
//| immediately instead of silently mis-sizing every trade again.    |
//+------------------------------------------------------------------+
#ifndef QXE_POSITIONSIZING_MQH
#define QXE_POSITIONSIZING_MQH

#include "../Core/Utilities.mqh"
#include "../Core/Logger.mqh"

class CPositionSizing
  {
public:
   // Returns lot size normalized to the symbol's volume constraints, or
   // 0.0 if a valid size cannot be computed OR OrderCalcProfit() itself
   // fails (caller must treat 0 as reject - never fall back to a guess).
   //
   // outMoneyAtRisk       = broker-verified expected loss at the FINAL
   //                         normalized lot (re-checked via a second
   //                         OrderCalcProfit call - never just scaled
   //                         linearly from the raw/unnormalized figure).
   // outLossPerLotBroker  = OrderCalcProfit()-based loss for 1.0 lot
   //                         (the value actually used for sizing).
   // outLossPerLotTickModel = the OLD tick_size/tick_value formula's
   //                         result for 1.0 lot - diagnostic only.
   double            CalculateLot(string symbol, double equity, double riskPercent,
                                   SignalDirection direction, double entryPrice, double stopPrice,
                                   double &outMoneyAtRisk, double &outLossPerLotBroker,
                                   double &outLossPerLotTickModel) const
     {
      outMoneyAtRisk = 0.0;
      outLossPerLotBroker = 0.0;
      outLossPerLotTickModel = 0.0;

      if(equity <= 0.0 || riskPercent <= 0.0 || direction == SIGNAL_NONE)
         return 0.0;

      double slDistance = MathAbs(entryPrice - stopPrice);
      if(slDistance <= 0.0)
         return 0.0;

      // --- Diagnostic-only tick-based model (never used for sizing) ---
      double tickSize = QXE_TickSize(symbol);
      double tickValue = QXE_TickValue(symbol);
      if(tickSize > 0.0 && tickValue > 0.0)
         outLossPerLotTickModel = (slDistance / tickSize) * tickValue;

      // --- PRIMARY: broker-agnostic loss via OrderCalcProfit() ---
      ENUM_ORDER_TYPE orderType = (direction == SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      double profitOneLot = 0.0;
      if(!OrderCalcProfit(orderType, symbol, 1.0, entryPrice, stopPrice, profitOneLot))
        {
         g_Logger.Error(StringFormat("OrderCalcProfit failed during sizing (symbol=%s err=%d) - rejecting trade rather than guessing.",
                         symbol, GetLastError()));
         return 0.0;
        }
      double lossOneLot = MathAbs(profitOneLot);
      outLossPerLotBroker = lossOneLot;

      if(outLossPerLotTickModel > 0.0 && lossOneLot > 0.0)
        {
         double ratio = lossOneLot / outLossPerLotTickModel;
         if(MathAbs(ratio - 1.0) > 0.05) // more than 5% disagreement
            g_Logger.Error(StringFormat(
               "[RISK-MODEL-MISMATCH] symbol=%s tickModelLoss=%.4f brokerCalcLoss=%.4f ratio=%.4f - sizing uses brokerCalcLoss",
               symbol, outLossPerLotTickModel, lossOneLot, ratio));
        }

      if(lossOneLot <= 0.0)
         return 0.0;

      double moneyToRisk = equity * (riskPercent / 100.0);
      double rawLot = moneyToRisk / lossOneLot;
      double normalizedLot = QXE_NormalizeVolume(symbol, rawLot);

      if(normalizedLot <= 0.0)
         return 0.0;

      // Re-verify the ACTUAL expected loss at the normalized lot with a
      // second OrderCalcProfit call - never assume linear scaling from
      // the 1-lot figure holds exactly (currency conversion / margin
      // quirks are broker-specific; ask the broker's own engine again).
      double profitAtNormalized = 0.0;
      if(!OrderCalcProfit(orderType, symbol, normalizedLot, entryPrice, stopPrice, profitAtNormalized))
        {
         g_Logger.Error("OrderCalcProfit re-verification at normalized lot failed - rejecting trade.");
         return 0.0;
        }
      double expectedLoss = MathAbs(profitAtNormalized);

      if(expectedLoss > moneyToRisk * 1.05) // should never happen (flooring only reduces risk) - defensive check
        {
         g_Logger.Error(StringFormat(
            "Post-normalization expected loss %.2f exceeds requested risk budget %.2f - rejecting trade.",
            expectedLoss, moneyToRisk));
         return 0.0;
        }

      outMoneyAtRisk = expectedLoss;
      return normalizedLot;
     }
  };

#endif // QXE_POSITIONSIZING_MQH
