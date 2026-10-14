#!/usr/bin/env bash
# GML CI checks for gn.gml
# Runs basic static analysis on .gml files that GameMaker's compiler would
# otherwise only catch at build time.

ERRORS=0
WARNINGS=0

error() {
    echo "ERROR: $1:$2: $3"
    ERRORS=$((ERRORS + 1))
}

warn() {
    echo "WARN:  $1:$2: $3"
    WARNINGS=$((WARNINGS + 1))
}

# Find all .gml files
GML_FILES=$(find scripts objects -name '*.gml' 2>/dev/null)

if [ -z "$GML_FILES" ]; then
    echo "No .gml files found"
    exit 0
fi

echo "Checking GML files..."
echo ""

for file in $GML_FILES; do
    # ── 1. Balanced braces ──────────────────────────────────────────────
    open=$(grep -o '{' "$file" | wc -l || true)
    close=$(grep -o '}' "$file" | wc -l || true)
    if [ "$open" -ne "$close" ]; then
        error "$file" "-" "Unbalanced braces: $open opening vs $close closing"
    fi

    # ── 2. Balanced parentheses ─────────────────────────────────────────
    open=$(grep -o '(' "$file" | wc -l || true)
    close=$(grep -o ')' "$file" | wc -l || true)
    if [ "$open" -ne "$close" ]; then
        error "$file" "-" "Unbalanced parentheses: $open opening vs $close closing"
    fi

    # ── 3. Balanced square brackets ─────────────────────────────────────
    open=$(grep -o '\[' "$file" | wc -l || true)
    close=$(grep -o '\]' "$file" | wc -l || true)
    if [ "$open" -ne "$close" ]; then
        error "$file" "-" "Unbalanced square brackets: $open opening vs $close closing"
    fi

    # ── 4. Line-level checks ───────────────────────────────────────────
    line_num=0
    while IFS= read -r line; do
        line_num=$((line_num + 1))

        # Strip single-line comments for analysis
        stripped=$(echo "$line" | sed 's|//.*||')

        # Skip blank / comment-only lines
        if echo "$stripped" | grep -qE '^\s*$'; then
            continue
        fi

        # 4a. Accidental assignment in if/while conditions
        #     Matches if(...= ...) but not == != <= >=
        if echo "$stripped" | grep -qP '\b(if|while)\s*\(.*[^!=<>]=[^=].*\)'; then
            if ! echo "$stripped" | grep -qP '==|!=|<=|>='; then
                warn "$file" "$line_num" "Possible accidental assignment in condition"
            fi
        fi

        # 4b. Trailing whitespace
        if echo "$line" | grep -qP '\s+$'; then
            warn "$file" "$line_num" "Trailing whitespace"
        fi

    done < "$file"
done

# ── 5. Project integrity: check .yyp references ───────────────────────
if [ -f "gn.gml.yyp" ]; then
    echo "Checking project integrity..."

    # Extract resource paths from .yyp and verify they exist
    refs=$(grep -oP '"resourcePath":\s*"[^"]*\.yy"' gn.gml.yyp 2>/dev/null | grep -oP '"[^"]*\.yy"' | tr -d '"' || true)
    for ref in $refs; do
        if [ ! -f "$ref" ]; then
            error "gn.gml.yyp" "-" "Referenced resource missing: $ref"
        fi
    done
fi

echo ""
echo "──────────────────────────────────"
echo "Results: $ERRORS error(s), $WARNINGS warning(s)"
echo "──────────────────────────────────"

if [ "$ERRORS" -gt 0 ]; then
    exit 1
fi

exit 0
