//+------------------------------------------------------------------+
//| Constants.mqh                                                    |
//| QUANT_XAUUSD_ENGINE - Technical constants                        |
//|                                                                   |
//| Only fixed technical constants live here (array sizes, buffer    |
//| indices, etc). Trading parameters are NEVER hardcoded here -     |
//| they belong in Config.mqh as EA inputs.                          |
//+------------------------------------------------------------------+
#ifndef QXE_CONSTANTS_MQH
#define QXE_CONSTANTS_MQH

#define QXE_VERSION            "1.0.0"
#define QXE_SYSTEM_NAME        "QUANT_XAUUSD_ENGINE"

// Number of timeframes tracked by the data engine.
#define QXE_TF_COUNT            5

// Indices into timeframe arrays (order matters - keep consistent everywhere).
#define QXE_TF_IDX_D1            0
#define QXE_TF_IDX_H4            1
#define QXE_TF_IDX_H1            2
#define QXE_TF_IDX_M15           3
#define QXE_TF_IDX_M5            4

// History depth requested per timeframe (bars). Must be large enough
// for the longest lookback used by any indicator (e.g. EMA200 + margin).
#define QXE_HISTORY_D1           400
#define QXE_HISTORY_H4           1000
#define QXE_HISTORY_H1           1500
#define QXE_HISTORY_M15          2000
#define QXE_HISTORY_M5           3000

// Minimum bars required before the engine will evaluate anything.
#define QXE_MIN_BARS_REQUIRED    210

// Max objects tracked per visual category to avoid chart object explosion.
#define QXE_MAX_VISUAL_OBJECTS   200

// Journal / CSV
#define QXE_CSV_DELIM            ","

// Score engine
#define QXE_SCORE_MIN            0.0
#define QXE_SCORE_MAX            100.0

// Small epsilon for float comparisons on price/points.
#define QXE_EPS                  0.0000001

#endif // QXE_CONSTANTS_MQH
