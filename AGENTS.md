# Capital Gains Calculator -- Agent Notes

Gotchas and operational notes for working with this codebase.

## Docker Usage

- Build: `docker buildx build --platform linux/amd64 --tag capital-gains-calculator .`
- The image entrypoint is `/bin/bash` with workdir `/data`. The `cgt-calc` CLI is available inside the container.
- Mount your data directories into `/data/` subpaths. The `--trading212-dir` flag expects a directory (not a single file).
- Do NOT put non-Trading-212 CSV files (like `isin_translation.csv`) in the trading212 directory. The parser will try to parse every `*.csv` in that dir and fail on unknown column headers.

### Example Docker Run

```bash
docker run --rm \
  -v /path/to/trading212-csvs:/data/trading212 \
  -v /path/to/output:/data/out \
  capital-gains-calculator:latest \
  cgt-calc --trading212-dir /data/trading212 \
    --isin-translation-file /data/out/isin_translation.csv \
    --year 2025 -o /data/out/report.pdf
```

## Trading 212 Parser Gotchas

- The "Stock distribution" action type is NOT supported upstream. It was added locally by mapping it to `ActionType.TRANSFER` in `cgt_calc/parsers/trading212.py:action_from_str()`. Trading 212 uses "Stock distribution" when a fund is delisted from one exchange and the broker gives you shares under the new ticker. It is paired with a "Market sell" at price 0 for the old ticker. Together they represent a forced exchange conversion, not a real disposal + acquisition. Both should be no-ops for CGT so the cost basis transfers to the new ticker.
- A "Market sell" with price 0 and total 0 is also a delisting/exchange-swap artifact. The parser now detects this (sell + amount==0 + price_foreign==0) and converts it to `ActionType.TRANSFER`. Without this fix, the calculator records a phantom loss (full cost basis disposed at 0 proceeds) and a matching phantom gain when the new-ticker shares are later sold.
- When an exchange swap happens (old ticker delisted, new ticker issued), add the new-to-old mapping in `TICKER_RENAMES` in `cgt_calc/const.py` (e.g., `"IEGE": "IBGE"`) so both tickers use the same Section 104 pool. The cost basis then flows through correctly.
- Trading 212 sometimes uses different ticker symbols for the same ISIN across transactions (e.g., `IBGE` vs `IEGE` for ISIN `IE00B3FH7618`). The ISIN converter will reject this. Fix by providing an `--isin-translation-file` with both tickers on the same row: `IE00B3FH7618,IBGE,IEGE`.
- ISIN translation file format: `ISIN,symbol` header, then one row per ISIN. Multiple tickers for the same ISIN go as extra columns on the same row (NOT separate rows).
- A minor price rounding warning ("Discrepancy per Share: 0.016") can appear. This is harmless rounding between the per-share price and the total after fees/FX conversion.

## Stock Split Handling

- `STOCK_SPLIT` action type requires a pre-existing holding of that ticker. It computes a multiplier from `(acquired + holding) / holding`. If the holding is zero, it will crash with `DivisionByZero`.
- This is why "Stock distribution" should NOT map to `STOCK_SPLIT` -- the distributed shares may use a different ticker than the original purchases.

## Key Files

| File | Purpose |
|------|---------|
| `cgt_calc/parsers/trading212.py` | Trading 212 CSV parser; `action_from_str()` maps action labels to ActionType enums |
| `cgt_calc/isin_converter.py` | ISIN-to-ticker resolution (bundled data + OpenFIGI API + user-provided file) |
| `cgt_calc/main.py` | Main calculation engine; handles acquisitions/disposals/splits |
| `cgt_calc/resources/initial_prices.csv` | Bundled stock prices for vesting/activity events |
