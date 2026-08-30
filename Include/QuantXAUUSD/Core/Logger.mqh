//+------------------------------------------------------------------+
//| Logger.mqh                                                       |
//| QUANT_XAUUSD_ENGINE - Unified logging                            |
//+------------------------------------------------------------------+
#ifndef QXE_LOGGER_MQH
#define QXE_LOGGER_MQH

#include "Config.mqh"

enum LogLevel
  {
   LOG_DEBUG = 0,
   LOG_INFO  = 1,
   LOG_WARN  = 2,
   LOG_ERROR = 3
  };

class CLogger
  {
private:
   bool              m_debugEnabled;
   string            m_prefix;

public:
                     CLogger(void) : m_debugEnabled(false), m_prefix("QXE") {}

   void              Init(bool debugEnabled, string prefix)
     {
      m_debugEnabled = debugEnabled;
      m_prefix = prefix;
     }

   void              Log(LogLevel level, string message)
     {
      if(level == LOG_DEBUG && !m_debugEnabled)
         return;

      string tag = "INFO";
      switch(level)
        {
         case LOG_DEBUG: tag = "DEBUG"; break;
         case LOG_INFO:  tag = "INFO";  break;
         case LOG_WARN:  tag = "WARN";  break;
         case LOG_ERROR: tag = "ERROR"; break;
        }
      PrintFormat("[%s][%s] %s", m_prefix, tag, message);
     }

   void              Debug(string message) { Log(LOG_DEBUG, message); }
   void              Info(string message)  { Log(LOG_INFO, message);  }
   void              Warn(string message)  { Log(LOG_WARN, message);  }
   void              Error(string message) { Log(LOG_ERROR, message); }
  };

// Global singleton instance used across the whole program.
CLogger g_Logger;

#endif // QXE_LOGGER_MQH
