#!/bin/bash
set -eux

# install postgres.
apt-get install -y --no-install-recommends postgresql

# setup tls.
install -o postgres -g postgres -m 444 /vagrant/shared/example-ca/postgresql.example.com-crt.pem /etc/postgresql/14/main
install -o postgres -g postgres -m 400 /vagrant/shared/example-ca/postgresql.example.com-key.pem /etc/postgresql/14/main
sed -i -E 's,^#?(ssl\s*=).+,\1 on,g' /etc/postgresql/14/main/postgresql.conf
sed -i -E 's,^#?(ssl_ciphers\s*=).+,\1 '"'HIGH:!aNULL'"',g' /etc/postgresql/14/main/postgresql.conf
sed -i -E 's,^#?(ssl_cert_file\s*=).+,\1 '"'/etc/postgresql/14/main/postgresql.example.com-crt.pem'"',g' /etc/postgresql/14/main/postgresql.conf
sed -i -E 's,^#?(ssl_key_file\s*=).+,\1 '"'/etc/postgresql/14/main/postgresql.example.com-key.pem'"',g' /etc/postgresql/14/main/postgresql.conf

# enable detailed logging.
# see https://www.postgresql.org/docs/14/runtime-config-logging.html
sed -i -E 's,^#?(logging_collector\s*=).+,\1 on,g' /etc/postgresql/14/main/postgresql.conf # default is off. # XXX postgres on ubuntu is writting to log files?
sed -i -E 's,^#?(log_min_messages\s*=).+,\1 info,g' /etc/postgresql/14/main/postgresql.conf # default is warning.
sed -i -E 's,^#?(log_statement\s*=).+,\1 '"'all'"',g' /etc/postgresql/14/main/postgresql.conf # default is 'none'.
sed -i -E 's,^#?(log_connections\s*=).+,\1 on,g' /etc/postgresql/14/main/postgresql.conf # default is 'off'.
sed -i -E 's,^#?(log_disconnections\s*=).+,\1 on,g' /etc/postgresql/14/main/postgresql.conf # default is 'off'.
echo 'You can see the postgresql logs with: tail -f /var/lib/postgresql/14/main/log/*.log'

# restart postgres.
systemctl restart postgresql

# create the vault admin user.
# TODO instead of creating a superuser user create one that can only create roles/users?
sudo -sHu postgres psql -c "create role vault superuser login password 'abracadabra'"

# create the greetings database and vault superuser.
sudo -sHu postgres createdb -E UTF8 -O postgres greetings >/dev/null
sudo -sHu postgres psql greetings >/dev/null <<'EOF'
create table greeting(lang char(2) primary key, message varchar(128) not null);
insert into greeting(lang, message) values('pt', 'Olá Mundo');
insert into greeting(lang, message) values('es', 'Hola Mundo');
insert into greeting(lang, message) values('fr', 'Bonjour le Monde');
insert into greeting(lang, message) values('it', 'Ciao Mondo');
insert into greeting(lang, message) values('en', 'Hello World');
EOF

# show version, users and databases.
sudo -sHu postgres psql -c 'select version()'
sudo -sHu postgres psql -c '\du'
sudo -sHu postgres psql -l
