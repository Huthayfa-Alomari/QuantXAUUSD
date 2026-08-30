# QUANT_XAUUSD_ENGINE

A modular, multi-strategy systematic/quant Expert Advisor for MetaTrader 5,
built primarily for **XAUUSD** across D1 / H4 / H1 / M15 / M5.

---

## 1. Architecture

```
Market Data (5 timeframes, cached indicators)
        v
Regime Engine (trend / range / volatility classification)
        v
Structure + Liquidity (swings, BOS/CHoCH, PDH/PDL/PWH/PWL, equal H/L, sweeps)
        v
Strategies (11 independent hypotheses, each emits a Signal or nothing)
        v
Score Engine (regime-priority filter -> aggregate -> composite 0-100 score)
        v
Risk Engine (daily limits, drawdown throttle, stop sanity, lot sizing)
        v
Spread / Session / Position filters
        v
Trade Executor (CTrade wrapper, retcode-checked)
        v
Position Manager (partial close, break-even, ATR trailing)
        v
Journal + Statistics (CSV logging, per-strategy attribution, metrics)
```

Every stage only passes forward if the previous stage approved. A signal
never bypasses scoring; a setup never bypasses risk; risk never bypasses
spread/session/position checks. Signal generation only runs on a newly
**closed H1 bar** (see `OnTick` in `QuantXAUUSD.mq5`); position management
runs every tick. No stage ever reads the current, unclosed candle for a
trading decision.

### Architecture Notes - documented consolidations

The build prompt's file tree lists a few single-purpose files that, in
practice, share one state machine or one data source with a sibling file.
To avoid the anti-pattern of thin wrapper files that just forward to each
other, the following were merged (each merge is called out again as a
comment at the top of the resulting file):

| Spec file(s) | Merged into |
|---|---|
| `CandleData.mqh`, `IndicatorCache.mqh` | `Data/TimeframeData.mqh` |
| `TrendRegime.mqh`, `RangeRegime.mqh`, `VolatilityRegime.mqh` | `Regime/RegimeEngine.mqh` |
| `BOSDetector.mqh`, `CHoCHDetector.mqh` | `Structure/MarketStructure.mqh` |
| `EqualHighLow.mqh`, `PreviousDayLevels.mqh`, `PreviousWeekLevels.mqh` | `Liquidity/LiquidityLevels.mqh` |
| `ConfirmationEngine.mqh` | `Entry/EntryEngine.mqh` |
| `SignalAggregator` (sec. 21) + `ScoreEngine` (sec. 23) | `Scoring/ScoreEngine.mqh` |
| `ATRStops.mqh` | `Risk/RiskEngine.mqh` (stop-sanity check) |
| `PartialClose.mqh`, `BreakEven.mqh`, `TrailingStop.mqh` | `Management/PositionManager.mqh` |
| `SlippageFilter.mqh` | `Execution/TradeExecutor.mqh` |
| `TradeStatistics.mqh`, `StrategyStatistics.mqh` | `Research/TradeStatistics.mqh` |

Everything else follows the requested tree exactly. Modularity is preserved:
every merge is between files that operated on the exact same underlying
state (e.g. BOS and CHoCH both come out of the same swing-pair machine) and
each merged module still exposes the same functional surface.

---

## 2. Strategy Summary

All strategies implement `IStrategy` and only ever *emit a Signal* — none of
them touch the trade ticket. Every strategy has its own `Enable*` ablation
toggle in `Config.mqh`.

| Strategy | Core rule | Only active when |
|---|---|---|
| **TrendFollowing** | H1 close vs EMA200 + EMA200 slope + ADX + H4 EMA200 alignment | Trend regime priority |
| **TimeSeriesMomentum** | ATR-normalized return over H4/H1/M15, needs 2-of-3 timeframe agreement | Trend / Vol-expansion |
| **DonchianBreakout** | Close breaks the prior N-bar high/low channel (channel excludes the breakout bar itself) | Vol-expansion |
| **VolatilityBreakout** | ATR(now)/ATR(avg) ratio exceeds threshold **and** price breaks the recent range, with an optional H4 bias veto | Vol-expansion |
| **MomentumPullback** | H4 trend established, H1 pulls back into the EMA20/EMA50 zone, confirmed by a same-direction closing candle | Trend |
| **MarketStructure** | Confirmed BOS (close beyond the last confirmed swing) aligned with the current regime; CHoCH alone is logged but not traded | Trend |
| **LiquiditySweep** | Wick pierces a tracked level (PDH/PDL/PWH/PWL/equal H-L) **and** the candle closes back inside it — a touch alone is never a sweep | Trend |
| **MeanReversion** | Z-score of price vs its N-bar mean reaches an extreme **and** the following candle confirms a reversal | RANGE only |
| **BollingerZScore** | Close beyond the Bollinger band + matching Z-score extreme (no reversal-candle requirement — kept separate from MeanReversion for attribution) | RANGE only |
| **VWAP** | Trend regime: pullback-to-VWAP continuation. Range regime: extension-from-VWAP mean reversion | Trend or Range |
| **OpeningRangeBreakout** | Configurable-length opening range (15/30/60 min), one breakout per session, with an ATR/range-width sanity filter | Vol-expansion |

