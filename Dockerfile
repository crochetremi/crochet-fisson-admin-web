# On part d'une image Debian qui fera office de "VM"
FROM debian:latest

#On désactive les interractions pour les paquets
ENV DEBIAN_FRONTEND=noninteractive

# 1. Installer Systemd et Ansible et les dépendances nécessaires
RUN apt-get update && apt-get install -y \
    systemd \
    systemd-sysv \
    ansible \
    python3 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 2. Copier le Playbook dans le conteneur
WORKDIR /ansible
COPY ./ansible/playbook.yml .

# 3. Exécuter Ansible à l'intérieur du conteneur pour dérouler la configuration - Le containeur est son propre chef d'orchestre.
RUN ansible-playbook playbook.yml

# 4. Au démarrage, on lance le processus init de Debian - Sinon le conteneur se termine immédiatement après le lancement
CMD ["/lib/systemd/systemd"]