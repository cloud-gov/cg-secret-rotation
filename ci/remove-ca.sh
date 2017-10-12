#!/bin/bash
set -eux

# Get new CA certificate
ca_cert=$(spruce json secrets-in/secrets.yml \
  | jq -r '.secrets.ca_cert' \
  | sed -e '1,/-----END CERTIFICATE-----/d')

# Replace CA certificate
spruce json secrets-in/secrets.yml \
  | jq --arg cert "${ca_cert}" '.secrets.ca_cert = $cert)' \
  | spruce merge \
  > secrets-updated/secrets.yml

# Encrypt updated secrets
INPUT_FILE=secrets-updated/secrets.yml \
  OUTPUT_FILE=secrets-updated/secrets-encrypted.yml \
  PASSPHRASE="${PASSPHRASE}" \
  pipeline-tasks/encrypt.sh
