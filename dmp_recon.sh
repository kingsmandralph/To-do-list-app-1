#!/usr/bin/env bash
# ============================================================
# DMP Bug Bounty - Passive Recon + JS Harvesting Script
# Program: Dossier Medical Partage (CNAM) - Private BBP
# Usage: bash dmp_recon.sh
# Requirements: curl, grep, sed, sort, uniq
# ============================================================

UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 CNAM-DPM-privateBBP"
OUT="dmp_output"
mkdir -p "$OUT/js" "$OUT/responses" "$OUT/endpoints"

TARGETS=(
  "https://www.dmp.gouv.fr"
  "https://www.dmp.fr"
  "https://auth.dmp.gouv.fr"
  "https://api.dmp.gouv.fr"
  "https://sip2.dmp.gouv.fr"
  "https://lps2.dmp.gouv.fr"
  "https://lps.dmp.gouv.fr"
  "https://web-mh.dmp.gouv.fr"
  "https://wps-cps.cv.dmp.gouv.fr"
)

echo "[*] Starting recon — $(date)"
echo "============================================================"

# ------------------------------------------------------------
# 1. Certificate Transparency - passive subdomain enum
# ------------------------------------------------------------
echo "[1] Querying crt.sh for subdomains..."
curl -sA "$UA" "https://crt.sh/?q=%25.dmp.gouv.fr&output=json" \
  | grep -oP '"name_value":"\K[^"]+' \
  | sed 's/\\n/\n/g' \
  | sort -u \
  | tee "$OUT/subdomains_crtsh.txt"
echo "[*] Found $(wc -l < "$OUT/subdomains_crtsh.txt") subdomains via crt.sh"

# ------------------------------------------------------------
# 2. Fetch each target - grab headers + HTML
# ------------------------------------------------------------
echo ""
echo "[2] Fetching targets..."
for TARGET in "${TARGETS[@]}"; do
  HOSTNAME=$(echo "$TARGET" | sed 's|https\?://||;s|/.*||')
  echo "  -> $TARGET"

  curl -sA "$UA" \
    -L \
    --max-time 15 \
    -D "$OUT/responses/${HOSTNAME}_headers.txt" \
    -o "$OUT/responses/${HOSTNAME}_body.html" \
    "$TARGET"

  # Extract JS file URLs from HTML
  grep -oP 'src=["'"'"']\K[^"'"'"']+\.js[^"'"'"']*' \
    "$OUT/responses/${HOSTNAME}_body.html" 2>/dev/null \
    | sed "s|^/|$TARGET/|" \
    >> "$OUT/js/${HOSTNAME}_js_urls.txt"

  # Extract interesting paths/endpoints
  grep -oP '(api|/v[0-9]|/rest|/graphql|/query|/auth|/login|/token|/oauth)[^"'"'"' <>]+' \
    "$OUT/responses/${HOSTNAME}_body.html" 2>/dev/null \
    | sort -u \
    >> "$OUT/endpoints/${HOSTNAME}_paths.txt"
done

# ------------------------------------------------------------
# 3. Download all discovered JS bundles
# ------------------------------------------------------------
echo ""
echo "[3] Downloading JS bundles..."
cat "$OUT/js/"*.txt 2>/dev/null | sort -u > "$OUT/js/all_js_urls.txt"
echo "[*] Total JS URLs: $(wc -l < "$OUT/js/all_js_urls.txt")"

while IFS= read -r JS_URL; do
  [[ -z "$JS_URL" ]] && continue
  FILENAME=$(echo "$JS_URL" | md5sum | cut -d' ' -f1).js
  echo "  -> $JS_URL"
  curl -sA "$UA" \
    --max-time 20 \
    -o "$OUT/js/$FILENAME" \
    "$JS_URL"
  echo "$JS_URL -> $FILENAME" >> "$OUT/js/url_to_file_map.txt"
done < "$OUT/js/all_js_urls.txt"

# ------------------------------------------------------------
# 4. Analyze JS for secrets + endpoints
# ------------------------------------------------------------
echo ""
echo "[4] Analyzing JS bundles for secrets and endpoints..."

JS_ANALYSIS="$OUT/js_analysis.txt"
echo "JS Analysis Report - $(date)" > "$JS_ANALYSIS"
echo "============================================================" >> "$JS_ANALYSIS"

