# Automated package testing script for Foreman

This script uses the Foreman API to spin up a VM in a specified host group,
waits until the VM is built, then SSH's in to the new VM (on the IP supplied by
Foreman) and installs the latest nightly version of "foreman" and "foreman-sqlite3"
It then makes a request to the new instance of Foreman to ensure the packages 
have some basic smoke-testing.

# Pre-requisites

* Libvirt on your primary Foreman server
* DHCP proxy to suggest IPs
* A dedicated Hostgroup with a clean installation template (no puppet, etc)

# Usage

Edit package\_test.rb and set the user\_data hash up with your details. Then you run

    ./package_test.rb <user> <pass>

Where the 2 args are the credentials for your libvirt-capable Foreman instance

# Todo

* Add commandline option parsing
* Allow fallback to hostgroup defaults if option not specified (for arch, os, etc)

# License / Copyright

Copyright (c) 2013 Greg Sutcliffe

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
