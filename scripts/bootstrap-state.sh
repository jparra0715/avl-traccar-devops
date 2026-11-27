#!/usr/bin/env bash
set -euo pipefail

export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

ENDPOINT="http://localhost:4566"
BUCKET="avl-traccar-tfstate"

echo "Creando bucket de estado remoto: $BUCKET..."
aws --endpoint-url="$ENDPOINT" s3 mb "s3://$BUCKET" 2>/dev/null || echo "El bucket ya existe."
aws --endpoint-url="$ENDPOINT" s3 ls
