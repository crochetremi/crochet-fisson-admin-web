FROM debian:12
ENV DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8

# Empêche le démarrage des services pendant le build
RUN printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d && chmod +x /usr/sbin/policy-rc.d

RUN apt-get update && apt-get install -y --no-install-recommends \
    systemd systemd-sysv ansible python3 python3-apt \
    ca-certificates openssl curl bzip2 unzip xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        lsb-release \
    && curl -fsSL https://packages.sury.org/php/README.txt | bash -x \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /ansible
COPY ansible/group_vars/ group_vars/
COPY ansible/tasks/ tasks/

# --- 1. OpenLDAP ---
COPY ansible/01-ldap.yml ./
COPY ansible/templates/users.ldif.j2 templates/
RUN ansible-playbook 01-ldap.yml

# --- 2. Nginx + certificats ---
COPY ansible/certs/ca.crt ansible/certs/server.crt ansible/certs/server.key certs/
COPY ansible/02-nginx.yml ./
RUN ansible-playbook 02-nginx.yml

# --- 3. MariaDB ---
COPY ansible/03-mariadb.yml ./
RUN ansible-playbook 03-mariadb.yml

# --- 4. Nextcloud ---
COPY ansible/04-nextcloud.yml ./
COPY ansible/conf/php/99-nextcloud.ini conf/php/
COPY ansible/conf/nginx/nextcloud.conf conf/nginx/
RUN ansible-playbook 04-nextcloud.yml

# --- 5. Keycloak ---
COPY ansible/05-keycloak.yml ./
COPY ansible/templates/keycloak.conf.j2 ansible/templates/keycloak.service.j2 ansible/templates/realm.json.j2 templates/
COPY ansible/conf/nginx/keycloak.conf conf/nginx/
RUN ansible-playbook 05-keycloak.yml

# --- 6. Lstu (sans authentification pour l'instant) ---
COPY ansible/06-lstu.yml ./
COPY ansible/templates/lstu.conf.j2 templates/
COPY ansible/conf/systemd/lstu.service conf/systemd/
COPY ansible/conf/nginx/lstu-noauth.conf conf/nginx/
RUN ansible-playbook 06-lstu.yml

# --- 7. OAuth2 Proxy (écrase le vhost Lstu par la version protégée) ---
COPY ansible/07-oauth2-proxy.yml ./
COPY ansible/templates/oauth2-proxy.cfg.j2 templates/
COPY ansible/conf/systemd/oauth2-proxy.service conf/systemd/
COPY ansible/conf/nginx/lstu.conf conf/nginx/
RUN ansible-playbook 07-oauth2-proxy.yml

# --- 8. Provisioning au premier démarrage ---
COPY ansible/08-provision.yml ansible/provision.yml ./
COPY ansible/conf/systemd/provision.service conf/systemd/
RUN ansible-playbook 08-provision.yml

RUN systemctl mask systemd-logind.service getty.target console-getty.service
RUN rm /usr/sbin/policy-rc.d
CMD ["/lib/systemd/systemd"]