import hvac
import json
import os
import textwrap

if hasattr(textwrap, 'indent'): # Python 3+?
    def indent(text, amount, ch=' '):
        return textwrap.indent(text, amount * ch)
else:
    def indent(text, amount, ch=' '):
        padding = amount * ch
        return ''.join(padding+line for line in text.splitlines(True))

vault_addr = 'https://vault.example.com:8200'
vault_token = open(os.path.expanduser('~/.vault-token')).read().strip()

client = hvac.Client(url=vault_addr, token=vault_token)

# see https://www.vaultproject.io/api/system/auth.html
# see https://github.com/hashicorp/vault/issues/3456
backends = client.list_auth_backends()

print('authentication backends:')
for path, backend in backends.items():
    if path.endswith('/'):
        print(
            '%s\n%s' % (
                path,
                indent(
                    json.dumps(backend, sort_keys=True, indent=4, separators=(',', ': ')),
                    4)))
