# == Class: jenkins::slave
#
class jenkins::slave(
  $ssh_key = '',
  $sudo = false,
  $bare = false,
  $user = true,
  $python3 = false,
  $include_pypy = false,
  $all_mysql_privs = false,
) {

  include pip
  include jenkins::params

  if ($user == true) {
    class { 'jenkins::jenkinsuser':
      ensure  => present,
      ssh_key => $ssh_key,
    }
  }

  anchor { 'jenkins::slave::update-java-alternatives': }

  # Packages that all jenkins slaves need
  $common_packages = [
    $::jenkins::params::jdk_package, # jdk for building java jobs
    $::jenkins::params::ccache_package,
    $::jenkins::params::python_netaddr_package, # Needed for devstack address_in_net()
    $::jenkins::params::haveged_package, # entropy is useful to have
  ]

  # Packages that most jenkins slaves (eg, unit test runners) need
  $standard_packages = [
    $::jenkins::params::ant_package, # for building buck
    $::jenkins::params::awk_package, # for building extract_docs.awk to work correctly
    $::jenkins::params::asciidoc_package, # for building gerrit/building openstack docs
    $::jenkins::params::curl_package,
    $::jenkins::params::docbook_xml_package, # for building openstack docs
    $::jenkins::params::docbook5_xml_package, # for building openstack docs
    $::jenkins::params::docbook5_xsl_package, # for building openstack docs
    $::jenkins::params::gettext_package, # for msgfmt, used in translating manuals
    $::jenkins::params::gnome_doc_package, # for generating translation files for docs
    $::jenkins::params::graphviz_package, # for generating graphs in docs
    $::jenkins::params::firefox_package, # for selenium tests
    $::jenkins::params::mod_wsgi_package,
    $::jenkins::params::language_fonts_packages,
    $::jenkins::params::libcurl_dev_package,
    $::jenkins::params::ldap_dev_package,
    $::jenkins::params::librrd_dev_package, # for python-rrdtool, used by kwapi
    $::jenkins::params::libtidy_package, # for python-tidy, used by sphinxcontrib-docbookrestapi
    $::jenkins::params::libsasl_dev, # for keystone ldap auth integration
    $::jenkins::params::memcached_package, # for tooz unit tests
    $::jenkins::params::mongodb_package, # for ceilometer unit tests
    $::jenkins::params::mysql_dev_package,
    $::jenkins::params::nspr_dev_package, # for spidermonkey, used by ceilometer
    $::jenkins::params::sqlite_dev_package,
    $::jenkins::params::libvirt_dev_package,
    $::jenkins::params::libxml2_package,
    $::jenkins::params::libxml2_dev_package, # for xmllint, need for wadl
    $::jenkins::params::libxslt_dev_package,
    $::jenkins::params::libffi_dev_package, # xattr's cffi dependency
    $::jenkins::params::pandoc_package, #for docs, markdown->docbook, bug 924507
    $::jenkins::params::pkgconfig_package, # for spidermonkey, used by ceilometer
    $::jenkins::params::python_libvirt_package,
    $::jenkins::params::python_lxml_package, # for validating openstack manuals
    $::jenkins::params::python_magic_package, # for pushing files to swift
    $::jenkins::params::python_requests_package, # for pushing files to swift
    $::jenkins::params::python_zmq_package, # zeromq unittests (not pip installable)
    $::jenkins::params::rubygems_package,
    $::jenkins::params::sbcl_package, # cl-openstack-client testing
    $::jenkins::params::sqlite_package,
    $::jenkins::params::unzip_package,
    $::jenkins::params::zip_package,
    $::jenkins::params::xslt_package, # for building openstack docs
    $::jenkins::params::xvfb_package, # for selenium tests
    $::jenkins::params::php5_cli_package, # for community portal build
  ]

  if ($bare == false) {
    $packages = [$common_packages, $standard_packages]
  } else {
    $packages = $common_packages
  }

  file { '/etc/apt/sources.list.d/cloudarchive.list':
    ensure => absent,
  }

  package { $packages:
    ensure => present,
    before => Anchor['jenkins::slave::update-java-alternatives']
  }

  case $::osfamily {
    'RedHat': {

      exec { 'yum Group Install':
        unless  => '/usr/bin/yum grouplist "Development tools" | /bin/grep "^Installed Groups"',
        command => '/usr/bin/yum -y groupinstall "Development tools"',
      }

      if ($::operatingsystem == 'Fedora') {
          package { $::jenkins::params::zookeeper_package:
              ensure => present,
          }
          # Fedora needs community-mysql package for mysql_config
          # command used in some gate-{project}-python27
          # jobs in Jenkins
          package { $::jenkins::params::mysql_package:
              ensure => present,
          }
      } else {
          exec { 'update-java-alternatives':
            unless   => '/bin/ls -l /etc/alternatives/java | /bin/grep 1.7.0-openjdk',
            command  => '/usr/sbin/alternatives --set java /usr/lib/jvm/jre-1.7.0-openjdk.x86_64/bin/java && /usr/sbin/alternatives --set javac /usr/lib/jvm/java-1.7.0-openjdk.x86_64/bin/javac',
            require  => Anchor['jenkins::slave::update-java-alternatives']
          }
      }
    }
    'Debian': {

      # install build-essential package group
      package { 'build-essential':
        ensure => present,
      }

      package { $::jenkins::params::maven_package:
        ensure  => present,
        require => Package[$::jenkins::params::jdk_package],
      }

      package { $::jenkins::params::ruby1_9_1_package:
        ensure => present,
      }

      package { $::jenkins::params::ruby1_9_1_dev_package:
        ensure => present,
      }

      package { $::jenkins::params::ruby_bundler_package:
        ensure => present,
      }

      package { 'openjdk-6-jre-headless':
        ensure  => purged,
        require => Package[$::jenkins::params::jdk_package],
      }

      # For [tooz, taskflow, nova] using zookeeper in unit tests
      package { $::jenkins::params::zookeeper_package:
        ensure => present,
      }

      # For openstackid using php5-mcrypt for distro build
      package { $::jenkins::params::php5_mcrypt_package:
        ensure => present,
      }

      exec { 'update-java-alternatives':
        unless   => '/bin/ls -l /etc/alternatives/java | /bin/grep java-7-openjdk-amd64',
        command  => '/usr/sbin/update-java-alternatives --set java-1.7.0-openjdk-amd64',
        require  => Anchor['jenkins::slave::update-java-alternatives']
      }

    }
    default: {
      fail("Unsupported osfamily: ${::osfamily} The 'jenkins' module only supports osfamily Debian or RedHat (slaves only).")
    }
  }

  if ($bare == false) {
    # pin to a release of rake which works with ruby 1.8.x
    # before PSH tries to pull in a newer one which isn't
    package { 'rake':
      ensure   => '10.1.1',
      provider => gem,
      before   => Package['puppetlabs_spec_helper'],
      require  => Package['rubygems'],
    }

    $gem_packages = [
      'bundler',
      'puppet-lint',
      'puppetlabs_spec_helper',
    ]

    package { $gem_packages:
      ensure   => latest,
      provider => gem,
      require  => Package['rubygems'],
    }
  }

  if $python3 {
    if ($::lsbdistcodename == 'precise') {
      apt::ppa { 'ppa:zulcss/py3k':
        before => Class[pip::python3],
      }
    }
    include pip::python3
    # Temporarily handle tox separately so we can pin it
    package { 'tox':
      ensure   => '1.6.1',
      provider => pip3,
      require  => Class['pip::python3'],
    }
  } else {
    # Temporarily handle tox separately so we can pin it
    package { 'tox':
      ensure   => '1.6.1',
      provider => pip,
      require  => Class['pip'],
    }
  }

  package { 'git-review':
    ensure   => '1.17',
    provider => pip,
    require  => Class[pip],
  }

  file { '/etc/profile.d/rubygems.sh':
    ensure => present,
    owner  => 'root',
    group  => 'root',
    mode   => '0644',
    source => 'puppet:///modules/jenkins/rubygems.sh',
  }

  file { '/usr/local/bin/gcc':
    ensure  => link,
    target  => '/usr/bin/ccache',
    require => Package['ccache'],
  }

  file { '/usr/local/bin/g++':
    ensure  => link,
    target  => '/usr/bin/ccache',
    require => Package['ccache'],
  }

  file { '/usr/local/bin/cc':
    ensure  => link,
    target  => '/usr/bin/ccache',
    require => Package['ccache'],
  }

  file { '/usr/local/bin/c++':
    ensure  => link,
    target  => '/usr/bin/ccache',
    require => Package['ccache'],
  }

  if ($bare == false) {
    if ($::operatingsystem == 'Fedora') and ($::operatingsystemrelease >= 19) {
      class {'mysql::server':
        config_hash  =>  {
          'root_password'  => 'insecure_slave',
          'default_engine' => 'MyISAM',
          'bind_address'   => '127.0.0.1',
        },
        package_name => 'community-mysql-server',
      }
    } else {
      class {'mysql::server':
        config_hash =>  {
          'root_password'  => 'insecure_slave',
          'default_engine' => 'MyISAM',
          'bind_address'   => '127.0.0.1',
        }
      }
    }

    include mysql::server::account_security

    mysql::db { 'openstack_citest':
      user     => 'openstack_citest',
      password => 'openstack_citest',
      host     => 'localhost',
      grant    => ['all'],
      require  => [
        Class['mysql::server'],
        Class['mysql::server::account_security'],
      ],
    }

    # mysql::db is too dumb to realize that the same user can have
    # access to multiple databases and will fail if you try creating
    # a second DB with the same user. Create the DB directly as mysql::db
    # above is creating the user for us.
    database { 'openstack_baremetal_citest':
      ensure   => present,
      charset  => 'utf8',
      provider => 'mysql',
      require  => [
        Class['mysql::server'],
        Class['mysql::server::account_security'],
      ],
    }

    database_grant { 'openstack_citest@localhost/openstack_baremetal_citest':
      privileges => ['all'],
      provider   => 'mysql',
      require    => Database_user['openstack_citest@localhost'],
    }

    if ($all_mysql_privs == true) {
      database_grant { 'openstack_citest@localhost':
        privileges => ['all'],
        provider   => 'mysql',
        require    => Database_user['openstack_citest@localhost'],
      }
    }

    # The puppetlabs postgres module does not manage the postgres user
    # and group for us. Create them here to ensure concat can create
    # dirs and files owned by this user and group.
    user { 'postgres':
      ensure  => present,
      gid     => 'postgres',
      system  => true,
      require => Group['postgres'],
    }

    group { 'postgres':
      ensure => present,
      system => true,
    }

    class { 'postgresql::server':
      postgres_password => 'insecure_slave',
      manage_firewall   => false,
      # The puppetlabs postgres module incorrectly quotes ip addresses
      # in the postgres server config. Use localhost instead.
      listen_addresses  => ['localhost'],
      require           => [
        User['postgres'],
        Class['postgresql::params'],
      ],
    }

    class { 'postgresql::lib::devel':
      require => Class['postgresql::params'],
    }

    # Create DB user and explicitly make it non superuser
    # that can create databases.
    postgresql::server::role { 'openstack_citest':
      password_hash => postgresql_password('openstack_citest', 'openstack_citest'),
      createdb      => true,
      superuser     => false,
      require       => Class['postgresql::server'],
    }

    postgresql::server::db { 'openstack_citest':
      user     => 'openstack_citest',
      password => postgresql_password('openstack_citest', 'openstack_citest'),
      grant    => 'all',
      require  => [
        Class['postgresql::server'],
        Postgresql::Server::Role['openstack_citest'],
      ],
    }

    # Alter the new database giving the test DB user ownership of the DB.
    # This is necessary to make the nova unittests run properly.
    postgresql_psql { 'ALTER DATABASE openstack_citest OWNER TO openstack_citest':
      db          => 'postgres',
      refreshonly => true,
      subscribe   => Postgresql::Server::Db['openstack_citest'],
    }

    postgresql::server::db { 'openstack_baremetal_citest':
      user     => 'openstack_citest',
      password => postgresql_password('openstack_citest', 'openstack_citest'),
      grant    => 'all',
      require  => [
        Class['postgresql::server'],
        Postgresql::Server::Role['openstack_citest'],
      ],
    }

    # Alter the new database giving the test DB user ownership of the DB.
    # This is necessary to make the nova unittests run properly.
    postgresql_psql { 'ALTER DATABASE openstack_baremetal_citest OWNER TO
                       openstack_citest':
      db          => 'postgres',
      refreshonly => true,
      subscribe   => Postgresql::Server::Db['openstack_baremetal_citest'],
    }
  }

  file { '/usr/local/jenkins':
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  file { '/usr/local/jenkins/slave_scripts':
    ensure  => directory,
    owner   => 'root',
    group   => 'root',
    mode    => '0755',
    recurse => true,
    purge   => true,
    force   => true,
    require => File['/usr/local/jenkins'],
    source  => 'puppet:///modules/jenkins/slave_scripts',
  }

  if ($sudo == true) {
    file { '/etc/sudoers.d/jenkins-sudo':
      ensure => present,
      source => 'puppet:///modules/jenkins/jenkins-sudo.sudo',
      owner  => 'root',
      group  => 'root',
      mode   => '0440',
    }
  }

  file { '/etc/sudoers.d/jenkins-sudo-grep':
    ensure => present,
    source => 'puppet:///modules/jenkins/jenkins-sudo-grep.sudo',
    owner  => 'root',
    group  => 'root',
    mode   => '0440',
  }

  vcsrepo { '/opt/requirements':
    ensure   => latest,
    provider => git,
    revision => 'master',
    source   => 'https://git.openstack.org/openstack/requirements',
  }

  # Temporary for debugging glance launch problem
  # https://lists.launchpad.net/openstack/msg13381.html
  # NOTE(dprince): ubuntu only as RHEL6 doesn't have sysctl.d yet
  if ($::osfamily == 'Debian') {

    file { '/etc/sysctl.d/10-ptrace.conf':
      ensure => present,
      source => 'puppet:///modules/jenkins/10-ptrace.conf',
      owner  => 'root',
      group  => 'root',
      mode   => '0444',
    }

    exec { 'ptrace sysctl':
      subscribe   => File['/etc/sysctl.d/10-ptrace.conf'],
      refreshonly => true,
      command     => '/sbin/sysctl -p /etc/sysctl.d/10-ptrace.conf',
    }

    if $include_pypy {
      apt::ppa { 'ppa:pypy/ppa': }
      package { 'pypy':
        ensure  => present,
        require => Apt::Ppa['ppa:pypy/ppa']
      }
      package { 'pypy-dev':
        ensure  => present,
        require => Apt::Ppa['ppa:pypy/ppa']
      }
    }
  }
}
