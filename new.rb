#!/usr/bin/ruby

# New version involving Hammer-CLI!
require '../vmbuilder/vm_builder'
require 'optparse'

# For printing progress dots
STDOUT.sync = true

# Input variables. Relies on:
#   * deb_repo being used as a host parameter in the finish script
#   * Puppet being installed in the finish script

OptionParser.new do |o|
  o.on('-i IMAGENAME') { |image| $image = image }
  o.on('-h') { puts o; exit }
  o.parse!
end
p :image => $image

data = {
  :name             => 'test',
  :hostgroup        => 'Packaging',
  :compute_resource => 'Amethyst',
  :image            => $image || 'Debian Wheezy',

  :deb_repo         => 'nightly',

  :installerflags  => [
    '--no-colors',
    '--enable-foreman',
    '--enable-foreman-proxy',
    '--enable-puppet',
  ],

  # PRs to test
  :prs => {
    :foreman          => [111],
    :foreman_proxy    => [80],
  },
}

# Any pull requests to try?
do_pull_requests = []
data[:prs].each do |mod,prs|
  do_pull_requests << [
    "cd /usr/share/foreman-installer/modules/#{mod.to_s}",
    prs.map {|pr| ["wget https://github.com/theforeman/puppet-#{mod}/pull/#{pr}.patch", "patch -p1 < #{pr}.patch"] }
  ]
  do_pull_requests.flatten!
end

# These will be joined with "&&" and executed over SSH
setup_commands = [
  "echo -en 'Puppet version: ' && puppet --version",
  "apt-get install foreman-installer -y",
  do_pull_requests,
  "/usr/bin/foreman-installer #{data[:installerflags].join(' ')}",
  "puppet agent -tv"
].flatten

p data
# Build the VM
vm = VmBuilder.new data
puts "Creating #{vm.hostname} (timeout in creation is expected)"
vm.create!
vm.wait_for_ssh!

# Set up Foreman
vm.ssh setup_commands

# Test Foreman
vm.test_foreman

# Cleanup
#vm.delete!
