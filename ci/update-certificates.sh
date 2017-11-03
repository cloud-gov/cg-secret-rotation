#!/bin/bash
set -eux

# install certstrap
export GOROOT=/goroot
mkdir /go
export GOPATH=/go
export PATH=$PATH:/goroot/bin
export PATH=$PATH:/go/bin
go get github.com/square/certstrap

# Get CA certificate from common
ca_cert=$(spruce json secrets-in-common/secrets.yml \
  | jq -r '.ca_cert' \
  | sed -e '1,/-----END CERTIFICATE-----/d')

# Get CA private key from common
ca_key=$(spruce json secrets-in-common/secrets.yml \
  | jq -r '.ca_key' \
  | sed -e '1,/-----END RSA PRIVATE KEY-----/d')

# set up to sign certs
mkdir out
echo "${ca_cert}" > out/master-bosh.crt
echo "${ca_key}" > out/master-bosh.key

# make a copy of the secrets file
cp secrets-in/secrets.yml secrets-updated/secrets.yml

# Generate bosh certs
bosh_name=$(spruce json "terraform-outputs/state.yml" | jq -r '.terraform_outputs.bosh_profile')
bosh_addr=$(spruce json "terraform-outputs/state.yml" | jq -r '.terraform_outputs.bosh_static_ip')
bosh-config/generate-bosh-certs.sh "${bosh_name}" "${bosh_addr}"

# map artifacts to yaml keys
mapping=$(cat << EOF
[
  {"key": "bosh_director_key", "path":"out/${bosh_name}-bosh-director.key"},
  {"key": "bosh_director_cert", "path":"out/${bosh_name}-bosh-director.crt"},
  {"key": "bosh_uaa_web_public_key", "path":"out/${bosh_name}-pub.key"},
  {"key": "bosh_uaa_web_key", "path":"out/${bosh_name}-uaa-web.key"},
  {"key": "bosh_uaa_web_cert", "path":"out/${bosh_name}-uaa-web.crt"}
]
EOF
)

# put artifacts in yml
for row in $(echo $mapping | jq -c '.[]'); do

  key=$(echo $row | jq -r '.key')
  path=$(echo $row | jq -r '.path')

  # store artifact at $path in .$key yml
  spruce json secrets-updated/secrets.yml \
    | jq --arg artifact "$(cat ${path})" ".${ENVIRONMENT}_${key} = \$artifact" \
    | spruce merge \
    > secrets-updated/tmp.yml
  mv secrets-updated/tmp.yml secrets-updated/secrets.yml

done

# list bosh passwords to generate
mapping=$(cat << EOF
[
  {"key": "bosh_nats_password"},
  {"key": "bosh_admin_password"},
  {"key": "bosh_director_password"},
  {"key": "bosh_agent_password"},
  {"key": "bosh_registry_password"},
  {"key": "bosh_uaa_hm_client_secret"},
  {"key": "bosh_uaa_admin_client_secret"},
  {"key": "bosh_uaa_login_client_secret"},
  {"key": "bosh_uaa_ci_client_secret"},
  {"key": "bosh_uaa_bosh_exporter_client_secret"}
]
EOF
)

# Generate passwords and store in yml
for row in $(echo $mapping | jq -c '.[]'); do

  key=$(echo $row | jq -r '.key')

  # store password in secrets.$key yml
  spruce json secrets-updated/secrets.yml \
  | jq --arg password "$(cat /dev/urandom | LC_ALL=C tr -dc "a-zA-Z0-9" | head -c 32)" ".${ENVIRONMENT}_${key} = \$password" \
    | spruce merge \
    > secrets-updated/tmp.yml
  mv secrets-updated/tmp.yml secrets-updated/secrets.yml

done

# generate new secrets passphrase each time we update secrets
## all pipelines consuming these secrets (including this one) will need to be updated before running again.
## use PASSPHRASE from env/pipeline configs for now.
#PASSPHRASE=$(cat /dev/urandom | LC_ALL=C tr -dc "a-zA-Z0-9" | head -c 32)

# store environment secrets passphrase in the secrets
spruce json secrets-updated/secrets.yml \
| jq --arg password "${PASSPHRASE}" ".${ENVIRONMENT}_secrets_secrets_passphrase = \$password" \
  | spruce merge \
  > secrets-updated/tmp.yml
mv secrets-updated/tmp.yml secrets-updated/secrets.yml

# Encrypt updated secrets
INPUT_FILE=secrets-updated/secrets.yml \
  OUTPUT_FILE=secrets-updated/secrets-encrypted.yml \
  PASSPHRASE="${PASSPHRASE}" \
  pipeline-tasks/encrypt.sh
