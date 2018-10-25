Vagrant.configure(2) do |config|
  config.vm.box = 'ubuntu-16.04-amd64'

  config.vm.hostname = 'vault.example.com'

  config.vm.provider "libvirt" do |lv|
    lv.memory = 2048
    lv.cpus = 2
    lv.cpu_mode = "host-passthrough"
    lv.nested = true
    lv.keymap = "pt"
  end

  config.vm.provider 'virtualbox' do |vb|
    vb.linked_clone = true
    vb.memory = 2048
    vb.cpus = 2
  end

  config.vm.provision 'shell', path: 'provision.sh'
  config.vm.provision 'shell', path: 'provision-certification-authority.sh'
  config.vm.provision 'shell', path: 'provision-certificate.sh', args: config.vm.hostname
  config.vm.provision 'shell', path: 'provision-vault.sh'
end
