#!/usr/bin/env ruby

require 'yaml'
require './vm_builder'
# For printing progress dots
STDOUT.sync = true

# To configure, copy the hash below to a file in this dir called options.yaml
# and alter appropriately

load_data = YAML.load_file('./options.yaml')
user_data = {
  :user             => 'admin',
  :pass             => 'changeme',
  :url              => 'https://foreman',
  :hostname         => "packaging#{`date '+%Y%m%d'`.chomp}",
  :net_dev          => 'br0',
  :disk_size        => '5G',
  :hostgroup        => 'Packaging',
  :environment      => 'production',
  :compute_resource => 'Jade',
  :architecture     => 'x86_64',
  :os_name          => 'Debian',
  :os_version       => '7',
  :location         => 1, # No API calls to figure these out by name yet
  :organisation     => 2,
  :delete           => false,
}.merge load_data['options']

user_data[:delete] = true if ARGV[0] == "-d"

# Test connection port
final_port = load_data[:port] || 443

# Answers file:
answers = load_data[:answers] || "---\n"

# Any pull requests to try?
do_pull_requests = []
[:apache,:passenger,:puppet,:foreman,:foreman_proxy,:tftp].each do |mod|
  unless load_data[mod].nil? or load_data[mod].empty?
    do_pull_requests << [
      "cd /tmp/f-i/#{mod.to_s}",
      load_data[mod],
    ]
    do_pull_requests.flatten!
  end
end

# These will be joined with "&&" and executed over SSH
setup_commands = [
  "echo -en 'Puppet version: ' && puppet --version",
  "rm -rf /tmp/f-i",
  "git clone -b develop --recursive https://github.com/theforeman/foreman-installer /tmp/f-i",
  do_pull_requests,
  "echo -e \"#{answers.to_yaml}\" > /tmp/f-i/foreman_installer/answers.yaml",
  "echo include foreman_installer | puppet apply -v --modulepath /tmp/f-i --show_diff",
].flatten

### Code starts here ###

vm_builder = VmBuilder.new(user_data)

# Check Foreman is alive
vm_builder.check_connection

# build the host (if required)
vm_builder.check_and_create_host

# Monitor build status
vm_builder.wait_for_connection

# Log in and setup up Foreman
vm_builder.ssh_setup(setup_commands)

# Test if the new foreman instance is operational
protocol = final_port == 443 ? 'https' : 'http'
VmBuilder.new({:url  => "#{protocol}://#{vm_builder.ip}:#{final_port}"}).check_connection
