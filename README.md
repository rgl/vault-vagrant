Install the [Ubuntu Base Box](https://github.com/rgl/ubuntu-vagrant).

Run `vagrant up --provider=libvirt` to launch with libvirt (qemu-kvm).

Run `vagrant up --provider=virtualbox` to launch with VirtualBox.

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
