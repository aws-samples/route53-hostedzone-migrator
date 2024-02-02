#!/bin/bash

# Function to check if a command is installed
check_cmd() {
    if ! command -v "$1" &> /dev/null; then
        echo "[ $(date) ] [OK] $1 command is not installed. Please install $1 to proceed."
        exit 1
    fi
}

# Function to log messages
log() {
    local message
    message="[ $(date) ] $1"
    echo "$message" | tee -a "$WORK_DIR/$HOSTED_ZONE_ID/$LOG_FILE"
}

# Function to check if AWS CLI profiles exist
aws_cli_profile_check() {
    if ! aws configure list --profile "$1" &> /dev/null; then
        log "[ERROR] AWS CLI profile '$1' is incorrect or does not exist."
        log "[ERROR] Please specify a correct AWS CLI profile name."
        exit 1
    else
        log "[OK] AWS CLI profile '$1' exists."
    fi
}

# Function to check if Hosted Zone ID exists
check_hosted_zone_id() {
    if ! aws route53 get-hosted-zone --id "$1" --profile "$SOURCE_PROFILE" &> /dev/null; then
        log "[ERROR] Hosted Zone ID '$1' does not exist or an error occurred."
        log "[ERROR] Please specify a correct Hosted Zone ID or verify the IAM permissions."
        exit 1
    else
        log "[OK] Hosted Zone ID '$1' exists in the source account."
    fi
}

# Checking if HOSTED ZONE is public or private
check_private_hosted_zone() {
    HOSTED_ZONE_PRIVATE=$(aws --profile "$SOURCE_PROFILE" route53 get-hosted-zone --id "$1" --query 'HostedZone.Config.PrivateZone' --output text)
    if [ "$HOSTED_ZONE_PRIVATE" == "True" ]; then
        log "[INFO] Hosted Zone is private." 
        if [ "$DRYRUN" != "true" ]; then
            log "Please provide additional information:"
            read -p "- Enter the Region to associate the private hosted zone: " HOSTED_ZONE_REGION
            read -p "- Enter the VPC ID to associate the private hosted zone: " HOSTED_ZONE_VPC_ID
        fi
    else
        log "[INFO] Hosted Zone is public."
    fi
}

# Check if the hosted zone already exists in the destination account
check_hosted_zone_name() {
    if [ -z "$(aws --profile "$DEST_PROFILE" route53 list-hosted-zones --query "HostedZones[?Name=='$1'].Id" --output text)" ]; then
        log "[OK] Hosted Zone Name '$1' does not exist in the destination account."
    else
        log "[ERROR] Hosted Zone Name '$1' already exists in the destination account."
        exit 1
    fi
}

