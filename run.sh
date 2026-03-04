#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="capital-gains-calculator"
DATA_DIR="${SCRIPT_DIR}/data"
OUT_DIR="${SCRIPT_DIR}/out"
TRANSLATION_DIR="${SCRIPT_DIR}/translation"

# Default to the last ended UK tax year (April to April).
# Tax year 2025/26 runs 6 Apr 2025 - 5 Apr 2026, referred to as --year 2025.
YEAR="${1:-}"

if [[ -z "$YEAR" ]]; then
    echo "Usage: ./run.sh <tax-year>"
    echo "  e.g. ./run.sh 2025   (for tax year 2025/26)"
    exit 1
fi

# Check data dir has CSVs
csv_count=$(find "$DATA_DIR" -maxdepth 1 -name '*.csv' ! -name 'isin_translation.csv' 2>/dev/null | wc -l | tr -d ' ')
if [[ "$csv_count" -eq 0 ]]; then
    echo "No Trading 212 CSV files found in $DATA_DIR"
    echo "Export your transactions from Trading 212 and drop them in the data/ folder."
    exit 1
fi

echo "Found $csv_count Trading 212 CSV file(s) in data/"

# Build image (cached layers make this fast after first run)
echo "Building Docker image..."
docker buildx build --platform linux/amd64 --tag "$IMAGE_NAME" "$SCRIPT_DIR" --quiet

# Ensure output dir exists
mkdir -p "$OUT_DIR"

# Build the command
CMD=(cgt-calc --trading212-dir /data/trading212 --year "$YEAR" -o /data/out/report.pdf)

# Use ISIN translation file if it exists (kept in translation/ to avoid the
# Trading 212 parser trying to parse it as a transaction CSV).
if [[ -f "$TRANSLATION_DIR/isin_translation.csv" ]]; then
    CMD+=(--isin-translation-file /data/translation/isin_translation.csv)
fi

# Run
echo "Running cgt-calc for tax year ${YEAR}/$(( YEAR + 1 ))..."
docker run --rm \
    -v "$DATA_DIR":/data/trading212:ro \
    -v "$TRANSLATION_DIR":/data/translation:ro \
    -v "$OUT_DIR":/data/out \
    "$IMAGE_NAME":latest \
    "${CMD[@]}"

echo ""
echo "Report saved to: ${OUT_DIR}/report.pdf"
