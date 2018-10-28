Vagrant.configure(2) do |config|
  config.vm.box = 'ubuntu-18.04-amd64'

  config.vm.hostname = 'vault.example.com'

  config.vm.provider 'libvirt' do |lv, config|
    lv.memory = 2048
    lv.cpus = 2
    lv.cpu_mode = 'host-passthrough'
    lv.nested = false
    lv.keymap = 'pt'
    config.vm.synced_folder '.', '/vagrant', type: 'nfs'
  end

  config.vm.provider 'virtualbox' do |vb|
    vb.linked_clone = true
    vb.memory = 2048
    vb.cpus = 2
  end

  config.vm.network 'private_network', ip: '10.0.0.20', libvirt__forward_mode: 'route', libvirt__dhcp_enabled: false

  config.vm.provision 'shell', path: 'provision.sh'
  config.vm.provision 'shell', path: 'provision-certification-authority.sh'
  config.vm.provision 'shell', path: 'provision-certificate.sh', args: config.vm.hostname
  config.vm.provision 'shell', path: 'provision-certificate.sh', args: 'postgresql.example.com'
  config.vm.provision 'shell', path: 'provision-postgresql.sh'
  config.vm.provision 'shell', path: 'provision-vault.sh'
  config.vm.provision 'shell', path: 'provision-goldfish.sh'
  config.vm.provision 'shell', path: 'examples/python/list-auth-backends/run.sh'
  config.vm.provision 'shell', path: 'examples/python/use-postgresql/run.sh'
end