# Function to extract and convert Route 53 hosted zone
extract_and_convert_zone() {
    local SOURCE_PROFILE=$1
    local DEST_PROFILE=$2
    local HOSTED_ZONE_ID=$3
    local HOSTED_ZONE_PRIVATE=$4

    # Checking working directory
    mkdir -p "$WORK_DIR/$HOSTED_ZONE_ID"

    # Extract hosted zone records and info from the source AWS account
    SOURCE_RECORDS=$(aws --profile "$SOURCE_PROFILE" route53 list-resource-record-sets --hosted-zone-id "$HOSTED_ZONE_ID" --output json)
    echo "$SOURCE_RECORDS" > "$WORK_DIR/$HOSTED_ZONE_ID/original_full_export.json"
    HOSTED_ZONE_NAME=$(aws --profile "$SOURCE_PROFILE" route53 get-hosted-zone --id "$HOSTED_ZONE_ID" --query 'HostedZone.Name' --output text)

    # Check if extraction was successful
    if [ $? -ne 0 ]; then
        log "[ERROR] Failed to extract records from the source hosted zone."
        exit 1
    fi

    # Check if the hosted zone name already exists in the destination account
    log "[INFO] Checking if Hosted Zone name already exists in the destination account..."
    check_hosted_zone_name "$HOSTED_ZONE_NAME"

    if [ "$DRYRUN" != "true" ]; then
        log "-- STARTING MIGRATION FROM $SOURCE_PROFILE to $DEST_PROFILE"
        log "[INFO] Hosted zone name: $HOSTED_ZONE_NAME"
    fi

    # Convert JSON using jq command
    CONVERTED_JSON=$(echo "$SOURCE_RECORDS" | jq --arg name "$HOSTED_ZONE_NAME" '.ResourceRecordSets |{"Changes":[.[]|select(.Type!="SOA")|select((.Type!="NS") or (.Name != $name))|{"Action":"CREATE","ResourceRecordSet":.}]}')

    # Order JSON to have ALIAS records at the end
    CONVERTED_JSON=$(echo "$CONVERTED_JSON" | jq '.Changes |= sort_by(.ResourceRecordSet.AliasTarget != null)')

    # If present, remove records with key "TrafficPolicyInstanceId" and create a new JSON file with only those, cleaning the original JSON
    if echo "$CONVERTED_JSON" | jq -e '.Changes[].ResourceRecordSet.TrafficPolicyInstanceId | select(. != null)' > /dev/null 2>&1; then
        log "[INFO] Found traffic policy records, moving them into $WORK_DIR/$HOSTED_ZONE_ID/traffic_policy_records.json"
        echo "$CONVERTED_JSON" | jq '{ Changes: [.Changes[] | select(.ResourceRecordSet.TrafficPolicyInstanceId)] }' > "$WORK_DIR/$HOSTED_ZONE_ID/traffic_policy_records.json"
        if [ $? -ne 0 ]; then echo "[ERROR] Failed to create traffic policy records file."; exit 1; else log "[OK] Traffic policy records file created."; fi
        log "[INFO] Removing traffic policy records from the original JSON file"
        CONVERTED_JSON=$(echo "$CONVERTED_JSON" | jq '.Changes |= map(select(.ResourceRecordSet.TrafficPolicyInstanceId | not))')
        if [ $? -ne 0 ]; then echo "[ERROR] Failed to clean original JSON from traffic policy records."; exit 1; else log "[OK] Original JSON cleaned form traffic policy records."; fi
    fi

    # Log the number of records before migration
    NUM_RECORDS_BEFORE=$(echo "$CONVERTED_JSON" | jq '.Changes | length')
    log "[INFO] Records included: $NUM_RECORDS_BEFORE"

    if [ "$DRYRUN" != "true" ]; then

        # Create the new hosted zone in the destination AWS account
        if [ "$HOSTED_ZONE_PRIVATE" == "False" ]; then
            DEST_HOSTED_ZONE_ID=$(aws --profile "$DEST_PROFILE" route53 create-hosted-zone --name "$HOSTED_ZONE_NAME" --caller-reference "$(date +%s)" --hosted-zone-config Comment="Migrated from $HOSTED_ZONE_ID" --query 'HostedZone.Id' --output text)
            # Check if the new hosted zone was created successfully
            if [ $? -ne 0 ]; then
                log "[ERROR] Failed to create the destination hosted zone."
                # Clean up - delete the destination hosted zone
                aws --profile "$DEST_PROFILE" route53 delete-hosted-zone --id "$DEST_HOSTED_ZONE_ID" > /dev/null 2>&1
                exit 1
            fi
        else
            DEST_HOSTED_ZONE_ID=$(aws --profile "$DEST_PROFILE" route53 create-hosted-zone --name "$HOSTED_ZONE_NAME" --caller-reference "$(date +%s)" --vpc "VPCRegion=$HOSTED_ZONE_REGION,VPCId=$HOSTED_ZONE_VPC_ID" --hosted-zone-config Comment="Migrated from $HOSTED_ZONE_ID" --query 'HostedZone.Id' --output text)
            if [ $? -ne 0 ]; then
                log "[ERROR] Failed to create the destination hosted zone."
                # Clean up - delete the destination hosted zone
                aws --profile "$DEST_PROFILE" route53 delete-hosted-zone --id "$DEST_HOSTED_ZONE_ID" > /dev/null 2>&1
                exit 1
            fi
        fi
    
    fi

    # Replace old HostedZoneId in AliasTarget records with the new one
    NEW_HOSTED_ZONE_ID=$(aws --profile "$DEST_PROFILE" route53 list-hosted-zones-by-name --dns-name "$HOSTED_ZONE_NAME" --query "HostedZones[].Id" --output text | cut -d / -f3 | xargs)
    CONVERTED_JSON=$(echo "$CONVERTED_JSON" | jq --arg newHostedZoneId "$NEW_HOSTED_ZONE_ID" --arg oldHostedZoneId "$HOSTED_ZONE_ID" '
        .Changes |= map(
        if .ResourceRecordSet.AliasTarget != null and .ResourceRecordSet.AliasTarget.HostedZoneId == $oldHostedZoneId then
            .ResourceRecordSet.AliasTarget.HostedZoneId = $newHostedZoneId
        else
            .
        end
            )'
    )

    # Save all the records in importable format, to file
    # echo "$CONVERTED_JSON" > "$WORK_DIR"/"$HOSTED_ZONE_ID"/importable_records.json

    # Call function to split the JSON file into smaller chunks, if needed
    json_chunker "$CONVERTED_JSON"

    if [ "$DRYRUN" == "true" ]; then
        log "[INFO] DRY RUN execution, skipping import."
    else
        # Import all JSON files into the destination hosted zone
        for json_file in "$WORK_DIR"/"$HOSTED_ZONE_ID"/part_*.json; do

            log "[INFO] Importing records from $json_file..."
            
            # Import all records in the file
            aws --profile "$DEST_PROFILE" route53 change-resource-record-sets --hosted-zone-id "$DEST_HOSTED_ZONE_ID" --change-batch "$(cat "$json_file")" >> "$WORK_DIR/$HOSTED_ZONE_ID/$LOG_FILE" 2>&1

            # Check if the update was successful
            if [ $? -eq 0 ]; then
                # Import successful
                log "[OK] Import completed"
                #rm "$json_file"
            else
                # Import failed
                log "[ERROR] Failed to import records in the destination hosted zone."
                log "[ERROR] Please check the log file $WORK_DIR/$HOSTED_ZONE_ID/$LOG_FILE for more details."
                # Clean up - delete the destination hosted zone
                aws --profile "$DEST_PROFILE" route53 delete-hosted-zone --id "$DEST_HOSTED_ZONE_ID" > /dev/null 2>&1
                #rm "$json_file"
                exit 1
            fi
        done
    
        # Log the number of records after migration
        NUM_RECORDS_AFTER=$(aws --profile "$DEST_PROFILE" route53 list-resource-record-sets --hosted-zone-id "$DEST_HOSTED_ZONE_ID" --output json | jq --arg name "$HOSTED_ZONE_NAME" '.ResourceRecordSets | map(select(.Type!="SOA")|select((.Type!="NS") or (.Name != $name))) | length')
        log "[INFO] New Hosted Zone ID: $NEW_HOSTED_ZONE_ID"
        log "[INFO] Record count: $NUM_RECORDS_AFTER"
        log "[INFO] Hosted zone migration completed successfully."
        echo ""

        if [ "$HOSTED_ZONE_PRIVATE" == "False" ]; then
            # Log the new nameservers in the destination hosted zone
            NEW_NAMESERVERS=$(aws --profile "$DEST_PROFILE" route53 get-hosted-zone --id "$DEST_HOSTED_ZONE_ID" --query 'DelegationSet.NameServers' --output json)
            echo "** IMPORTANT **"
            echo "Please make sure to setup the new nameservers of the imported zone in your domain configuration:"
            echo ""
            echo "$NEW_NAMESERVERS" | jq -r '.[]'
            echo ""
        fi
    fi
}

