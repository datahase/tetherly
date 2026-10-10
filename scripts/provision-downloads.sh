#!/usr/bin/env bash
set -euo pipefail
# Explicit operator inputs. The certificate must already be issued in us-east-1.
if [[ $# != 3 ]]; then printf '%s\n' 'Usage: provision-downloads.sh AWS_PROFILE EXPECTED_ACCOUNT CERTIFICATE_ARN' >&2; exit 2; fi
profile=$1
account=$2
certificate=$3
[[ "$account" =~ ^[0-9]{12}$ && "$certificate" == "arn:aws:acm:us-east-1:$account:certificate/"* ]] || exit 2
actual=$(aws --profile "$profile" sts get-caller-identity --query Account --output text)
[[ "$actual" == "$account" ]] || { printf '%s\n' 'AWS account mismatch.' >&2; exit 1; }
status=$(aws --profile "$profile" --region us-east-1 acm describe-certificate --certificate-arn "$certificate" --query Certificate.Status --output text)
[[ "$status" == ISSUED ]] || { printf '%s\n' 'Certificate is not issued. Add its validation DNS record and retry later.' >&2; exit 1; }
root=$(cd "$(dirname "$0")/.." && pwd)
aws --profile "$profile" --region ap-south-1 cloudformation deploy --template-file "$root/release/infra/downloads.cloudformation.json" --stack-name tetherly-release --parameter-overrides BucketName=tetherly-release AssetsDomain=assets.tetherly.link "CertificateArn=$certificate" --no-fail-on-empty-changeset
aws --profile "$profile" --region ap-south-1 cloudformation describe-stacks --stack-name tetherly-release --query 'Stacks[0].Outputs' --output json
