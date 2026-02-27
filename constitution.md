# AWS CLI Constitution (CRITICAL)

## MANDATORY CONFIRMATION RULE

**Before ANY AWS CLI command that creates, modifies, or deletes resources, you MUST get explicit user confirmation.**

## Commands Requiring Confirmation

### ALWAYS ASK BEFORE:

| Action Type | Example Commands |
|-------------|------------------|
| **Create** | `aws s3 mb`, `aws ec2 run-instances`, `aws lambda create-function`, `aws iam create-*` |
| **Modify** | `aws s3 cp`, `aws s3 sync`, `aws ec2 modify-*`, `aws lambda update-*`, `aws iam attach-*` |
| **Delete** | `aws s3 rb`, `aws s3 rm`, `aws ec2 terminate-instances`, `aws lambda delete-*`, `aws iam delete-*` |
| **Deploy** | `aws cloudformation deploy`, `aws cdk deploy`, `aws sam deploy` |
| **Config Change** | `aws configure`, `aws iam put-*-policy` |

### Safe Commands (No Confirmation Needed):

| Action Type | Example Commands |
|-------------|------------------|
| **Read/List** | `aws s3 ls`, `aws ec2 describe-*`, `aws lambda list-*`, `aws iam get-*` |
| **Describe** | `aws cloudformation describe-*`, `aws sts get-caller-identity` |
| **Dry-run** | Any command with `--dry-run` flag |

## Confirmation Protocol

1. **Confirm AWS accounts** to be used 
2. **Show the exact command** to be executed
3. **Explain what it will do** in plain language
4. **Highlight any risks** (cost, data loss, downtime)
5. **Use AskUserQuestion** tool for confirmation
6. **Only proceed after explicit "yes" or approval**

## Example Interaction

```
I need to create an S3 bucket. Here's the command:

aws s3 mb s3://my-new-bucket

This will:
- Confirm aws profile or context of eks using [AskUserQuestion: which profile do you want to execute on?]
- Create a new S3 bucket named "my-new-bucket"
```bash
  aws s3 mb s3://my-new-bucket --profile xxx
```
- if needed, confirm the region for the profile


## NEVER:

- Execute create/modify/delete commands without asking
- Assume user approval from previous similar commands except of destructive commands
- Batch multiple destructive operations without individual confirmation
- Use `--force` flags without explicit user consent

## Profile Awareness

Always confirm the active profile before destructive or first operations:
```bash
aws sts get-caller-identity --profile dev
```
This prevents accidental operations on wrong AWS accounts.

