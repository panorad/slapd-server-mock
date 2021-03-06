#!/bin/sh
set -eu

reconfigure_slapd() {
    echo "Reconfigure slapd..."
    cat <<EOL | debconf-set-selections
slapd slapd/internal/generated_adminpw password ${LDAP_SECRET}
slapd slapd/internal/adminpw password ${LDAP_SECRET}
slapd slapd/password2 password ${LDAP_SECRET}
slapd slapd/password1 password ${LDAP_SECRET}
slapd slapd/dump_database_destdir string /var/backups/slapd-VERSION
slapd slapd/domain string ${LDAP_DOMAIN}
slapd shared/organization string ${LDAP_ORGANISATION}
slapd slapd/backend string HDB
slapd slapd/purge_database boolean true
slapd slapd/move_old_database boolean true
slapd slapd/allow_ldap_v2 boolean false
slapd slapd/no_configuration boolean false
slapd slapd/dump_database select when needed
EOL

    DEBIAN_FRONTEND=noninteractive dpkg-reconfigure slapd
}


make_snakeoil_certificate() {
    echo "Make snakeoil certificate for ${LDAP_DOMAIN}..."
    openssl req -subj "/CN=${LDAP_DOMAIN}" \
                -new \
                -newkey rsa:2048 \
                -days 365 \
                -nodes \
                -x509 \
                -keyout ${LDAP_SSL_KEY} \
                -out ${LDAP_SSL_CERT}

    chmod 600 ${LDAP_SSL_KEY}
}


configure_features() {
    echo "Configure custom attributes/extension/conf (MSAD extension, TLS, loging...)"
    # Write config ldif by substituting env vars in template
    cat ${BOOTSTRAP_DIR}/config.ldif.TEMPLATE | envsubst > /tmp/config.ldif
    ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/config.ldif -Q
}

load_initial_data() {
    echo "Load data..."
    # Write data ldif by substituting env vars in template
    cat ${BOOTSTRAP_DIR}/data.ldif.TEMPLATE | envsubst > /tmp/data.ldif
    ldapadd -x -H ldapi:/// \
      -D ${LDAP_BINDDN} \
      -w ${LDAP_SECRET} \
      -f /tmp/data.ldif
}


## Init

reconfigure_slapd
make_snakeoil_certificate
chown -R openldap:openldap /etc/ldap
slapd -h "ldapi:///" -u openldap -g openldap

configure_features
load_initial_data

kill -INT `cat /run/slapd/slapd.pid`

exit 0
