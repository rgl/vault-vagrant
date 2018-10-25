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
vault_version=0.11.4
vault_artifact=vault_${vault_version}_linux_amd64.zip
vault_artifact_url=https://releases.hashicorp.com/vault/$vault_version/$vault_artifact
vault_artifact_sha=3e44826ffcf3756a72d6802d96ea244e605dad362ece27d5c8f8839fb69a7079
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
# see https://www.vaultproject.io/guides/production.html
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

storage "file" {
    path = "/opt/vault/data"
}

listener "tcp" {
    address = "0.0.0.0:8200"
    tls_disable = false
    tls_cert_file = "/opt/vault/etc/$domain-crt.pem"
    tls_key_file = "/opt/vault/etc/$domain-key.pem"
}
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
# NB vault-init-result.txt will have something like:
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
install -o root -g root -m 600 /dev/null vault-init-result.txt
install -o root -g root -m 600 /dev/null /opt/vault/etc/vault-unseal-keys.txt
install -o root -g root -m 600 /dev/null .vault-token
vault init >vault-init-result.txt
awk '/Unseal Key [0-9]+: /{print $4}' vault-init-result.txt | head -3 >/opt/vault/etc/vault-unseal-keys.txt
awk '/Initial Root Token: /{print $4}' vault-init-result.txt >.vault-token
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

# list the active authentication methods.
vault auth list

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

# write an example secret, read it back and delete it.
# see https://www.vaultproject.io/docs/commands/read-write.html
echo -n abracadabra | vault write secret/example password=- other_key=value
vault read -format=json secret/example      # read all the fields as json.
vault read secret/example                   # read all the fields.
vault read -field=password secret/example   # read just the password field.
vault delete secret/example
vault read secret/example || true

# install command line autocomplete.
vault -autocomplete-install
