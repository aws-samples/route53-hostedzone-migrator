# Amazon Route 53 Hosted Zone Migrator

This solution automates the migration of an AWS Route 53 hosted zone between AWS accounts, following all necessary steps outlined in the official AWS Route 53 migration [documentation](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/hosted-zones-migrating.html).

## Prerequisites
1. **Install or Upgrade AWS CLI:**<br/>
   follow the [AWS CLI User Guide](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html) to install or upgrade the AWS CLI.
2. **Install or Upgrade jq command**<br/>
   follow the [JQ Official Website](https://jqlang.github.io/jq/download/) to install or upgrade the 'jq' command.
3. **Configure profiles for AWS CLI:**<br/>
   make sure AWS CLI is configured for both the source and destination AWS accounts.
4. **Make sure you have the correct permissions in both accounts:**<br/>
   follow the [Identity and access management in Amazon Route 53](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/auth-and-access-control.html) to know more.<br>
   You can use the AmazonRoute53ReadOnlyAccess managed policy on the source account and the AmazonRoute53FullAccess managed policy in the destination account.<br>
   If you are working on private hosted zones, you will also need to ensure the appropriate VPC-related permissions (such as AmazonVPCFullAccess) are available in the destination account to associate the private zone with a VPC.

<br/>

## How the tool works (step by step)

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
        Amazon Route 53 Hosted Zone Migrator             
********************************************************

- Enter AWS CLI profile name for the source AWS account: source_accountA
- Enter AWS CLI profile name for the destination AWS account: dest_accountB
- Enter the Route 53 Hosted Zone ID to migrate: Z02526892************

[ Tue Oct 22 14:58:20 CEST 2024 ] [INFO] Checking AWS CLI profiles...
[ Tue Oct 22 14:58:26 CEST 2024 ] [OK] AWS CLI profile 'source_accountA' exists.
[ Tue Oct 22 14:58:29 CEST 2024 ] [OK] AWS CLI profile 'dest_accountB' exists.
[ Tue Oct 22 14:58:29 CEST 2024 ] [INFO] Checking Hosted Zone...
[ Tue Oct 22 14:58:31 CEST 2024 ] [OK] Hosted Zone ID 'Z02526892************' exists in the source account.
[ Tue Oct 22 14:58:31 CEST 2024 ] [INFO] Checking if Hosted Zone is public or private...
[ Tue Oct 22 14:58:32 CEST 2024 ] [INFO] Hosted Zone is public.
[ Tue Oct 22 14:58:35 CEST 2024 ] [INFO] Checking if Hosted Zone name already exists in the destination account...
[ Tue Oct 22 14:58:37 CEST 2024 ] [OK] Hosted Zone Name 'test.aws.com.' does not exist in the destination account.
[ Tue Oct 22 14:58:37 CEST 2024 ] -- STARTING MIGRATION FROM source_accountA to dest_accountB
[ Tue Oct 22 14:58:37 CEST 2024 ] [INFO] Hosted zone name: test.aws.com.
[ Tue Oct 22 14:58:37 CEST 2024 ] [INFO] Records included: 1016
[ Tue Oct 22 14:58:38 CEST 2024 ] [INFO] Limit of 999 records reached, splitting JSON: migrations/Z02526892************/part_1.json created.
[ Tue Oct 22 14:58:38 CEST 2024 ] [INFO] Limit of 999 records reached, splitting JSON: migrations/Z02526892************/part_2.json created.
[ Tue Oct 22 14:58:39 CEST 2024 ] [INFO] Importing records from migrations/Z02526892************/part_1.json...
[ Tue Oct 22 14:58:41 CEST 2024 ] [OK] Import completed
[ Tue Oct 22 14:58:41 CEST 2024 ] [INFO] Importing records from migrations/Z02526892************/part_2.json...
[ Tue Oct 22 14:58:43 CEST 2024 ] [OK] Import completed
[ Tue Oct 22 14:58:43 CEST 2024 ] [INFO] New Hosted Zone ID: Z04550442************
[ Tue Oct 22 14:58:43 CEST 2024 ] [INFO] Record count: 1016
[ Tue Oct 22 14:58:43 CEST 2024 ] [INFO] Hosted zone migration completed successfully.

** IMPORTANT **
Please make sure to setup the new nameservers of the imported zone in your domain configuration:

ns-600.awsdns-11.net
ns-1503.awsdns-59.org
ns-2022.awsdns-60.co.uk
ns-472.awsdns-59.com

%
```
<br/>

After the first execution, a 'migrations' folder will be generated. Within this folder, you'll discover a nested directory named after the Hosted Zone ID you are currently working with. 
Inside, you'll locate both log files and the JSON file(s) generated and utilised by the solution.

<br/>


## Files created by the tool (inside 'migrations/HOSTED_ZONE_ID/' folder)

1. **migrations.log**: log file of the execution with the details of API answers
2. **original_full_export.json**: export of the original hosted zone
3. **part_*.json**: json file(s) used for the import. If the split is needed, you will find more than one
4. **traffic_policy_records.json** (optional):  - traffic policy instance records which are removed from the import and saved on this file to refer/recreate them later

<br/><br/>

## Useful links

For detailed instructions and examples, refer to the [official AWS Route 53 documentation](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/hosted-zones-migrating.html).
