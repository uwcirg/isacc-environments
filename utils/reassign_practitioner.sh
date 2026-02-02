#!/bin/bash

DOCKER_CONTAINER="femr"
FHIR_BASE_URL="http://fhir-internal:8080/fhir"
# prod
OLD_PRACTITIONER="Practitioner/6"
NEW_PRACTITIONER="Practitioner/7"
NEW_DISPLAY="Wright, Riley"
# eval
#OLD_PRACTITIONER="Practitioner/699"
#NEW_PRACTITIONER="Practitioner/700"
#NEW_DISPLAY="Wright, Barbara"
# eval 2
#OLD_PRACTITIONER="Practitioner/21"
#NEW_PRACTITIONER="Practitioner/699"
#NEW_DISPLAY="Evanson, Anna"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "Searching for patients with generalPractitioner: $OLD_PRACTITIONER"

# Search for patients with the specific general practitioner
SEARCH_RESPONSE=$(docker-compose exec -T ${DOCKER_CONTAINER} curl -s -X GET \
  "${FHIR_BASE_URL}/Patient?general-practitioner=${OLD_PRACTITIONER}&_count=1000" \
  -H "Accept: application/fhir+json")

# Extract patient IDs from the bundle
#PATIENT_IDS=$(echo "$SEARCH_RESPONSE" | jq -r '.entry[]?.resource.id // empty')
mapfile -t PATIENT_IDS < <(echo "$SEARCH_RESPONSE" | jq -r '.entry[]?.resource.id // empty')

# Count patients found
#PATIENT_COUNT=$(echo "$PATIENT_IDS" | grep -c '^' 2>/dev/null || echo "0")
PATIENT_COUNT=${#PATIENT_IDS[@]}

if [ "$PATIENT_COUNT" -eq 0 ]; then
  echo -e "${YELLOW}No patients found with generalPractitioner: $OLD_PRACTITIONER${NC}"
  exit 0
fi

echo -e "${GREEN}Found $PATIENT_COUNT patient(s) to update${NC}"
echo ""

echo "Dry run, exiting. To do the PATCH's, comment out this line and the next one in the script."
exit 0

# Counter for success/failure
SUCCESS_COUNT=0
FAILURE_COUNT=0

# Iterate through each patient ID and apply the PATCH
#while IFS= read -r PATIENT_ID; do
for PATIENT_ID in "${PATIENT_IDS[@]}"; do
  if [ -z "$PATIENT_ID" ]; then
    continue
  fi
  
  echo "Updating Patient/$PATIENT_ID..."
  
  # Apply JSON Patch
  PATCH_OUTPUT=$(docker-compose exec -T ${DOCKER_CONTAINER} curl -s -w "\n%{http_code}" -X PATCH \
    "${FHIR_BASE_URL}/Patient/${PATIENT_ID}" \
    -H "Content-Type: application/json-patch+json" \
    -H "Accept: application/fhir+json" \
    -d "[
      {
        \"op\": \"test\",
        \"path\": \"/generalPractitioner/0/reference\",
        \"value\": \"${OLD_PRACTITIONER}\"
      },
      {
        \"op\": \"replace\",
        \"path\": \"/generalPractitioner/0\",
        \"value\": {
          \"display\": \"${NEW_DISPLAY}\",
          \"reference\": \"${NEW_PRACTITIONER}\",
          \"type\": \"Practitioner\"
        }
      }
    ]")
  
  # Extract HTTP code from last line
  HTTP_CODE=$(echo "$PATCH_OUTPUT" | tail -n 1)
  RESPONSE_BODY=$(echo "$PATCH_OUTPUT" | head -n -1)
  
  # Check HTTP response code
  if [ "$HTTP_CODE" -eq 200 ] || [ "$HTTP_CODE" -eq 201 ]; then
    echo -e "${GREEN}✓ Successfully updated Patient/$PATIENT_ID${NC}"
    ((SUCCESS_COUNT++))
  else
    echo -e "${RED}✗ Failed to update Patient/$PATIENT_ID (HTTP $HTTP_CODE)${NC}"
    echo "Response: $RESPONSE_BODY" | tee /tmp/patch_response_${PATIENT_ID}.json
    ((FAILURE_COUNT++))
  fi
  
  echo ""
#done <<< "$PATIENT_IDS"
done

# Summary
echo "================================================"
echo -e "${GREEN}Successfully updated: $SUCCESS_COUNT${NC}"
echo -e "${RED}Failed: $FAILURE_COUNT${NC}"
echo "================================================"
