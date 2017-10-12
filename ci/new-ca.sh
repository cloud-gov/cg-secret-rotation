#!/bin/bash

# Generate CA certificate
addr=$(spruce json terraform-outputs/tooling | jq -r '.master_bosh_static_ip')
bosh-config/generate-master-bosh-certs.sh "${addr}"

# Append CA certificate to secrets
spruce json common/secrets.yml \
  | jq --arg cert "$(cat out/master-bosh.crt)" '.secrets.ca_cert = (.secrets.ca_cert + "\n" + $cert)' \
  | spruce merge \
  > secrets-updated/secrets.yml

# Encrypt updated secrets
INPUT_FILE=secrets-updated/secrets.yml \
  OUTPUT_FILE=secrets-updated/secrets.yml \
  PASSPHRASE="${PASSPHRASE}" \
  pipeline-tasks/encrypt.sh