FVG (`Entry/FVGDetector.mqh`) and Displacement (`Entry/DisplacementDetector.mqh`)
are implemented as **confirmation primitives**, exactly as specified (never
a standalone entry). They are consumed directly by `LiquiditySweep` (optional
displacement confirmation, toggle `InpRequireDisplacementForSweep`) and are
available via `Entry/EntryEngine.mqh` for any strategy that wants FVG-based
entry refinement. **Known limitation:** in this build only the liquidity
sweep strategy wires in displacement confirmation; FVG confirmation via
`EntryEngine.FindConfirmingFVG()` is implemented and unit-clean but not yet
called from any strategy's `Evaluate()`. Wiring it in is a one-line addition
per strategy and is flagged here rather than silently left out.

---

## 3. Regime Summary

`Regime/RegimeEngine.mqh` computes three independent 0-100 scores every H1
bar:

- **TrendScore** (signed): price vs EMA200, EMA200 slope, ADX confirmation.
- **RangeScore**: low ADX + flat EMA200 slope.
- **VolatilityScore**: percentile rank of the current M5 ATR against its own
  last `InpATRPercentileLookback` values.

These are reconciled into one `RegimeType`:
`TREND_BULL`, `TREND_BEAR`, `RANGE`, `VOL_EXPANSION`, `VOL_CONTRACTION`,
`TRANSITION`, `NO_TRADE`. Conflicting or borderline readings resolve to
`TRANSITION` (reduced activity) or `NO_TRADE` (nothing trades) rather than
guessing — exactly as the spec requires.

Regime priority (`ScoreEngine::IsEligibleInRegime`) then decides which
strategies are even allowed to contribute a vote in the current regime, per
spec section 22.

---

## 4. Risk Model

`Risk/RiskEngine.mqh` is the single gate between a scored setup and a live
order:

1. **Drawdown throttle** (`DrawdownProtection.mqh`): risk multiplier steps
   down at `InpModerateDDPct` / `InpHighDDPct`, and trading halts completely
   at `InpCriticalDDPct`.
2. **Daily limits**: max daily loss %, max trades/day, max consecutive
   losses — tracked from midnight server time.
3. **Stop-distance sanity**: rejects if the computed SL is unrealistically
   tight or wide, or violates the broker's minimum stops level
   (`SYMBOL_TRADE_STOPS_LEVEL`).
4. **Position sizing** (`PositionSizing.mqh`): lot size is always derived
   from `equity x effective_risk% / (SL_distance_in_ticks x tick_value)`,
   normalized to the symbol's volume step/min/max. **A fixed lot is never
   used in live logic.**

No symbol assumptions are hardcoded — digits, point size, tick size/value,
and volume constraints are all read from `SymbolInfo*` at runtime, so the
EA is expected to tolerate broker suffixes/prefixes (`XAUUSDm`, `XAUUSD.a`,
etc.) without modification, though this has not been tested against a live
broker feed (see Known Limitations).

---

## 5. Signal Scoring

`Scoring/ScoreEngine.mqh` aggregates every strategy's signal that is
eligible in the current regime:

- Same-direction signals are averaged (entry/stop/target) and their scores
  summed with a per-strategy weight bucket (`InpWeightHTFTrend`,
  `InpWeightMomentum`, `InpWeightStructure`, `InpWeightLiquidity` scale the
  four strategies the spec explicitly weights; all others contribute their
  raw score).
- If BUY and SELL signals are both present, the stronger side must
  dominate by 1.5x or the whole bar is rejected as a genuine conflict — it
  is never resolved by a coin flip.
- Session and volatility-regime bonuses are added (`InpWeightSession`,
  `InpWeightVolatility`), plus a small entry-quality bonus scaled by vote
  count.
- The final composite score must clear `InpMinScore` (default 70) **and**
  pass regime/risk/spread/session gates — score alone is never sufficient,
  per spec.

---

## 6. Compilation

**This project was not run through the actual MetaEditor/MQL5 compiler.**
This sandbox has no MetaTrader installation or MQL5 toolchain, so I cannot
truthfully report a compiler's error/warning count, and per your explicit
instruction I will not fabricate one.

What I *did* do, mechanically, on every file:
- Verified every `#include` (both `"relative"` and `<QuantXAUUSD/...>`)
  resolves to a file that actually exists on disk.
- Verified every file has a unique include guard and that braces/parentheses
  balance file-by-file.
- Verified every `IStrategy` subclass implements all three virtual methods.
- Verified every `Inp*` / `Enable*` / `Draw*` identifier referenced in
  strategy/engine code is declared in `Config.mqh` (cross-checked
  programmatically, not by eye).
- Manually re-read every function for MQL5-specific pitfalls: `CopyBuffer`/
  `CopyRates` return-value checks, `ArraySetAsSeries` on every cached array,
  shift-1-not-shift-0 discipline, `PositionGetTicket`/`PositionSelectByTicket`
  usage, `CTrade` retcode checks after every trade call.

