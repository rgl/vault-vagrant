#!/bin/bash
set -eux

domain=$(hostname --fqdn)
export VAULT_ADDR="https://$domain:8200"

# add the goldfish user.
groupadd --system goldfish
adduser \
    --system \
    --disabled-login \
    --no-create-home \
    --gecos '' \
    --ingroup goldfish \
    --home /opt/goldfish \
    goldfish
install -d -o root -g goldfish -m 755 /opt/goldfish

# install goldfish.
goldfish_version=0.9.0
goldfish_artifact=goldfish-linux-amd64
goldfish_artifact_url=https://github.com/Caiyeon/goldfish/releases/download/v$goldfish_version/$goldfish_artifact
goldfish_artifact_sha=a716db6277afcac21a404b6155d0c52b1d633f27d39fba240aae4b9d67d70943
goldfish_artifact_path=/tmp/$goldfish_artifact
wget -q $goldfish_artifact_url -O$goldfish_artifact_path
if [ "$(sha256sum $goldfish_artifact_path | awk '{print $1}')" != "$goldfish_artifact_sha" ]; then
    echo "downloaded $goldfish_artifact_url failed the checksum verification"
    exit 1
fi
install -d /opt/goldfish/bin
install -m 755 $goldfish_artifact_path /opt/goldfish/bin/goldfish
/opt/goldfish/bin/goldfish -version

# configure.
# see https://github.com/Caiyeon/goldfish/wiki/Production-Deployment
install -o root -g goldfish -m 750 -d /opt/goldfish/etc
install -o root -g goldfish -m 440 /vagrant/shared/example-ca/$domain-crt.pem /opt/goldfish/etc
install -o root -g goldfish -m 440 /vagrant/shared/example-ca/$domain-key.pem /opt/goldfish/etc
install -o root -g goldfish -m 640 /dev/null /opt/goldfish/etc/goldfish.hcl
cat >/opt/goldfish/etc/goldfish.hcl <<EOF
disable_mlock = true

listener "tcp" {
    address = "0.0.0.0:8000"

    certificate "local" {
        cert_file = "/opt/goldfish/etc/$domain-crt.pem"
        key_file  = "/opt/goldfish/etc/$domain-key.pem"
    }
}

vault {
    address = "$VAULT_ADDR"
}
EOF

# configure vault for goldfish.
vault policy write \
    goldfish \
    - <<EOF
# goldfish hot-reloads from this endpoint every minute
path "secret/goldfish" {
    capabilities = ["read", "update"]
}
EOF
vault write \
    auth/approle/role/goldfish \
    role_name=goldfish \
    policies=default,goldfish \
    secret_id_num_uses=1 \
    secret_id_ttl=5m \
    period=24h \
    token_ttl=0 \
    token_max_ttl=0
vault write \
    auth/approle/role/goldfish/role-id \
    role_id=goldfish
vault write \
    secret/goldfish \
    DefaultSecretPath=secret/ \
    UserTransitKey=usertransit \
    BulletinPath=secret/bulletins/

# run as a service.
# see https://www.goldfishproject.io/guides/production.html
# see https://www.goldfishproject.io/docs/internals/security.html
cat >/etc/systemd/system/goldfish.service <<'EOF'
[Unit]
Description=goldfish
After=network.target

[Service]
Type=simple
User=goldfish
Group=goldfish
ExecStart=/opt/goldfish/bin/goldfish -config=/opt/goldfish/etc/goldfish.hcl
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# start the service.
systemctl start goldfish
sleep 3
journalctl -u goldfish

# bootstrap goldfish.
bootstrap_wrapping_token="$(vault write -f -wrap-ttl=1m -field=wrapping_token auth/approle/role/goldfish/secret-id)"
bootstrap_result_json="$(http --ignore-stdin POST https://$domain:8000/v1/bootstrap "wrapping_token=$bootstrap_wrapping_token")"
bootstrap_result="$(echo "$bootstrap_result_json" | jq -r .result)"
if [ "$bootstrap_result" != "success" ]; then
    echo "ERROR: failed to bootstrap goldfish with error: $(echo "$bootstrap_result_json" | jq -r .error)"
    exit 1
fi
