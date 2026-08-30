//+------------------------------------------------------------------+
//| ErrorHandler.mqh                                                 |
//| QUANT_XAUUSD_ENGINE - Centralized error / retcode handling       |
//+------------------------------------------------------------------+
#ifndef QXE_ERRORHANDLER_MQH
#define QXE_ERRORHANDLER_MQH

#include "Logger.mqh"

// Translates a trade server return code into a human-readable string
// and logs it. Returns true if the retcode represents success.
bool QXE_CheckTradeRetcode(uint retcode, string context)
  {
   switch(retcode)
     {
      case TRADE_RETCODE_DONE:
      case TRADE_RETCODE_DONE_PARTIAL:
      case TRADE_RETCODE_PLACED:
         return true;

      case TRADE_RETCODE_REQUOTE:
         g_Logger.Warn(StringFormat("[%s] Requote (retcode=%d)", context, retcode));
         return false;

      case TRADE_RETCODE_REJECT:
         g_Logger.Error(StringFormat("[%s] Order rejected (retcode=%d)", context, retcode));
         return false;

      case TRADE_RETCODE_INVALID_STOPS:
         g_Logger.Error(StringFormat("[%s] Invalid stops (retcode=%d)", context, retcode));
         return false;

      case TRADE_RETCODE_NO_MONEY:
         g_Logger.Error(StringFormat("[%s] Not enough money (retcode=%d)", context, retcode));
         return false;

      case TRADE_RETCODE_MARKET_CLOSED:
         g_Logger.Warn(StringFormat("[%s] Market closed (retcode=%d)", context, retcode));
         return false;

      case TRADE_RETCODE_TRADE_DISABLED:
         g_Logger.Error(StringFormat("[%s] Trading disabled (retcode=%d)", context, retcode));
         return false;

      case TRADE_RETCODE_INVALID_VOLUME:
         g_Logger.Error(StringFormat("[%s] Invalid volume (retcode=%d)", context, retcode));
         return false;

      case TRADE_RETCODE_PRICE_OFF:
         g_Logger.Warn(StringFormat("[%s] Off quotes (retcode=%d)", context, retcode));
         return false;

      case TRADE_RETCODE_CONNECTION:
         g_Logger.Error(StringFormat("[%s] No connection to trade server (retcode=%d)", context, retcode));
         return false;

      default:
         g_Logger.Error(StringFormat("[%s] Unhandled retcode=%d", context, retcode));
         return false;
     }
  }

// Checks whether an indicator handle is valid; logs and returns false if not.
bool QXE_ValidHandle(int handle, string indicatorName)
  {
   if(handle == INVALID_HANDLE)
     {
      g_Logger.Error(StringFormat("Failed to create indicator handle: %s (err=%d)",
                      indicatorName, GetLastError()));
      return false;
     }
   return true;
  }

// Checks a CopyBuffer/CopyRates result count against what was expected.
bool QXE_CheckCopyResult(int copied, int expected, string context)
  {
   if(copied < expected || copied <= 0)
     {
      g_Logger.Warn(StringFormat("[%s] Insufficient data copied: got %d, expected >= %d (err=%d)",
                     context, copied, expected, GetLastError()));
      return false;
     }
   return true;
  }

#endif // QXE_ERRORHANDLER_MQH
