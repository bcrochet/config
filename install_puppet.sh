#!/bin/bash

# Copyright 2013 OpenStack Foundation.
# Copyright 2013 Hewlett-Packard Development Company, L.P.
# Copyright 2013 Red Hat, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

# Install pip using get-pip
PIP_GET_PIP_URL=https://raw.githubusercontent.com/pypa/pip/master/contrib/get-pip.py

curl -O $PIP_GET_PIP_URL || wget $PIP_GET_PIP_URL
python get-pip.py

# Install puppet version 2.7.x from puppetlabs.
# The repo and preferences files are also managed by puppet, so be sure
# to keep them in sync with this file.

if cat /etc/*release | grep -e "Fedora" &> /dev/null; then

    yum update -y

    # NOTE: we preinstall lsb_release to ensure facter sets lsbdistcodename
    yum install -y redhat-lsb-core git puppet

    gem install hiera hiera-puppet

    mkdir -p /etc/puppet/modules/
    ln -s /usr/local/share/gems/gems/hiera-puppet-* /etc/puppet/modules/

    # Puppet is expecting the command to be pip-python on Fedora
    ln -s /usr/bin/pip /usr/bin/pip-python

elif cat /etc/*release | grep -e "CentOS" -e "Red Hat" &> /dev/null; then
    if cat /etc/*release | grep -E -e "6\.?" &> /dev/null; then
        epel_url=http://download.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm
        puppet_url=http://yum.puppetlabs.com/el/6/products/x86_64/puppetlabs-release-6-6.noarch.rpm
        puppet_release=6
    elif cat /etc/*release | grep -E -e "7\.?" &> /dev/null; then
        epel_url=http://dl.fedoraproject.org/pub/epel/beta/7/x86_64/epel-release-7-0.1.noarch.rpm
        puppet_url=https://yum.puppetlabs.com/el/7/products/x86_64/puppetlabs-release-7-10.noarch.rpm
        puppet_release=7
    else
        echo "Not a supported RHEL/CentOS platform"
        exit 1
    fi
    rpm -qi epel-release &> /dev/null || rpm -Uvh $epel_url
    rpm -ivh $puppet_url

    if cat /etc/*release | grep -E -e "6\.?" &> /dev/null; then
        cat > /etc/yum.repos.d/puppetlabs.repo <<"EOF"
[puppetlabs-products]
name=Puppet Labs Products El 6 - $basearch
baseurl=http://yum.puppetlabs.com/el/6/products/$basearch
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-puppetlabs
enabled=1
gpgcheck=1
exclude=puppet-2.8* puppet-2.9* puppet-3* facter-2*
EOF
    elif cat /etc/*release | grep -E -e "7\.?" &> /dev/null; then
        cat > /etc/yum.repos.d/puppetlabs.repo <<"EOF"
[puppetlabs-products]
name=Puppet Labs Products El 7 - $basearch
baseurl=http://yum.puppetlabs.com/el/7/products/$basearch
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-puppetlabs
enabled=1
gpgcheck=1
exclude=puppet-2.8* puppet-2.9* puppet-3* facter-2*
EOF
    fi

    yum update -y
    # NOTE: enable the optional-rpms channel (if not already enabled)
    # yum-config-manager --enable rhel-6-server-optional-rpms

    # NOTE: we preinstall lsb_release to ensure facter sets lsbdistcodename
    yum install -y redhat-lsb-core git puppet

    # NOTE: we remove puppetlabs-release since it later conflicts with rdo-release in devstack
    yum remove -y puppetlabs-release
else
    #defaults to Ubuntu
    # NB: keep in sync with openstack_project/files/00-puppet.pref
    cat > /etc/apt/preferences.d/00-puppet.pref <<EOF
Package: puppet puppet-common puppetmaster puppetmaster-common puppetmaster-passenger
Pin: version 2.7*
Pin-Priority: 501

Package: facter
Pin: version 1.*
Pin-Priority: 501
EOF

    lsbdistcodename=`lsb_release -c -s`
    puppet_deb=puppetlabs-release-${lsbdistcodename}.deb
    wget http://apt.puppetlabs.com/$puppet_deb -O $puppet_deb
    dpkg -i $puppet_deb
    rm $puppet_deb

    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get --option 'Dpkg::Options::=--force-confold' \
        --assume-yes dist-upgrade
    DEBIAN_FRONTEND=noninteractive apt-get --option 'Dpkg::Options::=--force-confold' \
        --assume-yes install -y --force-yes puppet git rubygems
fi
