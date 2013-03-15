#!/usr/bin/env ruby

require 'vm_builder'
# For printing progress dots
STDOUT.sync = true

### Automated package testing script for Foreman
#
# This script uses the Foreman API to spin up a VM in a specified host group,
# waits until the VM is built, then SSH's in to the new VM (on the IP supplied by
# Foreman) and installs the latest nightly version of "foreman" and "foreman-sqlite3"
# It then makes a request to the new instance of Foreman to ensure the packages 
# have some basic smoke-testing.
#
# Pre-requisites
#
# * Libvirt on your primary Foreman server
# * DHCP proxy to suggest IPs
# * A dedicated Hostgroup with a clean installation template (no puppet, etc)
#
# Alter the data below to configre the script

user_data = {
  :user             => ARGV[0] || 'admin',
  :pass             => ARGV[1] || 'changeme',
  :url              => 'https://topaz',
  :hostname         => "packaging#{`date '+%Y%m%d'`.chomp}",
  :net_dev          => 'br0',
  :disk_size        => '5G',
  :hostgroup        => 'Packaging',
  :compute_resource => 'Jade',
  :architecture     => 'x86_64',
  :os_name          => 'Debian',
  :os_version       => '7',
  :location         => 1, # No API calls to figure these out by name yet
  :organisation     => 2
}

# These will be joined with "&&" and executed over SSH
setup_commands = [
  "apt-get install foreman foreman-sqlite3 -y",
  "echo START=yes > /etc/default/foreman",
  "/etc/init.d/foreman restart"
]

# Stuff to get from the API
#@hostgroup        = 11 # Packaging
#@compute_resource = 7 # Jade
#@location         = 1 # Dollar
#@organisation     = 2 # RedHatDollar

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
VmBuilder.new({:url  => "http://#{vm_builder.ip}:3000"}).check_connection
