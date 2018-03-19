#!/bin/bash
set -eu

# Get new CA certificate
ca_cert=$(spruce json secrets-in/secrets.yml \
  | jq -r '.secrets.ca_cert')

# Make a copy of existing secrets to update
cp secrets-in/secrets.yml secrets-updated/secrets.yml

# Remove old CA from CA cert store
spruce json secrets-updated/secrets.yml \
  | jq --arg cert "${ca_cert}" '.secrets.ca_cert_store = $cert' \
  | spruce merge \
  > secrets-updated/tmp.yml
mv secrets-updated/tmp.yml secrets-updated/secrets.yml

# Encrypt updated secrets
INPUT_FILE=secrets-updated/secrets.yml \
  OUTPUT_FILE=secrets-updated/secrets-encrypted.yml \
  PASSPHRASE="${PASSPHRASE}" \
  pipeline-tasks/encrypt.sh
