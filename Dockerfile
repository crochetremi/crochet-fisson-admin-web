# On part d'une image Debian qui fera office de "VM"
FROM debian:latest

# On désactive les intéractions pour les paquets
ENV DEBIAN_FRONTEND=noninteractive

# =========================================================================
# ASTUCE MAGIQUE : Empêcher Debian de démarrer les services pendant le build
# =========================================================================
RUN printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d && chmod +x /usr/sbin/policy-rc.d

# Installer Systemd, Ansible et les dépendances nécessaires
RUN apt-get update && apt-get install -y \
    systemd \
    systemd-sysv \
    ansible \
    python3 \
    python3-apt \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copier le Playbook dans le conteneur
WORKDIR /ansible
COPY ./ansible/ .

# Exécuter Ansible à l'intérieur du conteneur pour dérouler la configuration
RUN ansible-playbook playbook.yml

# =========================================================================
# SÉCURITÉ ET NETTOYAGE
# =========================================================================
RUN systemctl mask systemd-logind.service getty.target console-getty.service

# On supprime notre blocage temporaire pour que les services (Nginx, LDAP) 
# puissent démarrer normalement quand le conteneur sera lancé.
RUN rm /usr/sbin/policy-rc.d

# Au démarrage, on lance le processus init de Debian
CMD ["/lib/systemd/systemd"]