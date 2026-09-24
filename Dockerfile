# On part d'une image Debian qui fera office de "VM"
FROM debian:latest

# On désactive les intéractions pour les paquets
ENV DEBIAN_FRONTEND=noninteractive

# Installer Systemd et Ansible et les dépendances nécessaires
RUN apt-get update && apt-get install -y \
    systemd \
    systemd-sysv \
    ansible \
    python3 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copier le Playbook dans le conteneur
WORKDIR /ansible
COPY ./ansible/ .

# Exécuter Ansible à l'intérieur du conteneur pour dérouler la configuration
RUN ansible-playbook playbook.yml

# =========================================================================
# SÉCURITÉ : Empêcher le conteneur de capturer les terminaux de l'hôte
# =========================================================================
RUN systemctl mask systemd-logind.service getty.target console-getty.service

# Au démarrage, on lance le processus init de Debian
CMD ["/lib/systemd/systemd"]