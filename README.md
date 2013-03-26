# Automated package testing script for Foreman

This script uses the Foreman API to spin up a VM in a specified host group,
waits until the VM is built, then SSH's in to the new VM (on the IP supplied by
Foreman) and clones/runs the foreman-installer, with any configured extra pull
requests. Thus we can do basic smoke testing on submitted PRs and new packages.

# Pre-requisites

* Libvirt on your primary Foreman server
* DHCP proxy to suggest IPs
* A dedicated Hostgroup with a clean installation template. I use
  * Standard Debian PXE
  * Standard Debian Install
  * Custom finish which just installs git and curl

_Important_: Don't sign the client cert (`puppet agent --tags no_such_tag` ...) -
signing the cert will break the installer's puppetmaster module

# Usage

Create `options.yaml` in the same dir as the checkout and populate with appropriate
data. As a minimum, you probably want your credentials and foreman url:

    ---
    options:
      :user: myadmin
      :pass: mypass
      :url: 'https://myforeman'

Add any further options required to override the defaults at the top of `package_test.rb`

You should also specify a URL (relative to your foreman server) to get the answers
file from:

    :answersfile: custom.yaml

This would correspond to `https://myforeman/custom.yaml` which would be placed in
`/public` on the foreman server. If not specified it defaults to `basic.yaml`

You can optionally specify a port (defaults to 443):

    :port: 80

You can also specify some pull requests to merge in and test. Start with the module,
and the the full git command to merge the PR. For example, here's a pair of PRs that
need to be tested together:

    :puppet:
    - "git pull https://github.com/oxilion/puppet-puppet.git storeconfigs"
    :foreman:
    - "git pull https://github.com/oxilion/puppet-foreman.git storeconfigs"

You can get the correct command direct from the PR notification email that Github
sends out. Currently only puppet, foreman, and foreman\_proxy are checked for PRs,
adding more is easy enough.

A complete file looks like this:

    ---
    options:
      :user: admin
      :pass: f4nGl3d
      :url: 'https://topaz'
    :answersfile: custom.yaml
    :puppet:
    - "git pull https://github.com/oxilion/puppet-puppet.git storeconfigs"
    :foreman:
    - "git pull https://github.com/oxilion/puppet-foreman.git storeconfigs"

Finally, run `package_test.rb` which will create the vm and execute the required
commands. The script will skip host creation if it already exists - optionally you
can pass `-d` to delete and reinstall the host

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