json_chunker() {
    array_to_chunk="$1"
    i=0
    j=1
    start_index=0
    combined_value_elements_size=0

    # Count the number of records in the array
    num_records=$(echo "$array_to_chunk" | jq '.Changes | length')

    while((i < num_records)); do

        value_element_size=$(echo "$array_to_chunk" | jq --argjson index "$i" -r '.Changes[$index].ResourceRecordSet.ResourceRecords[]? | .Value | @json ' | sed 's/^"\(.*\)"$/\1/' | tr -d '\n' | wc -c | xargs)
  
        if [[ $i == $((num_records - 1)) || $i == $((start_index + MAX_RECORDS - 1)) || $((value_element_size + combined_value_elements_size)) -gt $MAX_VALUE_SIZE ]]; then
            
            if [[ $i == $((start_index + MAX_RECORDS - 1)) ]]; then logmsg="[INFO] Limit of $MAX_RECORDS records reached"; fi
            if [[ $((value_element_size + combined_value_elements_size)) -gt $MAX_VALUE_SIZE ]]; then logmsg="[INFO] Limit of $MAX_VALUE_SIZE bytes in combined size of Value elements reached"; fi

            end_index=$((i + 1));
            local subset_records
            subset_records=$(echo "$array_to_chunk" | jq ".Changes[$start_index:$end_index]")
            value_element_size=0
            combined_value_elements_size=0
            echo "{ \"Changes\": $subset_records }" > "$WORK_DIR/$HOSTED_ZONE_ID/part_$j.json"

            if [ $? -ne 0 ] ; then
                log "[ERROR] Error writing to file" 
                exit 1 
            else
                if [ -n "$logmsg" ]; then 
                    log "$logmsg, splitting JSON: $WORK_DIR/$HOSTED_ZONE_ID/part_$j.json created."
                else
                    log "[OK] JSON file $WORK_DIR/$HOSTED_ZONE_ID/part_$j.json created." 
                fi
                start_index=$end_index
                ((j++))

            fi
        fi

        combined_value_elements_size=$((value_element_size + combined_value_elements_size))
        ((i++))

    done
}