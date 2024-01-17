#!/bin/bash
set -euxo pipefail


# wait for a specific vault state.
# see https://developer.hashicorp.com/vault/api-docs/system/health
function wait-for-state {
    local desired_state="$1"
    local vault_health_check_url="$VAULT_ADDR/v1/sys/health"
    while true; do
        local status_code="$(
            (wget \
                -qO- \
                --server-response \
                --spider \
                --tries=1 \
                "$vault_health_check_url" \
                2>&1 || true) \
                | awk '/^  HTTP/{print $2}')"
        case "$status_code" in
            "$desired_state")
                return 0
                ;;
            *)
                sleep 5
                ;;
        esac
    done
}


# install vault.
# see https://learn.hashicorp.com/vault/operations/production-hardening
# see https://www.vaultproject.io/docs/internals/security.html
# see https://github.com/hashicorp/vault
# NB execute `apt-cache madison vault` to known the available versions.
# renovate: datasource=github-releases depName=hashicorp/vault
vault_version='1.15.4'
apt-get install -y software-properties-common apt-transport-https gnupg
wget -qO- https://apt.releases.hashicorp.com/gpg \
    | gpg --dearmor >/etc/apt/keyrings/apt.releases.hashicorp.com.gpg
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/apt.releases.hashicorp.com.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    >/etc/apt/sources.list.d/apt.releases.hashicorp.com.list
apt-get update
vault_apt_version="$(apt-cache madison vault | perl -ne "/\s($vault_version(-.+?)?)\s/ && print \$1")"
apt-get install -y "vault=${vault_apt_version}"
vault -v

# configure the service to auto-unseal vault.
install -d /etc/systemd/system/vault.service.d
cat >/etc/systemd/system/vault.service.d/override.conf <<'EOF'
[Service]
ExecStartPost=
ExecStartPost=+/opt/vault/auto-unseal/unseal
EOF
systemctl daemon-reload

# configure.
domain=$(hostname --fqdn)
export VAULT_ADDR="https://$domain:8200"
echo export VAULT_ADDR="https://$domain:8200" >>~/.bash_login
install -o vault -g vault -m 770 -d /etc/vault.d
install -o root -g vault -m 710 -d /opt/vault
install -o vault -g vault -m 700 -d /opt/vault/data
install -o root -g vault -m 750 -d /opt/vault/tls
install -o root -g vault -m 440 /vagrant/shared/example-ca/$domain-crt.pem /opt/vault/tls
install -o root -g vault -m 440 /vagrant/shared/example-ca/$domain-key.pem /opt/vault/tls
cat >/etc/vault.d/vault.hcl <<EOF
cluster_name = "example"
disable_mlock = true
ui = true

# one of: trace, debug, info, warning, error.
log_level = "trace"

storage "file" {
    path = "/opt/vault/data"
}

listener "tcp" {
    address = "0.0.0.0:8200"
    cluster_address = "0.0.0.0:8201"
    tls_disable = false
    tls_cert_file = "/opt/vault/tls/$domain-crt.pem"
    tls_key_file = "/opt/vault/tls/$domain-key.pem"
    telemetry {
        unauthenticated_metrics_access = true
    }
}

api_addr = "https://$domain:8200"
cluster_addr = "https://$domain:8201"

# enable the telemetry endpoint.
# access it at https://$domain:8200/v1/sys/metrics?format=prometheus
# see https://www.vaultproject.io/docs/configuration/telemetry
# see https://www.vaultproject.io/docs/configuration/listener/tcp#telemetry-parameters
telemetry {
   disable_hostname = true
   prometheus_retention_time = "24h"
}
EOF
chown root:vault /etc/vault.d/vault.hcl
chmod 440 /etc/vault.d/vault.hcl
install -o root -g root -m 700 -d /opt/vault/auto-unseal
install -o root -g root -m 500 /dev/null /opt/vault/auto-unseal/unseal
echo '#!/bin/bash' >/opt/vault/auto-unseal/unseal