for JS_FILE in "$OUT/js/"*.js; do
  [[ ! -f "$JS_FILE" ]] && continue
  URL=$(grep "$JS_FILE" "$OUT/js/url_to_file_map.txt" 2>/dev/null | cut -d'>' -f2 | xargs)
  echo "" >> "$JS_ANALYSIS"
  echo "FILE: $JS_FILE ($URL)" >> "$JS_ANALYSIS"
  echo "------------------------------------------------------------" >> "$JS_ANALYSIS"

  # API endpoints
  echo "[ENDPOINTS]" >> "$JS_ANALYSIS"
  grep -oP '["'"'"'`](/[a-zA-Z0-9_/\-]+)+["'"'"'`]' "$JS_FILE" \
    | grep -v "\.png\|\.svg\|\.css\|\.woff\|\.ttf\|\.eot\|\.ico" \
    | sort -u >> "$JS_ANALYSIS"

  # API base URLs
  echo "[API BASE URLS]" >> "$JS_ANALYSIS"
  grep -oP 'https?://[a-zA-Z0-9._/\-]+' "$JS_FILE" \
    | sort -u >> "$JS_ANALYSIS"

  # Potential secrets
  echo "[POTENTIAL SECRETS]" >> "$JS_ANALYSIS"
  grep -iP '(api[_-]?key|apikey|secret|token|password|passwd|auth|bearer|client[_-]?id|client[_-]?secret|private[_-]?key)\s*[:=]\s*["'"'"'][^"'"'"']{8,}' \
    "$JS_FILE" >> "$JS_ANALYSIS"

  # AWS keys
  echo "[AWS KEYS]" >> "$JS_ANALYSIS"
  grep -oP 'AKIA[0-9A-Z]{16}' "$JS_FILE" >> "$JS_ANALYSIS"

  # JWT tokens
  echo "[JWTs]" >> "$JS_ANALYSIS"
  grep -oP 'eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+' "$JS_FILE" \
    >> "$JS_ANALYSIS"

  # postMessage handlers
  echo "[postMessage HANDLERS]" >> "$JS_ANALYSIS"
  grep -oP '.{0,100}(addEventListener.*message|postMessage|onmessage).{0,100}' \
    "$JS_FILE" >> "$JS_ANALYSIS"

  # GraphQL
  echo "[GRAPHQL]" >> "$JS_ANALYSIS"
  grep -oP '.{0,50}(query|mutation|subscription|__schema|__type|gql|graphql).{0,100}' \
    "$JS_FILE" | head -20 >> "$JS_ANALYSIS"
done

# ------------------------------------------------------------
# 5. Check common sensitive paths
# ------------------------------------------------------------
echo ""
echo "[5] Probing common sensitive paths..."
PATHS=(
  "/robots.txt"
  "/sitemap.xml"
  "/.well-known/openid-configuration"
  "/.well-known/oauth-authorization-server"
  "/api"
  "/api/v1"
  "/api/v2"
  "/api/v3"
  "/graphql"
  "/swagger.json"
  "/swagger-ui.html"
  "/openapi.json"
  "/api-docs"
  "/v2/api-docs"
  "/actuator"
  "/actuator/env"
  "/actuator/health"
  "/actuator/mappings"
  "/.env"
  "/config.json"
  "/package.json"
  "/webpack-stats.json"
  "/asset-manifest.json"
)

SENSITIVE_OUT="$OUT/sensitive_paths.txt"
echo "Sensitive Path Probe - $(date)" > "$SENSITIVE_OUT"

for TARGET in "${TARGETS[@]}"; do
  HOSTNAME=$(echo "$TARGET" | sed 's|https\?://||;s|/.*||')
  echo "" >> "$SENSITIVE_OUT"
  echo "=== $TARGET ===" >> "$SENSITIVE_OUT"
  for PATH_CHECK in "${PATHS[@]}"; do
    STATUS=$(curl -sA "$UA" \
      --max-time 10 \
      -o /dev/null \
      -w "%{http_code}" \
      "${TARGET}${PATH_CHECK}")
    if [[ "$STATUS" != "404" && "$STATUS" != "000" && "$STATUS" != "403" ]]; then
      echo "  [$STATUS] ${TARGET}${PATH_CHECK}" | tee -a "$SENSITIVE_OUT"
    fi
  done
done

# ------------------------------------------------------------
# 6. OpenID Connect / OAuth discovery
# ------------------------------------------------------------
echo ""
echo "[6] Probing OAuth/OIDC endpoints..."
OIDC_TARGETS=(
  "https://auth.dmp.gouv.fr/.well-known/openid-configuration"
  "https://auth.dmp.gouv.fr/.well-known/oauth-authorization-server"
  "https://auth.dmp.gouv.fr/oauth/authorize"
  "https://auth.dmp.gouv.fr/oauth/token"
  "https://auth.dmp.gouv.fr/api"
)

OIDC_OUT="$OUT/oidc_discovery.txt"
echo "OIDC/OAuth Discovery - $(date)" > "$OIDC_OUT"
for URL in "${OIDC_TARGETS[@]}"; do
  echo "" >> "$OIDC_OUT"
  echo "=== GET $URL ===" >> "$OIDC_OUT"
  curl -sA "$UA" \
    --max-time 10 \
    -D - \
    "$URL" >> "$OIDC_OUT"
done

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------
echo ""
echo "============================================================"
echo "[*] Recon complete — $(date)"
echo "[*] Output directory: $OUT/"
echo ""
echo "Key files to paste back for analysis:"
echo "  $OUT/subdomains_crtsh.txt"
echo "  $OUT/js_analysis.txt"
echo "  $OUT/sensitive_paths.txt"
echo "  $OUT/oidc_discovery.txt"
echo "  $OUT/responses/*_headers.txt"
echo ""
echo "Paste contents of these files to Claude for deep analysis."
echo "============================================================"
