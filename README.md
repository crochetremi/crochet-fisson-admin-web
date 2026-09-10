# Administrer un serveur web

><i> Rémi CROCHET et Ronan FISSON </i>

## Choix de nos outils

Nous avons décidés d'opter pour une structure mixant Docker et Ansible, le but final était de fournir un équivalent machine Linux tout en gardant une configuration facilement exportable et reproductible.

Le serveur Web retenu sera `nginx`, ce choix est arbitraire.

Outils supplémentaires non prévus par le sujet : 
    
    # Pour manager l'annuaire LDAP via une Web UI
    - PHPLDAPADMIN      

## Présentation de l'infrastructure.

Notre projet se structure comme ceci : 

```
├── ansible
│   ├── certs
│   ├── conf
│   │   └── nginx.conf
│   └── playbook.yml
├── docker-compose.yml
├── Dockerfile
├── documents
│   ├── retrospective.md
│   ├── tutoriel.md
│   └── workflow.md
└── README.md
```

Notre super-serveur regroupant les services tel que NextCloud, OpenLDAP, etc. est construit par l'association de 3 fichiers clés : `docker-compose.yml`, `Dockerfile` et enfin `playbook.yml`.

Les fichiers Docker permettent de créer une image qui :

1. expose les ports de ses services web
2. prépare l'environnement Debian en donnant les permissions et en associant les volumes nécessaires à une bonne utilisation de `systemd`

Note: Cette utilisation de Docker est "non-conventionelle", on le fait agir en tant que machine virtuelle, c'est pour cela qu'il faut lier des fichiers systèmes vers le conteneur.

Le fichier `playbook.yml` est le coeur de notre architecture. Il permet de dérouler la suite d'action permettant d'arriver à l'état de satisfaction de notre pile de services.

Nous avons choisi d'utiliser Ansible pour permettre d'avoir une Infrastructure As A Code, nous permettant ainsi de travailler en dehors de l'IUT sur les machines physiques, de pouvoir versionner l'infrastructure via GitHub.
Cela nous permettait aussi de ne pas utiliser des simples `docker-compose.yml` pré-fait et d'en faire un assemblage de Lego.

C'est la toute première fois que nous utilisons Ansible.

Nous avons choisi de créer le dossier `ansible` qui regroupe le Playbook ainsi que l'ensemble des fichiers de configurations nécessaires pour nos services. Nous glisserons notamment dans ce dossier les fichiers tel que `nginx.conf`.