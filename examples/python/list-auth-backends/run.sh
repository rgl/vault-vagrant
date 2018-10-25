#!/bin/bash
set -eux

pushd /vagrant/examples/python/list-auth-backends

# install dependencies.
apt-get install -y python-pip
python -m pip install -r requirements.txt

# run.
export REQUESTS_CA_BUNDLE='/etc/ssl/certs/ca-certificates.crt'
python main.py

popd
