# AWS Route 53 Hosted Zone Migrator

This script will help you to automate the migration of an AWS Route 53 hosted zone from an AWS account to another.

## Prerequisites
1. **Install or Upgrade AWS CLI:**<br/>
   follow the [AWS CLI User Guide](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html) to install or upgrade the AWS CLI.
2. **Install or Upgrade jq command**<br/>
   follow the [JQ Official Website](https://jqlang.github.io/jq/download/) to install or upgrade the 'jq' command.
3. **Configure profiles for AWS CLI:**<br/>
   make sure AWS CLI is configured for both the source and destination AWS accounts.
4. **Make sure you have the correct permissions in both accounts:**<br/>
   follow the [Identity and access management in Amazon Route 53](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/auth-and-access-control.html) to know more.
<br/>

## Usage example

When you run the script, you will be asked for:

- AWS CLI profile name of your source account, where the DNS zone is hosted;
- AWS CLI profile name of the destination account, where you want to migrate the source DNS zone;
- the Hosted Zone ID you want to migrate.

If the hosted zone you want to import is "private", you will be asked for additional information needed:

- the Region to associate with the private hosted zone
- the VPC ID to associate with the private hosted zone
<br/>

Dry run option:

```
% sh r53_migrator.sh --help

Usage: r53_migrator.sh [--dry-run]

%
```

Example of normal execution:

```
% sh r53_migrator.sh

********************************************************
          AWS Route 53 Hosted Zone Migrator             
********************************************************

- Enter AWS CLI profile name for the source AWS account: source_account
- Enter AWS CLI profile name for the destination AWS account: dest_account
- Enter the Route 53 Hosted Zone ID to migrate: ********************

[ Mon Dec  4 18:37:41 CET 2023 ] [INFO] Checking AWS CLI profiles...
[ Mon Dec  4 18:37:42 CET 2023 ] [OK] AWS CLI profile 'source_account' exists.
[ Mon Dec  4 18:37:43 CET 2023 ] [OK] AWS CLI profile 'destination_account' exists.
[ Mon Dec  4 18:37:43 CET 2023 ] [INFO] Checking Hosted Zone...
[ Mon Dec  4 18:37:45 CET 2023 ] [OK] Hosted Zone ID '********************' exists in the source account.
[ Mon Dec  4 18:37:45 CET 2023 ] [INFO] Checking if Hosted Zone is public or private...
[ Mon Dec  4 18:37:47 CET 2023 ] [INFO] Hosted Zone is public.
[ Mon Dec  4 18:37:50 CET 2023 ] [INFO] Checking if Hosted Zone name already exists in the destination account...
[ Mon Dec  4 18:37:52 CET 2023 ] [OK] Hosted Zone Name 'testzone.aws.com.' does not exist in the destination account.
[ Mon Dec  4 18:37:52 CET 2023 ] -- STARTING MIGRATION FROM source_account to destination_account
[ Mon Dec  4 18:37:52 CET 2023 ] [INFO] Hosted zone name: testzone.aws.com.
[ Mon Dec  4 18:37:52 CET 2023 ] [INFO] Found traffic policy records, moving them into migrations/********************/traffic_policy_records.json
[ Mon Dec  4 18:37:52 CET 2023 ] [OK] Traffic policy records file created.
[ Mon Dec  4 18:37:52 CET 2023 ] [INFO] Removing traffic policy records from the original JSON file
[ Mon Dec  4 18:37:52 CET 2023 ] [OK] Original JSON cleaned form traffic policy records.
[ Mon Dec  4 18:37:52 CET 2023 ] [INFO] Records to import: 8
[ Mon Dec  4 18:37:55 CET 2023 ] [OK] JSON file migrations/********************/part_1.json created.
[ Mon Dec  4 18:37:55 CET 2023 ] [INFO] Importing records from migrations/********************/part_1.json...
[ Mon Dec  4 18:37:57 CET 2023 ] [OK] Import completed
[ Mon Dec  4 18:37:59 CET 2023 ] [INFO] New Hosted Zone ID: ********************
[ Mon Dec  4 18:37:59 CET 2023 ] [INFO] Record count: 8
[ Mon Dec  4 18:37:59 CET 2023 ] [INFO] Hosted zone migration completed successfully.

** IMPORTANT ** 
Please make sure to setup the new nameservers of the imported zone in your domain configuration:

ns-****.awsdns-**.co.uk
ns-****.awsdns-**.org
ns-****.awsdns-**.com
ns-****.awsdns-**.net

%
```
<br/>

After the initial execution, a 'migrations' folder will be generated. Within this folder, you'll discover a nested directory named after the Hosted Zone ID you are currently working with. 
Inside, you'll locate both log files and the JSON file(s) generated and utilised by the tool.

<br/>

## How the script works (step by step)

1. It exports original hosted zone records on a JSON file from the source AWS account

2. Creates the new empty hosted zone on the destination account

3. Edits the exported JSON file with the required changes:
   - removes original SOA and NS records because they are already present in the new hosted zone created in the destination account;
   - moves all the ALIAS records at the end of the file;
   - replaces the old HostedZoneID in the ALIAS records which refer to other records in the same zone, with the new HostedZoneID;
   - removes any alias records that route traffic to a traffic policy instance. Writes the removed records into a JSON file so you can recreate them later.

4. Split the JSON file into multiple JSON files, as required by AWS Route 53 API, if:
   - DNS records are more than 1000;
   - the maximum combined length of the values in all Value elements is greater than 32,000 bytes.

5. Imports all the JSON files in the new hosted zone on the AWS destination account

6. If the zone is public, prints the nameservers of the new hosted zone:
   - to make the new hosted zone active, you have to set up the nameservers of the new hosted zone in the domain configuration.

<br/>

## Files created by the tool (inside 'migrations/HOSTED_ZONE_ID/' folder)

1. **migrations.log**: log file of the execution with the details of API answers
2. **original_full_export.json**: export of the original hosted zone
3. **part_*.json**: json file(s) used for the import. If the split is needed, you will find more than one
4. **traffic_policy_records.json** (optional):  - traffic policy instance records which are removed from the import and saved on this file to refer/recreate them later

<br/><br/>

For detailed instructions and examples, refer to the [official AWS Route 53 documentation](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/hosted-zones-migrating.html).