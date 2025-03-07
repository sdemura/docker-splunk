#!/bin/bash
# Copyright 2018-2021 Splunk
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e

# Generate UTF-8 char map and locale
# Reinstalling local English def for now, removed in minimal image: https://bugzilla.redhat.com/show_bug.cgi?id=1665251
microdnf -y --nodocs install glibc-langpack-en

# Currently there is no access to the UTF-8 char map. The following command is commented out until
# the base container can generate the locale.
# localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
# We get around the gen above by forcing the language install, and then pointing to it.
export LANG=en_US.utf8

# Install utility packages
microdnf -y --nodocs install wget sudo shadow-utils procps tar make gcc \
                             openssl-devel bzip2-devel libffi-devel findutils
# Patch security updates
microdnf -y --nodocs update gnutls kernel-headers librepo libnghttp2 nettle \
                            libpwquality libxml2 systemd-libs glib2 lz4-libs \
                            rpm rpm-libs sqlite-libs cyrus-sasl-lib vim expat \
                            openssl-libs xz-libs zlib

# Reinstall tzdata (originally stripped from minimal image): https://bugzilla.redhat.com/show_bug.cgi?id=1903219
microdnf -y --nodocs reinstall tzdata || microdnf -y --nodocs update tzdata

# Install Python and necessary packages
PY_SHORT=${PYTHON_VERSION%.*}
wget -O /tmp/python.tgz https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz
wget -O /tmp/Python-gpg-sig-${PYTHON_VERSION}.tgz.asc https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz.asc
gpg --keyserver keys.openpgp.org --recv-keys $PYTHON_GPG_KEY_ID \
    || gpg --keyserver pool.sks-keyservers.net --recv-keys $PYTHON_GPG_KEY_ID \
    || gpg --keyserver pgp.mit.edu --recv-keys $PYTHON_GPG_KEY_ID \
    || gpg --keyserver keyserver.pgp.com --recv-keys $PYTHON_GPG_KEY_ID
gpg --verify /tmp/Python-gpg-sig-${PYTHON_VERSION}.tgz.asc /tmp/python.tgz
rm /tmp/Python-gpg-sig-${PYTHON_VERSION}.tgz.asc
mkdir -p /tmp/pyinstall
tar -xzC /tmp/pyinstall/ --strip-components=1 -f /tmp/python.tgz
rm /tmp/python.tgz
cd /tmp/pyinstall
./configure --enable-optimizations --prefix=/usr --with-ensurepip=install
make altinstall LDFLAGS="-Wl,--strip-all"
rm -rf /tmp/pyinstall
ln -sf /usr/bin/python${PY_SHORT} /usr/bin/python
ln -sf /usr/bin/pip${PY_SHORT} /usr/bin/pip

# Install splunk-ansible dependencies
cd /
pip -q --no-cache-dir install six wheel requests cryptography==3.3.2 ansible==3.4.0 urllib3==1.26.5 jmespath --upgrade

# Remove tests packaged in python libs
find /usr/lib/ -depth \( -type d -a -not -wholename '*/ansible/plugins/test' -a \( -name test -o -name tests -o -name idle_test \) \) -exec rm -rf '{}' \;
find /usr/lib/ -depth \( -type f -a -name '*.pyc' -o -name '*.pyo' -o -name '*.a' \) -exec rm -rf '{}' \;
find /usr/lib/ -depth \( -type f -a -name 'wininst-*.exe' \) -exec rm -rf '{}' \;
ldconfig

# Cleanup
microdnf remove -y make gcc openssl-devel bzip2-devel libffi-devel findutils cpp binutils \
                   glibc-devel keyutils-libs-devel krb5-devel libcom_err-devel libselinux-devel \
                   libsepol-devel libverto-devel libxcrypt-devel pcre2-devel zlib-devel
microdnf clean all

# Install scloud
wget -O /usr/bin/scloud.tar.gz ${SCLOUD_URL}
tar -xf /usr/bin/scloud.tar.gz -C /usr/bin/
rm /usr/bin/scloud.tar.gz

# Install busybox direct from the multiarch since EPEL isn't available yet for redhat8
wget -O /bin/busybox https://busybox.net/downloads/binaries/1.28.1-defconfig-multiarch/busybox-`arch`
chmod +x /bin/busybox

# Enable busybox symlinks
cd /bin
BBOX_LINKS=( clear find diff hostname killall netstat nslookup ping ping6 readline route syslogd tail traceroute vi )
for item in "${BBOX_LINKS[@]}"
do
  ln -s busybox $item || true
done
chmod u+s /bin/ping
groupadd sudo

echo "
## Allows people in group sudo to run all commands
%sudo  ALL=(ALL)       ALL" >> /etc/sudoers

# Clean
microdnf clean all
rm -rf /install.sh /anaconda-post.log /var/log/anaconda/*
