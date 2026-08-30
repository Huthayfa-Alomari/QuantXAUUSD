//+------------------------------------------------------------------+
//| SwingDetector.mqh                                                |
//| QUANT_XAUUSD_ENGINE - Deterministic swing high/low detection     |
//|                                                                   |
//| A bar at shift `right` is a confirmed swing high if it is the    |
//| highest of [right-left .. right+... wait] - see method docstring.|
//| Detection only confirms once `SwingRight` bars have closed after |
//| the candidate bar, so it NEVER repaints.                         |
//+------------------------------------------------------------------+
#ifndef QXE_SWINGDETECTOR_MQH
#define QXE_SWINGDETECTOR_MQH

#include "../Data/TimeframeData.mqh"
#include "../Core/Types.mqh"

class CSwingDetector
  {
private:
   int               m_left;
   int               m_right;

public:
   void              Init(int left, int right)
     {
      m_left = MathMax(1, left);
      m_right = MathMax(1, right);
     }

   // Checks whether the bar at `shift` (>= m_right, so it and all bars
   // to its left/right are fully closed) is a confirmed swing high.
   // shift indexing: 1 = last closed bar. Candidate bar is at
   // (shift + m_right); we look m_left bars further left and m_right
   // bars to the right (i.e. towards shift=1) of the candidate.
   bool              IsSwingHigh(CTimeframeData *tf, int candidateShift) const
     {
      double candidate = tf.High(candidateShift);
      for(int i = 1; i <= m_left; i++)
         if(tf.High(candidateShift + i) >= candidate)
            return false;
      for(int i = 1; i <= m_right; i++)
         if(tf.High(candidateShift - i) >= candidate)
            return false;
      return true;
     }

   bool              IsSwingLow(CTimeframeData *tf, int candidateShift) const
     {
      double candidate = tf.Low(candidateShift);
      for(int i = 1; i <= m_left; i++)
         if(tf.Low(candidateShift + i) <= candidate)
            return false;
      for(int i = 1; i <= m_right; i++)
         if(tf.Low(candidateShift - i) <= candidate)
            return false;
      return true;
     }

   // Scans backwards from `startShift` and returns the shift of the most
   // recent confirmed swing high/low, or -1 if none found within maxScan.
   int               FindLastSwingHigh(CTimeframeData *tf, int startShift, int maxScan) const
     {
      for(int s = startShift; s < startShift + maxScan; s++)
        {
         if(s + m_left >= tf.Bars())
            break;
         if(IsSwingHigh(tf, s))
            return s;
        }
      return -1;
     }

   int               FindLastSwingLow(CTimeframeData *tf, int startShift, int maxScan) const
     {
      for(int s = startShift; s < startShift + maxScan; s++)
        {
         if(s + m_left >= tf.Bars())
            break;
         if(IsSwingLow(tf, s))
            return s;
        }
      return -1;
     }
  };

#endif // QXE_SWINGDETECTOR_MQH
