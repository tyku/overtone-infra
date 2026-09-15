#!/bin/sh
set -eu

mc alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"
mc mb --ignore-existing "local/$S3_BUCKET"
mc anonymous set none "local/$S3_BUCKET"

printf '%s\n' \
  '{' \
  '  "Version": "2012-10-17",' \
  '  "Statement": [' \
  '    {' \
  '      "Effect": "Allow",' \
  '      "Action": ["s3:GetBucketLocation", "s3:ListBucket", "s3:ListBucketMultipartUploads"],' \
  "      \"Resource\": [\"arn:aws:s3:::$S3_BUCKET\"]" \
  '    },' \
  '    {' \
  '      "Effect": "Allow",' \
  '      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"],' \
  "      \"Resource\": [\"arn:aws:s3:::$S3_BUCKET/*\"]" \
  '    }' \
  '  ]' \
  '}' > /tmp/app-policy.json
mc admin user add local "$S3_ACCESS_KEY_ID" "$S3_SECRET_ACCESS_KEY" 2>/dev/null || \
  mc admin user enable local "$S3_ACCESS_KEY_ID"
mc admin policy create local overtone-app /tmp/app-policy.json
mc admin policy attach local overtone-app --user "$S3_ACCESS_KEY_ID"

mc alias set app http://minio:9000 "$S3_ACCESS_KEY_ID" "$S3_SECRET_ACCESS_KEY"
mc stat "app/$S3_BUCKET" >/dev/null