# disable swap.
swapoff --all
sed -i -E 's,^(\s*[^#].+\sswap.+),#\1,g' /etc/fstab

# start vault.
systemctl enable vault
systemctl start vault
wait-for-state 501 # wait for the not-initialized state.
journalctl -u vault

# init vault.
# NB vault-operator-init-result.txt will have something like:
#       Unseal Key 1: sXiqMfCPiRNGvo+tEoHVGy+FHFW092H7vfOY0wPrzpYh
#       Unseal Key 2: dCm5+NhacPcX6GwI0IMMK+CM0xL6wif5/k0LJ0XTPHhy
#       Unseal Key 3: YjbM3TANam0dO9FTa0y/2wj7nxnlDyct7oVMksHs7trE
#       Unseal Key 4: CxWG0yrF75cIYsKvWQBku8klN9oPaPJDWqO7l7LNWX2A
#       Unseal Key 5: C+ttQv3KeViOkIxVZH7gXuZ7iZPKi0va1/lUBSiMeyLz
#       Initial Root Token: d2bb2175-2264-d18b-e8d8-18b1d8b61278
#
#       Vault initialized with 5 keys and a key threshold of 3. Please
#       securely distribute the above keys. When the vault is re-sealed,
#       restarted, or stopped, you must provide at least 3 of these keys
#       to unseal it again.
#
#       Vault does not store the master key. Without at least 3 keys,
#       your vault will remain permanently sealed.
pushd ~
install -o root -g root -m 600 /dev/null vault-operator-init-result.txt
install -o root -g root -m 600 /dev/null /opt/vault/auto-unseal/unseal-keys.txt
install -o root -g root -m 600 /dev/null .vault-token
vault operator init >vault-operator-init-result.txt
awk '/Unseal Key [0-9]+: /{print $4}' vault-operator-init-result.txt | head -3 >/opt/vault/auto-unseal/unseal-keys.txt
awk '/Initial Root Token: /{print $4}' vault-operator-init-result.txt | tr -d '\n' >.vault-token
cp .vault-token /vagrant/shared/vault-root-token.txt
popd
cat >/opt/vault/auto-unseal/unseal <<EOF
#!/bin/bash
set -eu
export VAULT_ADDR='$VAULT_ADDR'
# wait for vault to be ready.
# see https://developer.hashicorp.com/vault/api-docs/system/health
VAULT_HEALTH_CHECK_URL="\$VAULT_ADDR/v1/sys/health"
while true; do
    status_code="\$(
        (wget \
            -qO- \
            --server-response \
            --spider \
            --tries=1 \
            "\$VAULT_HEALTH_CHECK_URL" \
            2>&1 || true) \
            | awk '/^  HTTP/{print \$2}')"
    case "\$status_code" in
        # vault is sealed. break the loop, and unseal it.
        503)
            break
            ;;
        # for some odd reason vault is already unsealed. anyways, its
        # ready and unsealed, so exit this script.
        200)
            exit 0
            ;;
        # otherwise, wait a bit, then retry the health check.
        *)
            sleep 5
            ;;
    esac
done
KEYS=\$(cat /opt/vault/auto-unseal/unseal-keys.txt)
for key in \$KEYS; do
    /usr/bin/vault operator unseal \$key
done
EOF
/opt/vault/auto-unseal/unseal

# restart vault to verify that the automatic unseal is working.
systemctl restart vault
wait-for-state 200 # wait for the unsealed state.
journalctl -u vault
vault status

# show the vault tls certificate.
openssl s_client -connect $domain:8200 -servername $domain </dev/null 2>/dev/null | openssl x509 -noout -text

# show information about our own token.
# see https://www.vaultproject.io/api/auth/token#lookup-a-token-self
vault token lookup
http $VAULT_ADDR/v1/auth/token/lookup-self \
    "X-Vault-Token: $(cat ~/.vault-token)" \
    | jq .data

# enable auditing to stdout (use journalctl -u vault to see it).
# see https://www.vaultproject.io/docs/commands/audit/enable.html
# see https://www.vaultproject.io/docs/audit/file.html
vault audit enable file file_path=stdout log_raw=true
vault audit list

