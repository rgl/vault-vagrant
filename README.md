Install the [Ubuntu Base Box](https://github.com/rgl/ubuntu-vagrant).

Run `vagrant up --provider=libvirt --no-destroy-on-error` to launch with libvirt (qemu-kvm).

Add the following entry to your `hosts` file:

```
10.0.0.20 vault.example.com
```

Browse to the [UI](https://vault.example.com:8200/ui) and login with the vault root token (get it from the `shared/vault-root-token.txt` file).

Test the [prometheus telemetry endpoint](https://vault.example.com:8200/v1/sys/metrics?format=prometheus).

# TLS

Verify that a secure connection with vault can be established:

```bash
vagrant ssh
echo -n | openssl s_client -CAfile /etc/ssl/certs/ca-certificates.crt -servername vault.example.com -connect vault.example.com:8200
```

And make sure the result has no errors, e.g.:

```
depth=1 CN = Example CA
verify return:1
depth=0 CN = vault.example.com
verify return:1
...
Verification: OK
```


# Reference

* [Why We Need Dynamic Secrets (MAR 01 2018)](https://www.hashicorp.com/blog/why-we-need-dynamic-secrets)
* [Authenticating Applications with HashiCorp Vault AppRole (MAR 13 2018)](https://www.hashicorp.com/blog/authenticating-applications-with-vault-approle)
