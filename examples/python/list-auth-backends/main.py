import hvac
import json
import os
import textwrap

def indent(text, amount, ch=' '):
    return textwrap.indent(text, amount * ch)

vault_addr = 'https://vault.example.com:8200'
vault_token = open(os.path.expanduser('~/.vault-token')).read().strip()

client = hvac.Client(url=vault_addr, token=vault_token)

# see https://www.vaultproject.io/api/system/auth.html
# see https://github.com/hashicorp/vault/issues/3456
# see https://hvac.readthedocs.io/en/v2.3.0/usage/system_backend/auth.html#list-auth-methods
backends = client.sys.list_auth_methods()

print('authentication backends:')
for path, backend in backends.items():
    if path.endswith('/'):
        print(
            '%s\n%s' % (
                path,
                indent(
                    json.dumps(backend, sort_keys=True, indent=4, separators=(',', ': ')),
                    4)))
