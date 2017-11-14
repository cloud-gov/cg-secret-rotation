#!/bin/bash
set -eu

# Get new CA certificate
ca_cert=$(spruce json secrets-in/secrets.yml \
  | jq -r '.ca_cert' \
  | sed -e '1,/-----END CERTIFICATE-----/d')

# Get new CA private key
ca_key=$(spruce json secrets-in/secrets.yml \
  | jq -r '.ca_key' \
  | sed -e '1,/-----END RSA PRIVATE KEY-----/d')

# Make a copy of existing secrets to update
cp secrets-in/secrets.yml secrets-updated/secrets.yml

# Replace CA certificate
spruce json secrets-updated/secrets.yml \
  | jq --arg cert "${ca_cert}" '.ca_cert = $cert' \
  | spruce merge \
  > secrets-updated/tmp.yml
mv secrets-updated/tmp.yml secrets-updated/secrets.yml

# Replace CA private key
spruce json secrets-updated/secrets.yml \
  | jq --arg key "${ca_key}" '.ca_key = $key' \
  | spruce merge \
  > secrets-updated/tmp.yml
mv secrets-updated/tmp.yml secrets-updated/secrets.yml

# Encrypt updated secrets
INPUT_FILE=secrets-updated/secrets.yml \
  OUTPUT_FILE=secrets-updated/secrets-encrypted.yml \
  PASSPHRASE="${PASSPHRASE}" \
  pipeline-tasks/encrypt.sh
