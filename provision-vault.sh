#!/bin/bash
set -eux

# add the vault user.
groupadd --system vault
adduser \
    --system \
    --disabled-login \
    --no-create-home \
    --gecos '' \
    --ingroup vault \
    --home /opt/vault \
    vault
install -d -o root -g vault -m 755 /opt/vault

# install vault.
vault_version=1.4.0
vault_artifact=vault_${vault_version}_linux_amd64.zip
vault_artifact_url=https://releases.hashicorp.com/vault/$vault_version/$vault_artifact
vault_artifact_sha=8f739c4850bab35e971e27c8120908f48f247b07717d19aabad1110e9966cded
vault_artifact_zip=/tmp/$vault_artifact
wget -q $vault_artifact_url -O$vault_artifact_zip
if [ "$(sha256sum $vault_artifact_zip | awk '{print $1}')" != "$vault_artifact_sha" ]; then
    echo "downloaded $vault_artifact_url failed the checksum verification"
    exit 1
fi
install -d /opt/vault/bin
unzip $vault_artifact_zip -d /opt/vault/bin
ln -s /opt/vault/bin/vault /usr/local/bin
vault -v

# run as a service.
# see https://learn.hashicorp.com/vault/operations/production-hardening
# see https://www.vaultproject.io/docs/internals/security.html
cat >/etc/systemd/system/vault.service <<'EOF'
[Unit]
Description=Vault
After=network.target

[Service]
Type=simple
User=vault
Group=vault
PermissionsStartOnly=true
ExecStart=/opt/vault/bin/vault server -config=/opt/vault/etc/vault.hcl
ExecStartPost=/opt/vault/bin/vault-unseal
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# configure.
domain=$(hostname --fqdn)
export VAULT_ADDR="https://$domain:8200"
echo export VAULT_ADDR="https://$domain:8200" >>~/.bash_login
install -o vault -g vault -m 700 -d /opt/vault/data
install -o root -g vault -m 750 -d /opt/vault/etc
install -o root -g vault -m 440 /vagrant/shared/example-ca/$domain-crt.pem /opt/vault/etc
install -o root -g vault -m 440 /vagrant/shared/example-ca/$domain-key.pem /opt/vault/etc
install -o root -g vault -m 640 /dev/null /opt/vault/etc/vault.hcl
cat >/opt/vault/etc/vault.hcl <<EOF
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
    tls_cert_file = "/opt/vault/etc/$domain-crt.pem"
    tls_key_file = "/opt/vault/etc/$domain-key.pem"
}

api_addr = "https://$domain:8200"
cluster_addr = "https://$domain:8201"
EOF
install -o root -g root -m 700 /dev/null /opt/vault/bin/vault-unseal
echo '#!/bin/bash' >/opt/vault/bin/vault-unseal

# disable swap.
swapoff --all
sed -i -E 's,^(\s*[^#].+\sswap.+),#\1,g' /etc/fstab

# start vault.
systemctl enable vault
systemctl start vault
sleep 3
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
install -o root -g root -m 600 /dev/null /opt/vault/etc/vault-unseal-keys.txt
install -o root -g root -m 600 /dev/null .vault-token
vault operator init >vault-operator-init-result.txt
awk '/Unseal Key [0-9]+: /{print $4}' vault-operator-init-result.txt | head -3 >/opt/vault/etc/vault-unseal-keys.txt
awk '/Initial Root Token: /{print $4}' vault-operator-init-result.txt | tr -d '\n' >.vault-token
cp .vault-token /vagrant/shared/vault-root-token.txt
popd
cat >/opt/vault/bin/vault-unseal <<EOF
#!/bin/bash
set -eu
sleep 3 # to give vault some time to initialize before we hit its api.
KEYS=\$(cat /opt/vault/etc/vault-unseal-keys.txt)
for key in \$KEYS; do
    /opt/vault/bin/vault operator unseal -address=$VAULT_ADDR \$key
done
EOF
/opt/vault/bin/vault-unseal

# restart vault to verify that the automatic unseal is working.
systemctl restart vault
sleep 3
journalctl -u vault
vault status

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
# see https://www.postgresql.org/docs/10/static/libpq-connect.html#LIBPQ-CONNSTRING
# see https://www.postgresql.org/docs/10/static/sql-createrole.html
# see https://www.postgresql.org/docs/10/static/sql-grant.html
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
echo -n abracadabra | vault kv put secret/example password=- other_key=value
vault kv get -format=json secret/example    # read all the fields as json.
vault kv get secret/example                 # read all the fields.
vault kv get -field=password secret/example # read just the password field.
vault kv metadata delete secret/example     # delete the secret and all its versions.    
vault kv get secret/example || true

# install command line autocomplete.
vault -autocomplete-install
