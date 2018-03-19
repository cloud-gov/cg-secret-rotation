#!/bin/bash
set -eu

# install certstrap
export GOROOT=/goroot
mkdir /go
export GOPATH=/go
export PATH=$PATH:/goroot/bin
export PATH=$PATH:/go/bin
go get github.com/square/certstrap

# Generate CA certificate and keys
addr=$(spruce json terraform-outputs/state.yml | jq -r '.terraform_outputs.master_bosh_static_ip')
bosh-config/generate-master-bosh-certs.sh "${addr}"
key_name=$(cat ./key-name)

# Make a copy of existing secrets to update
cp secrets-in/secrets.yml secrets-updated/secrets.yml

# Update CA certificate in secrets
spruce json secrets-updated/secrets.yml \
  | jq --arg cert "$(cat out/master-bosh.crt)" '.secrets.ca_cert = $cert' \
  | spruce merge \
  > secrets-updated/tmp.yml
mv secrets-updated/tmp.yml secrets-updated/secrets.yml

# Append CA certificate to cert store
spruce json secrets-updated/secrets.yml \
  | jq --arg cert "$(cat out/master-bosh.crt)" '.secrets.ca_cert_store = (.secrets.ca_cert_store + "\n" + $cert)' \
  | spruce merge \
  > secrets-updated/tmp.yml
mv secrets-updated/tmp.yml secrets-updated/secrets.yml

# Rotate CA public key name in secrets
## this public key is stored in ec2 and must be rotated on all bosh deployments
##
spruce json secrets-updated/secrets.yml \
  | jq --arg key "${key_name}" '.secrets.ca_public_key_name = $key' \
  | spruce merge \
  > secrets-updated/tmp.yml
mv secrets-updated/tmp.yml secrets-updated/secrets.yml

# Update CA private key in secrets
spruce json secrets-updated/secrets.yml \
  | jq --arg key "$(cat out/master-bosh.key)" '.secrets.ca_key = $key' \
  | spruce merge \
  > secrets-updated/tmp.yml
mv secrets-updated/tmp.yml secrets-updated/secrets.yml

# generate new secrets passphrase each time we update secrets
## all pipelines consuming these secrets (including this one) will need to be updated before running again.
## use PASSPHRASE from env/pipeline configs for now.
#PASSPHRASE=$(cat /dev/urandom | LC_ALL=C tr -dc "a-zA-Z0-9" | head -c 32)

# store environment secrets passphrase in the secrets
spruce json secrets-updated/secrets.yml \
  | jq --arg password "${PASSPHRASE}" ".secrets.secrets_secrets_passphrase = \$password" \
  | spruce merge \
  > secrets-updated/tmp.yml
mv secrets-updated/tmp.yml secrets-updated/secrets.yml

# Encrypt updated secrets
INPUT_FILE=secrets-updated/secrets.yml \
  OUTPUT_FILE=secrets-updated/secrets-encrypted.yml \
  PASSPHRASE="${PASSPHRASE}" \
  pipeline-tasks/encrypt.sh
