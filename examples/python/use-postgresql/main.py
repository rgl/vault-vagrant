import hvac
import psycopg2

vault_addr = 'https://vault.example.com:8200'
vault_username = 'use-postgresql'
vault_password = 'abracadabra'
vault_pg_greetings_reader_path = 'database/creds/greetings-reader'

# login into vault.
client = hvac.Client(url=vault_addr)
vault_authentication = client.auth_userpass(vault_username, vault_password)
print('vault policies for %s: %r' % (vault_username, vault_authentication['auth']['policies']))

# get the postgresql greetings reader secret.
# NB vault will create a new postgresql user in this call.
# NB the postgresql user will only be valid until the vault secret lease
#    expires (in our example policy, an hour). in a persistent application,
#    you would need to periodically renew the secret lease.
#    see https://www.vaultproject.io/docs/concepts/lease
greetings_reader_secret = client.read(vault_pg_greetings_reader_path)
pg_greetings_reader_username = greetings_reader_secret['data']['username']
pg_greetings_reader_password = greetings_reader_secret['data']['password']
print('pg_greetings_reader_username: %r' % pg_greetings_reader_username)
print('pg_greetings_reader_password: %r' % pg_greetings_reader_password)

def escape_data_source_name_string(value):
    # see https://www.postgresql.org/docs/12/libpq-connect.html#LIBPQ-CONNSTRING
    return '\'%s\'' % value.replace('\\', '\\\\').replace('\'', '\\\'')

data_source_name = ' '.join([
    'sslmode=verify-full',
    'sslrootcert=/etc/ssl/certs/ca-certificates.crt',
    'host=postgresql.example.com',
    'port=5432',
    'user=%s' % escape_data_source_name_string(pg_greetings_reader_username),
    'password=%s' % escape_data_source_name_string(pg_greetings_reader_password),
    'dbname=greetings',
])

# see http://initd.org/psycopg/docs/
# see https://www.postgresql.org/docs/12/libpq-connect.html#LIBPQ-CONNECT-SSLMODE
# NB psycopg2 uses the %APPDATA%\postgresql\root.crt file to validate the server certificate.
def sql_execute_scalar(data_source_name, sql):
    with psycopg2.connect(data_source_name) as connection:
        with connection.cursor() as cursor:
            cursor.execute(sql)
            return cursor.fetchone()[0]

print('PostgreSQL Version:')
print(sql_execute_scalar(data_source_name, 'select version()'))

print('PostgreSQL Current User Name:')
print(sql_execute_scalar(data_source_name, 'select current_user'))

print('Total number of greetings:')
print(sql_execute_scalar(data_source_name, 'select count(*) from greeting'))

print('Random greeting:')
print(sql_execute_scalar(data_source_name, 'select message from greeting order by random() limit 1'))
