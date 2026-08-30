//+------------------------------------------------------------------+
//| MarketStructure.mqh                                              |
//| QUANT_XAUUSD_ENGINE - HH/HL/LH/LL + BOS/CHoCH detection           |
//|                                                                   |
//| REPAIR PASS changes:                                             |
//| 1. Structural bias starts BIAS_UNKNOWN, never implicitly bullish. |
//| 2. BOS/CHoCH are now EVENTS, edge-triggered on the close crossing |
//|    a level for the FIRST time - not re-fired every subsequent bar|
//|    that simply remains beyond it. Each broken level is marked    |
//|    "consumed" so it cannot fire again until a new swing forms    |
//|    beyond it.                                                    |
//|                                                                   |
//| Consolidates BOSDetector.mqh + CHoCHDetector.mqh from the spec   |
//| tree into this module, since both operate on the exact same      |
//| swing-pair state machine (documented in README).                 |
//+------------------------------------------------------------------+
#ifndef QXE_MARKETSTRUCTURE_MQH
#define QXE_MARKETSTRUCTURE_MQH

#include "SwingDetector.mqh"
#include "../Core/Types.mqh"
#include "../Core/Config.mqh"
#include "../Core/Constants.mqh"

class CMarketStructure
  {
private:
   CSwingDetector    m_swings;

   double            m_lastSwingHigh;
   double            m_lastSwingLow;
   double            m_prevSwingHigh;
   double            m_prevSwingLow;

   double            m_prevClose;         // close at the previous evaluation, for edge-triggering
   bool              m_prevCloseValid;

   bool              m_lastHighConsumed;  // has m_lastSwingHigh already produced a BOS/CHoCH?
   bool              m_lastLowConsumed;

   StructureEventType m_lastEvent;        // event fired on the MOST RECENT update only (else STRUCT_NONE)
   StructureEventType m_lastSwingLabel;   // most recent HH/HL/LH/LL classification
   StructBias        m_bias;              // starts UNKNOWN - never implicitly bullish
   bool              m_initialized;

public:
   void              Init(void)
     {
      m_swings.Init(InpSwingLeft, InpSwingRight);
      m_lastSwingHigh = 0.0;
      m_lastSwingLow = 0.0;
      m_prevSwingHigh = 0.0;
      m_prevSwingLow = 0.0;
      m_prevClose = 0.0;
      m_prevCloseValid = false;
      m_lastHighConsumed = false;
      m_lastLowConsumed = false;
      m_lastEvent = STRUCT_NONE;
      m_lastSwingLabel = STRUCT_NONE;
      m_bias = BIAS_UNKNOWN;
      m_initialized = false;
     }

   // Re-evaluates structure using confirmed closed bars only. Should be
   // called once per new closed bar on the timeframe of interest.
   void              Update(CTimeframeData *tf)
     {
      m_lastEvent = STRUCT_NONE; // event flag is per-call, not sticky

      int startShift = InpSwingRight + 1;
      int scanWindow = 60;

      int hiShift = m_swings.FindLastSwingHigh(tf, startShift, scanWindow);
      int loShift = m_swings.FindLastSwingLow(tf, startShift, scanWindow);

      if(hiShift >= 0)
        {
         double h = tf.High(hiShift);
         if(!m_initialized || MathAbs(h - m_lastSwingHigh) > QXE_EPS)
           {
            m_prevSwingHigh = m_lastSwingHigh;
            m_lastSwingHigh = h;
            m_lastHighConsumed = false; // a fresh swing high is unbroken again
            ClassifyHigh();
           }
        }

      if(loShift >= 0)
        {
         double l = tf.Low(loShift);
         if(!m_initialized || MathAbs(l - m_lastSwingLow) > QXE_EPS)
           {
            m_prevSwingLow = m_lastSwingLow;
            m_lastSwingLow = l;
            m_lastLowConsumed = false;
            ClassifyLow();
           }
        }

      // BOS / CHoCH: EDGE-TRIGGERED. Fires only on the bar where the
      // close first crosses from <= level to > level (or >= to <), and
      // only once per swing (consumed flag) - never repeats every bar
      // that price simply remains beyond the level.
      double close1 = tf.Close(1);

      if(m_prevCloseValid && m_lastSwingHigh > 0.0 && !m_lastHighConsumed &&
         m_prevClose <= m_lastSwingHigh && close1 > m_lastSwingHigh)
        {
         m_lastEvent = (m_bias == BIAS_BULLISH) ? STRUCT_BOS_BULL : STRUCT_CHOCH_BULL;
         m_bias = BIAS_BULLISH;
         m_lastHighConsumed = true;
        }
      else if(m_prevCloseValid && m_lastSwingLow > 0.0 && !m_lastLowConsumed &&
              m_prevClose >= m_lastSwingLow && close1 < m_lastSwingLow)
        {
         m_lastEvent = (m_bias == BIAS_BEARISH) ? STRUCT_BOS_BEAR : STRUCT_CHOCH_BEAR;
         m_bias = BIAS_BEARISH;
         m_lastLowConsumed = true;
        }

      m_prevClose = close1;
      m_prevCloseValid = true;
      m_initialized = true;
     }

   StructBias        Bias(void)              const { return m_bias; }
   bool              IsBullishBias(void)      const { return m_bias == BIAS_BULLISH; }
   bool              IsBearishBias(void)      const { return m_bias == BIAS_BEARISH; }
   double            LastSwingHigh(void)      const { return m_lastSwingHigh; }
   double            LastSwingLow(void)       const { return m_lastSwingLow; }
   StructureEventType LastEvent(void)         const { return m_lastEvent; }
   StructureEventType LastSwingLabel(void)    const { return m_lastSwingLabel; }

   // True ONLY on the exact call where the event fired (edge-triggered,
   // not a persistent state) - callers must check this every bar, not cache it.
   bool              IsRecentBOS(void) const
     {
      return (m_lastEvent == STRUCT_BOS_BULL || m_lastEvent == STRUCT_BOS_BEAR);
     }

   bool              IsRecentCHoCH(void) const
     {
      return (m_lastEvent == STRUCT_CHOCH_BULL || m_lastEvent == STRUCT_CHOCH_BEAR);
     }

private:
   void              ClassifyHigh(void)
     {
      if(m_prevSwingHigh <= 0.0)
         return;
      m_lastSwingLabel = (m_lastSwingHigh > m_prevSwingHigh) ? STRUCT_HH : STRUCT_LH;
     }

   void              ClassifyLow(void)
     {
      if(m_prevSwingLow <= 0.0)
         return;
      m_lastSwingLabel = (m_lastSwingLow > m_prevSwingLow) ? STRUCT_HL : STRUCT_LL;
     }
  };

#endif // QXE_MARKETSTRUCTURE_MQH
