#!/bin/bash
# Generate a shell script of curl PATCH commands

DOCKER_CONTAINER="femr"
FHIR_BASE_URL="http://fhir-internal:8080/fhir"

#prod
#OLD_PRACTITIONER="Practitioner/6"
#NEW_PRACTITIONER="Practitioner/7"
#NEW_DISPLAY="Wright, Riley"

#eval - the generated script ran properly on eval
#OLD_PRACTITIONER="Practitioner/699"
#NEW_PRACTITIONER="Practitioner/700"
#NEW_DISPLAY="Wright, Barbara"

OUTPUT_FILE="/home/mcjustin/isacc-environments/utils/update_careteams_commands_cove.sh"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "Searching for CareTeams with participant member: $OLD_PRACTITIONER"

# Search for CareTeams with the specific practitioner as a participant
SEARCH_RESPONSE=$(docker-compose exec -T ${DOCKER_CONTAINER} curl -s -X GET \
  "${FHIR_BASE_URL}/CareTeam?participant=${OLD_PRACTITIONER}&_count=1000" \
  -H "Accept: application/fhir+json")

# Extract CareTeam IDs from the bundle into an array
mapfile -t CARETEAM_IDS < <(echo "$SEARCH_RESPONSE" | jq -r '.entry[]?.resource.id // empty')

# Count CareTeams found
CARETEAM_COUNT=${#CARETEAM_IDS[@]}

if [ "$CARETEAM_COUNT" -eq 0 ]; then
  echo -e "${YELLOW}No CareTeams found with participant member: $OLD_PRACTITIONER${NC}"
  exit 0
fi

echo -e "${GREEN}Found $CARETEAM_COUNT CareTeam(s) to update${NC}"
echo ""

# Initialize the output file
cat > "$OUTPUT_FILE" << 'EOF'
#!/bin/bash

# Generated CareTeam update commands
# Review and execute these commands one by one, or run the entire file

DOCKER_CONTAINER="femr"

EOF

# Counter for commands generated
COMMAND_COUNT=0
SKIP_COUNT=0

# Iterate through each CareTeam ID
for CARETEAM_ID in "${CARETEAM_IDS[@]}"; do
  if [ -z "$CARETEAM_ID" ]; then
    continue
  fi
  
  echo "Analyzing CareTeam/$CARETEAM_ID..."
  
  # Fetch the full CareTeam resource
  CARETEAM_RESOURCE=$(docker-compose exec -T ${DOCKER_CONTAINER} curl -s -X GET \
    "${FHIR_BASE_URL}/CareTeam/${CARETEAM_ID}" \
    -H "Accept: application/fhir+json")
  
  # Find all indices where Practitioner/6 appears in participant array
  OLD_INDICES=$(echo "$CARETEAM_RESOURCE" | jq -r '[.participant // [] | to_entries[] | select(.value.member.reference == "'"${OLD_PRACTITIONER}"'") | .key] | @csv' | tr -d '"')
  
  # Check if Practitioner/7 already exists
  HAS_NEW=$(echo "$CARETEAM_RESOURCE" | jq -r '.participant // [] | map(.member.reference) | contains(["'"${NEW_PRACTITIONER}"'"])')
  
  if [ -z "$OLD_INDICES" ]; then
    echo -e "${YELLOW}⊘ Skipping - no matching participant found${NC}"
    ((SKIP_COUNT++))
    echo ""
    continue
  fi
  
  # Convert comma-separated indices to array
  IFS=',' read -ra INDEX_ARRAY <<< "$OLD_INDICES"
  
  # Build JSON Patch operations
  PATCH_OPS="["
  
  if [ "$HAS_NEW" == "true" ]; then
    echo -e "${BLUE}→ Practitioner/7 already exists, will remove Practitioner/6${NC}"
    COMMENT="Practitioner/7 already exists, removing Practitioner/6"
    # Remove all instances of Practitioner/6 (in reverse order to maintain indices)
    for ((i=${#INDEX_ARRAY[@]}-1; i>=0; i--)); do
      INDEX=${INDEX_ARRAY[$i]}
      if [ "$i" -lt $((${#INDEX_ARRAY[@]}-1)) ]; then
        PATCH_OPS="${PATCH_OPS},"
      fi
      PATCH_OPS="${PATCH_OPS}
      {
        \"op\": \"remove\",
        \"path\": \"/participant/${INDEX}\"
      }"
    done
  else
    echo -e "${BLUE}→ Will replace Practitioner/6 with Practitioner/7${NC}"
    COMMENT="Replacing Practitioner/6 with Practitioner/7"
    # Replace the first instance and remove any additional instances
    FIRST_INDEX=${INDEX_ARRAY[0]}
    PATCH_OPS="${PATCH_OPS}
      {
        \"op\": \"replace\",
        \"path\": \"/participant/${FIRST_INDEX}/member\",
        \"value\": {
          \"reference\": \"${NEW_PRACTITIONER}\",
          \"display\": \"${NEW_DISPLAY}\"
        }
      }"
    
    # Remove any additional instances (in reverse order)
    if [ ${#INDEX_ARRAY[@]} -gt 1 ]; then
      for ((i=${#INDEX_ARRAY[@]}-1; i>=1; i--)); do
        INDEX=${INDEX_ARRAY[$i]}
        PATCH_OPS="${PATCH_OPS},
      {
        \"op\": \"remove\",
        \"path\": \"/participant/${INDEX}\"
      }"
      done
    fi
  fi
  
  PATCH_OPS="${PATCH_OPS}
    ]"
  
  # Escape single quotes in the JSON for the bash script
  PATCH_OPS_ESCAPED=$(echo "$PATCH_OPS" | sed "s/'/'\\\\''/g")
  
  # Add command to output file
  cat >> "$OUTPUT_FILE" << EOF

# CareTeam/$CARETEAM_ID - $COMMENT
echo "Updating CareTeam/$CARETEAM_ID..."
docker-compose exec -T \${DOCKER_CONTAINER} curl -X PATCH \\
  "${FHIR_BASE_URL}/CareTeam/${CARETEAM_ID}" \\
  -H "Content-Type: application/json-patch+json" \\
  -H "Accept: application/fhir+json" \\
  -d '$PATCH_OPS_ESCAPED'
echo ""
echo ""

EOF

  ((COMMAND_COUNT++))
  echo ""
done

# Make the output file executable
chmod +x "$OUTPUT_FILE"

# Summary
echo "================================================"
echo -e "${GREEN}Generated $COMMAND_COUNT command(s)${NC}"
echo -e "${YELLOW}Skipped: $SKIP_COUNT${NC}"
echo -e "${BLUE}Commands saved to: $OUTPUT_FILE${NC}"
echo "================================================"
echo ""
echo "To review and run commands one by one, open the file in an editor."
echo "To run all commands: ./$OUTPUT_FILE"
