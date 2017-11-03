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

# Make a copy of existing secrets to update
cp secrets-in/secrets.yml secrets-updated/secrets.yml

# Append CA certificate to secrets
spruce json secrets-updated/secrets.yml \
  | jq --arg cert "$(cat out/master-bosh.crt)" '.ca_cert = (.ca_cert + "\n" + $cert)' \
  | spruce merge \
  > secrets-updated/tmp.yml
mv secrets-updated/tmp.yml secrets-updated/secrets.yml

# Rotate CA public key name in secrets
## this public key is stored in ec2 and must be rotated on all bosh deployments
##
spruce json secrets-updated/secrets.yml \
  | jq --arg key "masterbosh-$(date +'%Y%m%d')" '.ca_public_key_name = $key' \
  | spruce merge \
  > secrets-updated/tmp.yml
mv secrets-updated/tmp.yml secrets-updated/secrets.yml

# Append CA private key to secrets
spruce json secrets-updated/secrets.yml \
  | jq --arg key "$(cat out/master-bosh.key)" '.ca_key = (.ca_key + "\n" + $key)' \
  | spruce merge \
  > secrets-updated/tmp.yml
mv secrets-updated/tmp.yml secrets-updated/secrets.yml

# Encrypt updated secrets
INPUT_FILE=secrets-updated/secrets.yml \
  OUTPUT_FILE=secrets-updated/secrets-encrypted.yml \
  PASSPHRASE="${PASSPHRASE}" \
  pipeline-tasks/encrypt.sh
