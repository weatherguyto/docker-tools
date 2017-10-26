#! /bin/bash -e
[ -z "$LOCALHOSTNAME" ] && LOCALHOSTNAME=$HOSTNAME
MYTHHOME=/home/mythtv
OSTYPE=`grep ^ID= /etc/os-release|cut -f 2 -d=`

localedef -i $(cut -d. -f1 <<< $LANGUAGE) -f $(cut -d. -f2 <<< $LANGUAGE) $LANG

if [ "$OSTYPE" == "opensuse" ]; then
  ln -fns /usr/share/zoneinfo/$TZ /etc/localtime
  CONF_DIR=/etc/apache2/conf.d
  DOCUMENT_ROOT=/srv/www/htdocs/mythweb
elif [ "$OSTYPE" == "ubuntu" ]; then
  if [[ $(cat /etc/timezone) != $TZ ]]; then
    echo $TZ > /etc/timezone
    sed -i -e "s#;date.timezone.*#date.timezone = ${TZ}#g" /etc/php/7.0/apache2/php.ini
    sed -i -e "s#;date.timezone.*#date.timezone = ${TZ}#g" /etc/php/7.0/cli/php.ini
    dpkg-reconfigure -f noninteractive tzdata
  fi
  CONF_DIR=/etc/apache2/sites-available
  DOCUMENT_ROOT=/var/www/html/mythweb
fi

if [ -e /run/secrets/mythtv-db-password ]; then
  DBPASSWORD=$(cat /run/secrets/mythtv-db-password)
else
  DBPASSWORD=$(xml_grep --text_only Password /etc/mythtv/config.xml)
fi

if [ -e /run/secrets/mythtv-user-password ]; then
  usermod -p $(cat /run/secrets/mythtv-user-password) mythtv
fi

if [ ! -f $MYTHHOME/icons/bomb.png ]; then
  mkdir -p $MYTHHOME/icons
  cp /root/bomb.png $MYTHHOME/icons/
  chmod 755 $MYTHHOME/icons/bomb.png
fi

if [ ! -f $MYTHHOME/.Xauthority ]; then
  touch $MYTHHOME/.Xauthority && chown mythtv $MYTHHOME/.Xauthority
fi

cp /root/config.xml /etc/mythtv/
chmod 600 /etc/mythtv/config.xml && chown mythtv /etc/mythtv/config.xml

for file in $CONF_DIR/mythweb.conf $CONF_DIR/mythweb-settings.conf \
    /etc/mythtv/config.xml; do
  sed -i -e "s+{{ APACHE_LOG_DIR }}+$APACHE_LOG_DIR+" \
      -e "s/{{ DBNAME }}/$DBNAME/" \
      -e "s/{{ DBPASSWORD }}/$DBPASSWORD/" \
      -e "s/{{ DBSERVER }}/$DBSERVER/" \
      -e "s+{{ DOCUMENT_ROOT }}+$DOCUMENT_ROOT+" \
      -e "s/{{ LOCALHOSTNAME }}/$LOCALHOSTNAME/" $file
done

if [ ! -f /etc/ssh/.keys_generated ] && \
     ! grep -q '^[[:space:]]*HostKey[[:space:]]' /etc/ssh/sshd_config; then
  rm /etc/ssh/ssh_host*
  ssh-keygen -A
  touch /etc/ssh/.keys_generated
fi
mkdir -p /var/run/sshd

for mod in deflate filter headers rewrite; do a2enmod $mod; done
a2ensite mythweb mythweb-settings
apache2ctl start

for retry in $(seq 1 10); do
  while killall -0 mythtv-setup; do sleep 5; done
  su mythtv -c /usr/bin/mythbackend || echo Unexpected exit retry=$retry
  sleep 60
done
