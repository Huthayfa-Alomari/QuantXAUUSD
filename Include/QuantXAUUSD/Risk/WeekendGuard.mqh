//+------------------------------------------------------------------+
//| WeekendGuard.mqh                                                 |
//| QUANT_XAUUSD_ENGINE - Weekend / Gap Risk Guard (spec section 19) |
//|                                                                   |
//| Motivated by a real 2026 case: a position held over the weekend   |
//| gapped from an expected ~$392 SL loss to an actual ~$1,866 loss   |
//| (~4.8R) purely from the market reopening far from Friday's close. |
//| This is NOT a sizing bug - a resting SL order cannot protect      |
//| against a closed market. All three controls are independently    |
//| configurable and OFF/neutral unless the corresponding input says  |
//| otherwise (InpCloseBeforeWeekend defaults false, per spec: "لا    |
//| تجعل Force Close default بالضرورة").                              |
//+------------------------------------------------------------------+
#ifndef QXE_WEEKENDGUARD_MQH
#define QXE_WEEKENDGUARD_MQH

#include "../Core/Config.mqh"
#include "../Core/Logger.mqh"

class CWeekendGuard
  {
public:
   // Returns true if a NEW entry should be blocked right now.
   bool              BlocksNewEntry(datetime nowServerTime) const
     {
      if(!InpEnableWeekendGuard)
         return false;

      MqlDateTime dt;
      TimeToStruct(nowServerTime, dt);

      bool isFriday = (dt.day_of_week == 5);
      if(isFriday && dt.hour >= InpFridayNoNewTradesHour)
        {
         g_Logger.Info(StringFormat("[WEEKEND-GUARD] REJECT_NEW_ENTRY day=Friday hour=%d (cutoff=%d)",
                        dt.hour, InpFridayNoNewTradesHour));
         return true;
        }
      return false;
     }

   // Returns the risk multiplier to apply for the reduce-risk window
   // (1.0 outside that window - no effect).
   double            RiskMultiplier(datetime nowServerTime) const
     {
      if(!InpEnableWeekendGuard)
         return 1.0;

      MqlDateTime dt;
      TimeToStruct(nowServerTime, dt);

      bool isFriday = (dt.day_of_week == 5);
      if(isFriday && dt.hour >= InpFridayReduceRiskHour)
         return InpFridayRiskMultiplier;
      return 1.0;
     }

   // Returns true once the force-close hour is reached, if enabled.
   bool              ShouldForceClose(datetime nowServerTime) const
     {
      if(!InpEnableWeekendGuard || !InpCloseBeforeWeekend)
         return false;

      MqlDateTime dt;
      TimeToStruct(nowServerTime, dt);

      bool isFriday = (dt.day_of_week == 5);
      if(isFriday && dt.hour >= InpFridayForceCloseHour)
        {
         g_Logger.Info(StringFormat("[WEEKEND-GUARD] FORCE_CLOSE_TRIGGERED day=Friday hour=%d (cutoff=%d)",
                        dt.hour, InpFridayForceCloseHour));
         return true;
        }
      return false;
     }
  };

#endif // QXE_WEEKENDGUARD_MQH
