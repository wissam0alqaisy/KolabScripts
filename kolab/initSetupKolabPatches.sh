#!/bin/bash

SCRIPTSPATH=`dirname ${BASH_SOURCE[0]}`
source $SCRIPTSPATH/lib.sh

DetermineOS
InstallWgetAndPatch
DeterminePythonPath

#####################################################################################
# apply a couple of patches, see related kolab bugzilla number in filename, eg. https://issues.kolab.org/show_bug.cgi?id=2018
#####################################################################################

if [ -z $APPLYPATCHES ]
then
  APPLYPATCHES=1
fi

if [ $APPLYPATCHES -eq 1 ]
then
echo "applying patch for Roundcube Kolab plugin for storage in MariaDB"
patch -p1 -i `pwd`/patches/roundcubeStorageMariadbBug4883.patch -d /usr/share/roundcubemail || exit -1

# TODO: see if we still need these patches
#echo "applying patch for waiting after restart of dirsrv (necessary on Debian)"
#patch -p1 -i `pwd`/patches/setupKolabSleepDirSrv.patch -d $pythonDistPackages || exit -1

# https://github.com/TBits/KolabScripts/issues/76
echo "fix problem on LXC containers with access to TCP keepalive settings"
patch -p1 -i `pwd`/patches/fixPykolabIMAPKeepAlive.patch -d $pythonDistPackages || exit -1

echo "applying patch to Roundcube for the compose to show loading message"
# patch -p1 -i `pwd`/patches/roundcubeComposeLoading.patch -d /usr/share/roundcubemail || exit -1
# app.js has been compressed
sed -i "s#this.open_compose_step=function(p){var url#this.open_compose_step=function(p){this.set_busy(true, 'loading');var url#g" /usr/share/roundcubemail/public_html/assets/program/js/app.js

echo "apply patch for Etc timezone in roundcube plugins/calendar"
patch -p1 -i `pwd`/patches/roundcube_calendar_etc_timezone_T2666.patch -d /usr/share/roundcubemail || exit -1
# another way to fix it, in the jstz library (see also https://bitbucket.org/pellepim/jstimezonedetect/issues/168/ignore-timezones-like-etc-gmt-1)
sed -i 's#"UTC"===a)#"UTC"===a)\&\&a.indexOf("Etc")<0#' /usr/share/roundcubemail/public_html/assets/program/js/jstz.min.js

echo "do not rename existing mailboxes"
patch -p1 --fuzz=0 -i `pwd`/patches/pykolab_do_not_rename_existing_mailbox_T3315.patch -d $pythonDistPackages || exit -1

echo "fix for php-net-LDAP3"
# see https://git.kolab.org/rPNL56210fdaec70bc1f8f7455a75a6cd34e3a2f7e6d
patch -p1 --fuzz=0 -i `pwd`/patches/fixphpnetldap_url.patch -d / || exit -1
# and https://cgit.kolab.org/php-Net-LDAP3/commit/?id=858fd6076366626b6ff45e8bdf57dedeb210ce34
patch -p1 --fuzz=0 -i `pwd`/patches/fixphpnetldap_url2.patch -d / || exit -1

fi

if [[ $OS == CentOS* || $OS == Fedora* ]]
then
  # there is an issue with lxc 2.0.8 and CentOS, with PrivateDevices
  # https://github.com/lxc/lxc/issues/1623
  # journalctl -xe shows:
  # -- Unit amavisd.service has begun starting up.
  # systemd[3849]: Failed at step NAMESPACE spawning /usr/sbin/amavisd: Invalid argument
  # -- Subject: Process /usr/sbin/amavisd could not be executed
  sed -i 's/PrivateDevices=true/#PrivateDevices=true/g' /usr/lib/systemd/system/amavisd.service
  systemctl daemon-reload
  systemctl restart amavisd.service
fi

if [[ $OS == Debian* ]]
then
      # workaround for bug 2050, https://issues.kolab.org/show_bug.cgi?id=2050
      echo "export ZEND_DONT_UNLOAD_MODULES=1" >> /etc/apache2/envvars

      # TODO on Debian, we need to install the rewrite for the csrf token
      newConfigLines="\tRewriteEngine On\n \
\tRewriteRule ^/roundcubemail/[a-f0-9]{16}/(.*) /roundcubemail/\$1 [PT,L]\n \
\tRewriteRule ^/webmail/[a-f0-9]{16}/(.*) /webmail/\$1 [PT,L]\n \
\tRedirectMatch ^/$ /roundcubemail/\n"

#      sed -i -e "s~</VirtualHost>~$newConfigLines</VirtualHost>~" /etc/apache2/sites-enabled/000-default
fi
