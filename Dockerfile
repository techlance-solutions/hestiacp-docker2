FROM debian:bookworm

# Update package repositories and upgrade existing packages
RUN apt-get update && apt-get upgrade -y

# Install necessary packages
RUN apt-get install -y curl gnupg2 ca-certificates

# Import Hestia Control Panel GPG key
RUN curl https://apt.hestiacp.com/keys/hestia.gpg.key | gpg --dearmor > /usr/share/keyrings/hestia-archive-keyring.gpg

# Add Hestia Control Panel repository
RUN echo 'deb [signed-by=/usr/share/keyrings/hestia-archive-keyring.gpg] http://apt.hestiacp.com bookworm main' > /etc/apt/sources.list.d/hestia.list

# Update package repositories
RUN apt-get update

# Install Hestia Control Panel
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y hestia

# Clean up
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Expose Hestia Control Panel ports
EXPOSE 80 443 8083

# Start Hestia Control Panel
CMD ["hestia", "start"]

# Adjust permissions on executables
RUN chmod +x /etc/my_init.d/*
RUN chmod +x /usr/local/hestia/bin/*

# Add root user in incron
RUN echo 'root' >> /etc/incron.allow

# Change incron permissions
RUN chmod 600 /var/spool/incron/root

# Change cron permissions
RUN chown root:crontab /var/spool/cron/crontabs/root
RUN chmod 600 /var/spool/cron/crontabs/root

# Add "-f" to force cron execution
RUN sed -Ei "s|/usr/sbin/logrotate /etc/logrotate.conf|/usr/sbin/logrotate -f /etc/logrotate.conf|" /etc/cron.daily/logrotate

# Disable sudo message
RUN sed -Ei "s|(Defaults\s*secure_path.*)|\1\nDefaults        lecture=\"never\"|" /etc/sudoers

# Avoid errors on fail2ban startup due to missing logs
RUN touch /var/log/dovecot.log
RUN touch /var/log/roundcube/errors.log
RUN chown www-data:www-data /var/log/roundcube/errors.log
RUN touch /var/log/nginx/domains/dummy.error.log
RUN chown www-data:adm /var/log/nginx/domains/dummy.error.log
RUN touch /var/log/nginx/domains/dummy.access.log
RUN chown www-data:adm /var/log/nginx/domains/dummy.access.log

# Remove existing socks to avoid service startup issues
RUN rm -f /var/run/fail2ban/*

# Fix clamav run directory permissions
RUN chown clamav:clamav -R /var/run/clamav

# Add dir for mariadb-bridge socket
RUN mkdir -p /var/run/mysqld

# Adjust permissions for PHP to access directories on volumes
RUN sed -Ei "s|(^php_admin_value\[open_basedir\].*)|\1:/conf/usr/local/hestia/:/conf/etc/ssh/|" /usr/local/hestia/php/etc/php-fpm.conf

# Change the path of "fastcgi_cache_pool.conf" to a directory on volume
RUN find /usr/local/hestia -type f -print0 | xargs -0 sed -i "s|/etc/nginx/conf.d/fastcgi_cache_pool.conf|/etc/nginx/conf.d/pre-domains/fastcgi_cache_pool.conf|g"

# Remove "/conf" from key path to prevent error on comparison
RUN sed -Ei "s|(^maybe_key_path=\".*)|\1\nmaybe_key_path=\"\$(echo \"\$maybe_key_path\" | sed \"s/^\/conf//\")\"|" /usr/local/hestia/bin/v-check-api-key

# Change path to domains dir in Hestia templates
RUN sed -Ei "s|/etc/nginx/conf.d|/etc/nginx/conf.d/pre-domains|g" /usr/local/hestia/data/templates/web/nginx/caching.sh
RUN sed -i "s|phppgadmin.inc|general/phppgadmin.inc|g" /usr/local/hestia/data/templates/web/nginx/php-fpm/*tpl
RUN sed -i "s|phpmyadmin.inc|general/phpmyadmin.inc|g" /usr/local/hestia/data/templates/web/nginx/php-fpm/*tpl

# Fix path to rrd to prevent error on comparison in Hestia Web
RUN sed -i "s|\$dir_name != \$_SERVER\[\"DOCUMENT_ROOT\"\].'/rrd'|\!in_array(\$dir_name, [ \$_SERVER[\"DOCUMENT_ROOT\"].'/rrd', '/conf'.\$_SERVER\[\"DOCUMENT_ROOT\"\].'/rrd'])|" /usr/local/hestia/web/list/rrd/image.php

# Remove mysql from services list in Hestia Web
RUN sed -Ei "s|(if \(isset\(\$data\['mysql'\]\)\) unset\(\$data\['mysql'\]\);)|\1\nif \(isset\(\$data\['mariadb'\]\)\) unset\(\$data\['mariadb'\]\);|" /usr/local/hestia/web/list/server/index.php

# Create necessary directories for NGINX
RUN mkdir -p /etc/nginx/conf.d/general
RUN mkdir -p /etc/nginx/conf.d/pre-domains
RUN mkdir -p /etc/nginx/conf.d/streams

# Change includes from nginx.conf
RUN sed -i "s|include /etc/nginx/conf.d/\*.conf;|include /etc/nginx/conf.d/general/*.conf;\n    include /etc/nginx/conf.d/pre-domains/*.conf;|" /etc/nginx/nginx.conf

# Add stream in the end of nginx.conf
RUN echo -e "\nstream {\n    log_format mysql '\$remote_addr [\$time_local] \$protocol \$status \$bytes_received '\n                     '\$bytes_sent \$upstream_addr \$upstream_connect_time '\n                     '\$upstream_first_byte_time \$upstream_session_time \$session_time';\n    include /etc/nginx/conf.d/streams/*.conf;\n}\n" >> /etc/nginx/nginx.conf

# Move configurations file to "general" directory
RUN mv /etc/nginx/conf.d/172.*.conf /etc/nginx/conf.d/domains

# Make specified files or directories persistent
RUN mkdir -p /conf-start && \
    bash /usr/local/hestia/install/make-persistent.sh /etc/bind/named.conf yes && \
    bash /usr/local/hestia/install/make-persistent.sh /etc/bind/named.conf.options yes && \
    bash /usr/local/hestia/install/make-persistent.sh /etc/exim4/domains && \
    bash /usr/local/hestia/install/make-persistent.sh /etc/fail2ban/jail.local yes && \
    bash /usr/local/hestia/install/make-persistent.sh /etc/nginx/conf.d/domains && \
    bash /usr/local/hestia/install/make-persistent.sh /etc/nginx/conf.d/pre-domains && \
    for php_path in /etc/php/*; do \
      php_version=\"\$(basename -- \"\$php_path\")\"; \
      bash /usr/local/hestia/install/make-persistent.sh /etc/php/\${php_version}/fpm/pool.d; \
    done && \
    bash /usr/local/hestia/install/make-persistent.sh /etc/phpmyadmin/conf.d && \
    bash /usr/local/hestia/install/make-persistent.sh /etc/roundcube/config.inc.php yes && \
    bash /usr/local/hestia/install/make-persistent.sh /etc/ssh && \
    bash /usr/local/hestia/install/make-persistent.sh /etc/ssl && \
    bash /usr/local/hestia/install/make-persistent.sh /root && \
    bash /usr/local/hestia/install/make-persistent.sh /usr/local/hestia/data && \
    bash /usr/local/hestia/install/make-persistent.sh /usr/local/hestia/conf && \
    bash /usr/local/hestia/install/make-persistent.sh /usr/local/hestia/ssl && \
    bash /usr/local/hestia/install/make-persistent.sh /usr/local/hestia/web/rrd && \
    bash /usr/local/hestia/install/make-persistent.sh /var/lib/fail2ban && \
    bash /usr/local/hestia/install/make-persistent.sh /var/spool/cron/crontabs && \
    mv /home /home-start

# Set environment variables
ENV MAIL_ADMIN=${MAIL_ADMIN:-} \
    AUTOSTART_DISABLED=${AUTOSTART_DISABLED:-}

# Set the working directory to Hestia Control Panel
WORKDIR /usr/local/hestia

# Start Hestia Control Panel
CMD ["bash", "-c", "/usr/local/hestia/bin/v-start-service"]
