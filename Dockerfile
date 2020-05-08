FROM wordpress:5.4-php7.4-apache

MAINTAINER Nikita Popov <npv1310_at_gmail.com>

ARG MODSECURITY_TARGZ
ARG MODSECURITY_BUILD_DIR
ARG MODSECURITY_RULES_DIR

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

RUN mkdir ${MODSECURITY_BUILD_DIR}
COPY ${MODSECURITY_TARGZ} ${MODSECURITY_BUILD_DIR}
RUN { \
        set -u -e -x; \
        cd ${MODSECURITY_BUILD_DIR}; \
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
    }

COPY ep.sh /

VOLUME ${MODSECURITY_RULES_DIR}

ENTRYPOINT ["/ep.sh"]