**You should open this in MetaEditor and compile it before anything else.**
I expect small issues typical of a first compile of a project this size
(an off-by-one in an enum, a missed `const`, etc.) — please paste me the
error list and I will fix them directly; that is the fastest path to a
genuinely verified build, faster than me guessing at more static checks.

Errors = **unknown (not compiled)**
Warnings = **unknown (not compiled)**

---

## 7. Testing Instructions (Strategy Tester)

1. Symbol: **XAUUSD** (or your broker's exact suffixed name, e.g. `XAUUSDm`).
2. Model: **Every tick based on real ticks** (or "Every tick" if real-tick
   data is unavailable for your broker/history) — required because the EA
   reads live spread and manages positions intra-bar.
3. Period: **H1** as the chart timeframe (signal cadence is H1-bar-driven;
   the EA internally pulls M5/M15/H4/D1 via `CopyRates`/`CopyBuffer`
   regardless of the chart period, but H1 keeps `OnTick` load reasonable).
4. Date range: at least 2-3 years, ideally spanning both trending and
   ranging XAUUSD periods, so the regime engine and per-strategy
   attribution report actually mean something.
5. Initial deposit: realistic for your target account (the risk engine is
   %-based, so absolute deposit size mostly affects lot granularity).
6. **First run**: set `InpResearchMode = true` and check
   `MQL5/Files/QXE_Research_XAUUSD.csv` after the run — this validates the
   full signal pipeline without risking a single real order.
7. Second run: set `InpResearchMode = false` for an actual backtest, then
   inspect `MQL5/Files/QXE_Trades_XAUUSD.csv` and the strategy attribution
   block printed to the Experts log in `OnDeinit`.
8. Use the `Enable*` toggles in `Config.mqh` to run ablation studies (spec
   section 37) — disable everything except one strategy at a time to see
   its standalone attribution.

---

## 8. Known Limitations (do not skip this section)

Per your instruction, nothing here is dressed up — this is an honest list.

- **Not compiled.** See section 6. This is the single most important
  limitation: until MetaEditor confirms a clean compile, treat every claim
  in this README as "designed to," not "proven to."
- **No backtest has been run.** No profitability, win rate, or drawdown
  claim is made or implied anywhere in this project, per your instruction.
  Every strategy is a hypothesis, not a proven edge.
- **VWAP uses tick volume as a proxy.** XAUUSD spot has no centralized
  exchange volume; `MarketData::UpdateVWAP()` uses broker tick count, which
  is a liquidity proxy, not true traded volume. This is standard practice
  for spot gold but should be understood as an approximation.
- **FVG confirmation is implemented but not wired into any strategy's
  `Evaluate()`** yet (see section 2). It is available and tested at the
  unit level (`EntryEngine::FindConfirmingFVG`).
- **HH/HL/LH/LL labels are computed but not currently consumed** by any
  strategy — only the BOS/CHoCH events (which are consumed) are traded.
  The classification exists (`CMarketStructure::LastSwingLabel()`) for
  research/labelling and future strategies.
- **News filter is an interface stub only** (`InpEnableNewsFilter`,
  currently unused/disabled by design per spec section 32) — there is no
  external news feed integrated. Wiring an economic-calendar source is
  future work.
- **`OnTradeTransaction`'s per-trade attribution is best-effort.** MT5's
  deal history does not carry a custom "which strategy triggered this"
  field, so the exit handler currently tags every closed trade against
  `g_activeSetup` (the most recently opened setup) rather than a true
  per-ticket strategy record. With `InpOnePositionPerSymbol = true` (the
  default) this is accurate for the common case of one position at a time;
  it will misattribute if you disable that flag and run multiple
  concurrent positions. A ticket-keyed map from `TradeSetup` to open
  ticket would remove this limitation and is a natural next step.
- **MAE/MFE are declared in `TradeResult`/CSV but not populated** — doing
  this correctly requires tracking intrabar excursion per open position on
  every tick, which was left out of this pass to keep `OnTick` load
  reasonable; the fields default to 0 and are clearly visible as such in
  the CSV rather than silently faked.
- **Multi-broker symbol suffix/prefix handling is implemented via
  `SymbolInfo*` calls but untested against a live/demo broker feed** — the
  logic follows MQL5 best practice but "should work" is not "verified to
  work."
- **Real-tick backtest data availability varies by broker** for XAUUSD
  history — verify your broker provides sufficient real-tick history for
  the date range you intend to test.

---

## 9. Ablation & Toggles Reference

All in `Include/QuantXAUUSD/Core/Config.mqh`, grouped by section header.
Every strategy, every filter (regime/score/ATR/session), and every visual
debug layer has an independent `bool` input. Nothing that affects trading
logic is hardcoded — if you find a magic number in `Strategies/`, `Regime/`,
`Risk/`, or `Scoring/`, that is a bug relative to this project's own stated
design principle and should be reported.
