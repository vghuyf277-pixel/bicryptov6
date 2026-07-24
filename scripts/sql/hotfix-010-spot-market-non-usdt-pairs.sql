UPDATE exchange_market
SET status = 0
WHERE pair = 'BTC'
   OR (currency = 'LINK' AND pair = 'ETH');

-- hotfix-010: Deactivate non-USDT spot market pairs that KuCoin doesn't carry.
--
-- KuCoin only carries USDT-quoted pairs for most altcoins. BTC-quoted pairs
-- (SOL/BTC, ETH/BTC) and ETH-quoted pairs (LINK/ETH) cause a hard ccxt
-- BadSymbol error that crashes the processCurrenciesPrices cron every 2 min,
-- blocking ALL spot price updates entirely.
--
-- Root cause of the "0 statements" bug: import-sql.js splits on ';' followed
-- by a newline. A single-statement file with leading comment lines gets merged
-- into one chunk starting with '--', which the filter rejects. SQL must come
-- first so it parses as a standalone statement.
--
-- Idempotent — safe to run on every boot.
-- Also mirrored in activate-all.js (deactivate BTC-quoted rows after bulk enable).
