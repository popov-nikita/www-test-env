FROM wordpress:5.4-php7.4-apache

MAINTAINER Nikita Popov <npv1310_at_gmail.com>

ARG MODSECURITY_TARGZ
ARG APACHE_NOTIFIER_TARGZ
ARG DOCKER_RULES_DIR
ARG DOCKER_DOCROOT
ARG BUILD_DIR
ARG APACHE_LOG_DIR

# getservbyname & friends libc functions depend on `netbase` package. Caused some php tests fail
RUN { \
        set -u -e -x; \
        apt-get update; \
        apt-get install --yes --no-install-recommends \
                                                      netbase \
                                                      libapr1-dev \
                                                      libaprutil1-dev \
                                                      apache2-dev \
                                                      libpcre3 \
                                                      libpcre3-dev \
                                                      libssl1.1 \
                                                      libssl-dev \
                                                      libcurl4 \
                                                      libcurl4-openssl-dev \
                                                      libxml2 \
                                                      libxml2-dev \
                                                      liblua5.3-0 \
                                                      liblua5.3-dev \
                                                      libyajl2 \
                                                      libyajl-dev \
                                                      libfuzzy2 \
                                                      libfuzzy-dev \
        ; \
        rm -rf /var/lib/apt/lists/*; \
    }

RUN mkdir ${BUILD_DIR}
COPY ${MODSECURITY_TARGZ} ${BUILD_DIR}
COPY ${APACHE_NOTIFIER_TARGZ} ${BUILD_DIR}

RUN { \
        set -u -e -x; \
        cd ${BUILD_DIR}; \
        tar -x -f ${MODSECURITY_TARGZ}; \
        cd ${MODSECURITY_TARGZ%.tar.gz}; \
        ./configure --prefix=/usr/modsecurity \
                    --enable-apache2-module \
                    --enable-extentions; \
        nr_cpus=$(grep -c '^processor' /proc/cpuinfo); \
        if test $nr_cpus -gt 1; then \
            nr_threads=$(($nr_cpus >> 1)); \
        else \
            nr_threads=$nr_cpus; \
        fi; \
        make -j$nr_threads; \
        make install; \
    }

RUN { \
        set -u -e -x; \
        mod_sec_path=$(find /usr/ -type f -name mod_security2.so -print -quit); \
        test -f "$mod_sec_path"; \
        mods_avail_dir=/etc/apache2/mods-available; \
        test \( -d "$mods_avail_dir" \) -a \( -w "$mods_avail_dir" \); \
        echo "LoadModule security2_module $mod_sec_path" > ${mods_avail_dir}/mod_security2.load; \
        a2enmod unique_id; \
        a2enmod mod_security2; \
        conf_avail_dir=/etc/apache2/conf-available; \
        test \( -d "$conf_avail_dir" \) -a \( -w "$conf_avail_dir" \); \
        echo "<IfModule security2_module>" > ${conf_avail_dir}/mod_security2-rules.conf; \
        echo "    SecAuditEngine \"RelevantOnly\"" >> ${conf_avail_dir}/mod_security2-rules.conf; \
        echo "    SecAuditLog \"${APACHE_LOG_DIR}/modsec_audit.log\"" >> ${conf_avail_dir}/mod_security2-rules.conf; \
        echo "    # We use 'I' here so multipart/form-data requests bodies are truncated" >> ${conf_avail_dir}/mod_security2-rules.conf; \
        echo "    SecAuditLogParts \"ABFIZ\"" >> ${conf_avail_dir}/mod_security2-rules.conf; \
        echo "    SecAuditLogType \"Serial\"" >> ${conf_avail_dir}/mod_security2-rules.conf; \
        echo '    SecAuditLogRelevantStatus "^.*$"' >> ${conf_avail_dir}/mod_security2-rules.conf; \
        echo "    SecAuditLogFormat \"Native\"" >> ${conf_avail_dir}/mod_security2-rules.conf; \
        echo "" >> ${conf_avail_dir}/mod_security2-rules.conf; \
        echo "    SecDebugLogLevel \"9\"" >> ${conf_avail_dir}/mod_security2-rules.conf; \
        echo "    SecDebugLog \"${APACHE_LOG_DIR}/modsec_debug.log\"" >> ${conf_avail_dir}/mod_security2-rules.conf; \
        echo "" >> ${conf_avail_dir}/mod_security2-rules.conf; \
        echo "    SecRuleEngine \"On\"" >> ${conf_avail_dir}/mod_security2-rules.conf; \
        echo "    # This is required in order to fully process POST payload" >> ${conf_avail_dir}/mod_security2-rules.conf; \
        echo "    SecRequestBodyAccess \"On\"" >> ${conf_avail_dir}/mod_security2-rules.conf; \
        echo "    # Avoid creation of extra temporary files" >> ${conf_avail_dir}/mod_security2-rules.conf; \
        echo "    SecTmpSaveUploadedFiles \"Off\"" >> ${conf_avail_dir}/mod_security2-rules.conf; \
        echo "    SecUploadKeepFiles \"Off\"" >> ${conf_avail_dir}/mod_security2-rules.conf; \
        echo "    SecResponseBodyLimitAction \"ProcessPartial\"" >> ${conf_avail_dir}/mod_security2-rules.conf; \
        echo "    SecPcreMatchLimit \"1150500\"" >> ${conf_avail_dir}/mod_security2-rules.conf; \
        echo "    SecPcreMatchLimitRecursion \"1150500\"" >> ${conf_avail_dir}/mod_security2-rules.conf; \
        echo "" >> ${conf_avail_dir}/mod_security2-rules.conf; \
        echo "    IncludeOptional ${DOCKER_RULES_DIR}/*.conf" >> ${conf_avail_dir}/mod_security2-rules.conf; \
        echo "</IfModule>" >> ${conf_avail_dir}/mod_security2-rules.conf; \
        a2enconf mod_security2-rules; \
    }

RUN { \
        set -u -e -x; \
        cd ${BUILD_DIR}; \
        tar -x -f ${APACHE_NOTIFIER_TARGZ}; \
        cd ${APACHE_NOTIFIER_TARGZ%.tar.gz}; \
        nr_cpus=$(grep -c '^processor' /proc/cpuinfo); \
        if test $nr_cpus -gt 1; then \
            nr_threads=$(($nr_cpus >> 1)); \
        else \
            nr_threads=$nr_cpus; \
        fi; \
        make -j$nr_threads clean all; \
        cp -f apache-notifier /usr/local/bin; \
    }

# We need to disable apache2's foreground operation
RUN { \
        set -u -e -x; \
        wrapper_script='/usr/local/bin/apache2-foreground'; \
        test -f "$wrapper_script"; \
        sed -i -e '/^[[:space:]]*exec/ s@\-DFOREGROUND@@g' "$wrapper_script"; \
    }

# Since we are making apache2 daemonize (in which it redirects its stdout/stderr to /dev/null)
# we need to fix its logs. Use standard descriptors of PID #1 (INIT) process
RUN { \
        set -u -e -x; \
        umask 0000; \
        mkdir -p "$APACHE_LOG_DIR"; \
        cd "$APACHE_LOG_DIR"; \
        echo > access.log; \
        echo > error.log; \
        echo > other_vhosts_access.log; \
        echo > modsec_audit.log; \
        echo > modsec_debug.log; \
        chown -R --no-dereference www-data:www-data .; \
    }

# Create custom php config
RUN { \
        set -u -e -x; \
        php_ini_dir='/usr/local/etc/php/conf.d'; \
        test \( -d "$php_ini_dir" \) -a \( -w "$php_ini_dir" \); \
        cd "$php_ini_dir"; \
        echo '; Allow wrappers globally' > _custom.ini; \
        echo 'allow_url_fopen=On' >> _custom.ini; \
        echo 'allow_url_include=On' >> _custom.ini; \
        echo '; Allow file uploads' >> _custom.ini; \
        echo 'file_uploads=On' >> _custom.ini; \
        echo '; Increase max allowed size of uploaded files. Needed for some plugins' >> _custom.ini; \
        echo 'upload_max_filesize=80M' >> _custom.ini; \
        echo 'post_max_size=81M' >> _custom.ini; \
    }

VOLUME ${DOCKER_RULES_DIR}
VOLUME ${DOCKER_DOCROOT}

COPY ep.sh /

#COPY sh-wrapper /
#RUN ["/bin/bash", "-c", "unlink /bin/sh; mv /sh-wrapper /bin/sh"]

ENTRYPOINT ["/ep.sh"]
