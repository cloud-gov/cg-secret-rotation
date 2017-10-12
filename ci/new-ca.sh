#!/bin/bash
set -eux

# install certstrap
export GOROOT=/goroot
mkdir /go
export GOPATH=/go
export PATH=$PATH:/goroot/bin
export PATH=$PATH:/go/bin
go get github.com/square/certstrap

# Generate CA certificate
addr=$(spruce json terraform-outputs/state.yml | jq -r '.terraform_outputs.master_bosh_static_ip')
bosh-config/generate-master-bosh-certs.sh "${addr}"

# Append CA certificate to secrets
spruce json secrets-in/secrets.yml \
  | jq --arg cert "$(cat out/master-bosh.crt)" '.secrets.ca_cert = (.secrets.ca_cert + "\n" + $cert)' \
  | spruce merge \
  > secrets-updated/secrets.yml

# Encrypt updated secrets
INPUT_FILE=secrets-updated/secrets.yml \
  OUTPUT_FILE=secrets-updated/secrets-encrypted.yml \
  PASSPHRASE="${PASSPHRASE}" \
  pipeline-tasks/encrypt.sh