# enable the userpass authentication method.
# NB this is needed by our examples.
vault auth enable userpass

# list enabled authentication methods.
vault auth list

# enable the PostgreSQL database secrets engine.
# NB this is needed by our examples.
vault secrets enable database

# configure the greetings PostgreSQL database.
# see https://learn.hashicorp.com/vault/secrets-management/sm-dynamic-secrets#postgresql
# see https://learn.hashicorp.com/vault/secrets-management/db-root-rotation
# see https://www.postgresql.org/docs/14/libpq-connect.html#LIBPQ-CONNSTRING
# see https://www.postgresql.org/docs/14/sql-createrole.html
# see https://www.postgresql.org/docs/14/sql-grant.html
# see https://www.vaultproject.io/docs/secrets/databases/postgresql.html
# see https://www.vaultproject.io/api/secret/databases/postgresql.html
vault write database/config/greetings \
    plugin_name=postgresql-database-plugin \
    allowed_roles=greetings-admin,greetings-reader \
    connection_url='postgresql://{{username}}:{{password}}@postgresql.example.com:5432/greetings?sslmode=verify-full' \
    username=vault \
    password=abracadabra
#vault write -force database/rotate-root/greetings # immediatly rotate the root password (in this case, the vault username password).
vault read -format=json database/config/greetings | jq .data
# NB db_name must match the database/config/:db_name
vault write database/roles/greetings-admin \
    db_name=greetings \
    creation_statements="
create role \"{{name}}\" with login password '{{password}}' valid until '{{expiration}}';
comment on role \"{{name}}\" is 'vault role greetings-admin';
grant all privileges on all tables in schema public to \"{{name}}\";
" \
    default_ttl=1h \
    max_ttl=24h
vault read -format=json database/roles/greetings-admin | jq .data
# NB db_name must match the database/config/:db_name
vault write database/roles/greetings-reader \
    db_name=greetings \
    creation_statements="
create role \"{{name}}\" with login password '{{password}}' valid until '{{expiration}}';
comment on role \"{{name}}\" is 'vault role greetings-reader';
grant select on all tables in schema public to \"{{name}}\";
" \
    default_ttl=1h \
    max_ttl=24h
vault read -format=json database/roles/greetings-reader | jq .data
echo 'You can create a user to administer the greetings database with: vault read database/creds/greetings-admin'
echo 'You can create a user to access the greetings database with: vault read database/creds/greetings-reader'

# create the policy for our use-postgresql example.
vault policy write use-postgresql - <<EOF
path "database/creds/greetings-admin" {
    capabilities = ["read"]
}
path "database/creds/greetings-reader" {
    capabilities = ["read"]
}
EOF

# create the user for our use-postgresql example.
vault write auth/userpass/users/use-postgresql \
    password=abracadabra \
    policies=use-postgresql

# list database connections/names.
vault list -format=json database/config

# list the active secret backends.
vault secrets list

# show the default policy.
# see https://www.vaultproject.io/docs/concepts/policies.html
vault read sys/policy/default

# list the active authentication backends.
# see https://www.vaultproject.io/intro/getting-started/authentication.html
# see https://github.com/hashicorp/vault/issues/3456
vault path-help sys/auth
http $VAULT_ADDR/v1/sys/auth "X-Vault-Token: $(cat ~/.vault-token)" \
    | jq -r 'keys[] | select(endswith("/"))'

# enable the kv 2 secrets engine.
vault secrets enable -version=2 -path=secret kv

# write an example secret, read it back and delete it.
# see https://www.vaultproject.io/docs/commands/read-write.html
echo -n abracadabra | vault kv put secret/example username=alibaba password=-
vault kv get -format=json secret/example    # read all the fields as json.
vault kv get secret/example                 # read all the fields.
vault kv get -field=password secret/example # read just the password field.
vault kv metadata delete secret/example     # delete the secret and all its versions.
vault kv get secret/example || true

# install command line autocomplete.
vault -autocomplete-install
