#!/bin/bash

# This script is used to migrate a Route 53 Hosted Zone from one AWS account to another.
# It requires the AWS CLI and jq to be installed on the system.
# Please read the README.md file for more information.

. ./config
. ./functions.sh

if [ "$#" -gt 0 ]; then
    case "$1" in
        --dry-run)
            export DRYRUN="true"
            ;;
        --help)
            echo ""
            echo "Usage: $0 [--dry-run]"
            echo ""
            exit 1
            ;;
        *)
            echo ""
            echo "[ERROR] Unknown argument '$1'"
            echo ""
            echo "Usage: $0 [--dry-run]"
            echo ""
            exit 1
            ;;
    esac
fi

# Check pre-requisites
check_cmd "aws"
check_cmd "jq"

# Prompt the user for AWS CLI profile names and hosted zone ID
echo ""
echo "********************************************************"
echo "          AWS Route 53 Hosted Zone Migrator             "
echo "********************************************************"
echo ""
read -p "- Enter AWS CLI profile name for the source AWS account: " SOURCE_PROFILE
read -p "- Enter AWS CLI profile name for the destination AWS account: " DEST_PROFILE
read -p "- Enter the Route 53 Hosted Zone ID to migrate: " HOSTED_ZONE_ID
echo ""

# Checking log directory
if [ ! -e "$WORK_DIR/$HOSTED_ZONE_ID/$LOG_FILE" ]; then 
    mkdir -p "$WORK_DIR/$HOSTED_ZONE_ID"
    touch "$WORK_DIR/$HOSTED_ZONE_ID/$LOG_FILE"
fi

# Starting logging after the definition of the HOSTED_ZONE_ID
echo "" >> "$WORK_DIR/$HOSTED_ZONE_ID/$LOG_FILE"
echo "********************************************************" >> "$WORK_DIR/$HOSTED_ZONE_ID/$LOG_FILE"
echo "          AWS Route 53 Hosted Zone Migrator             " >> "$WORK_DIR/$HOSTED_ZONE_ID/$LOG_FILE"
echo "********************************************************" >> "$WORK_DIR/$HOSTED_ZONE_ID/$LOG_FILE"
echo "" >> "$WORK_DIR/$HOSTED_ZONE_ID/$LOG_FILE"

# Log dry-run execution
if [ "$DRYRUN" == "true" ]; then log "[INFO] Dry-run execution enabled"; fi

# Checking if specified AWS CLI profile are correct
log "[INFO] Checking AWS CLI profiles..."
aws_cli_profile_check "$SOURCE_PROFILE"
aws_cli_profile_check "$DEST_PROFILE"

# Checking if specified Hosted Zone is ok for both accounts
log "[INFO] Checking Hosted Zone..."
check_hosted_zone_id "$HOSTED_ZONE_ID"

# Checking if HOSTED ZONE is public or private
log "[INFO] Checking if Hosted Zone is public or private..."
check_private_hosted_zone "$HOSTED_ZONE_ID"

# Call the main function to perform the migration
extract_and_convert_zone "$SOURCE_PROFILE" "$DEST_PROFILE" "$HOSTED_ZONE_ID" "$HOSTED_ZONE_PRIVATE"

# Check DNSSEC configuration
check_dnssec "$SOURCE_PROFILE" "$HOSTED_ZONE_ID"