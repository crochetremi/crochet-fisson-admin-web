# Workflow

**Document indiquant nos méthodes de travail.**

---

## 1. L'équipe

Nous avons travaillé **à deux** : Rémi CROCHET et Ronan FISSON. Dès le départ, nous avons voulu que chacun comprenne l'ensemble de l'infrastructure et pas seulement sa partie, parce que la démonstration finale et les documents engagent les deux membres du binôme.

## 2. Principes d'organisation

- **Une brique, un responsable, un relecteur.** Chaque composant du sujet a un responsable qui le conçoit et le fait fonctionner, et un relecteur qui le reprend, le teste et le documente. Personne ne travaille seul sans que l'autre ait vu le résultat.
- **Binôme sur les points qui lient plusieurs briques.** La liaison Nextcloud, Keycloak et OpenLDAP, puis celle de Lstu, OAuth2 Proxy et Keycloak, traversent les périmètres de chacun. Nous les avons traitées ensemble, devant le même écran ou en partage d'écran.
- **Tout est dans le code.** Nous avons choisi Ansible et Docker pour décrire l'infrastructure sous forme de fichiers versionnés (*Infrastructure as Code*). Cela nous a permis de travailler en dehors de l'IUT, sur nos machines personnelles, sans dépendre des postes de la salle, et de rejouer l'installation depuis zéro à tout moment.
- **Un dépôt Git partagé** (hébergé sur Github et migré à la fin sur le GitLab de l'université, comme demandé par le sujet) contient les configurations, les documents et les notes. Chacun pousse ses modifications sur `main` après les avoir testées localement, et l'autre les récupère avant de continuer.
- **On suit l'ordre conseillé par le sujet.** D'abord OpenLDAP, Keycloak et Nextcloud, puis un Lstu fonctionnel, et seulement ensuite OAuth2 Proxy. Nous n'avons pas commencé une étape avant que la précédente soit validée.
- **Documentation au fil de l'eau.** Le sujet recommande de prendre des notes au fur et à mesure. Chaque problème rencontré est noté dans la rétrospective au moment où il se produit, et le tutoriel est écrit à partir des fichiers réellement utilisés, pas de mémoire.

## 3. Répartition des tâches

| Bloc | Responsable | Relecteur | Contenu |
|---|---|---|---|
| Socle Docker et Ansible | Rémi | Ronan | `Dockerfile`, `docker-compose.yml`, démarrage de `systemd` dans le conteneur, découpage en couches |
| OpenLDAP | Rémi | Ronan | Installation de `slapd`, annuaire, import des utilisateurs, hachage des mots de passe |
| Certificats et nginx | Rémi | Ronan | Autorité de certification, certificat avec SAN, vhosts HTTPS |
| MariaDB et Nextcloud | Rémi | Ronan | Archive officielle, PHP-FPM, installation en ligne de commande avec `occ`, confiance dans la CA |
| Keycloak | Ronan | Rémi | Archive officielle, unité systemd, realm, fédération LDAP, clients OIDC |
| Lstu | Ronan | Rémi | Dépôt officiel, dépendances Perl, configuration, unité systemd |
| OAuth2 Proxy | Ronan | Rémi | Release officielle, configuration OIDC, règles `auth_request` de nginx, URL courtes publiques |
| Liaison Nextcloud et Keycloak | Rémi et Ronan | : | Application `user_oidc`, provisioning au premier démarrage |
| Tests automatiques | Rémi et Ronan | : | `tests/run-tests.sh` et rapport `documents/tests.md` |

Les documents demandés ont été répartis de la même façon, puis relus par l'autre :

| Document | Rédacteur principal | Relecteur |
|---|---|---|
| `README.md` et `tutoriel.md` | Rémi | Ronan |
| `workflow.md` et `retrospective.md` | Ronan | Rémi |

Pour vérifier que le tutoriel est suivable, le relecteur l'a déroulé de bout en bout sur une installation propre, sans l'aide de l'auteur.

Au total, chacun a pris en charge environ la moitié de l'infrastructure et la moitié des documents, et chacun a relu l'intégralité du travail de l'autre.

## 4. Planning

Nous avons avancé par étapes, dans l'ordre suivant. Chaque étape se terminait par un test avant de passer à la suivante.

| Phase | Objectif | Validation |
|---|---|---|
| 1 | Choix des outils (Docker + Ansible + nginx), conteneur Debian avec `systemd`, premier playbook | Le conteneur démarre, nginx répond |
| 2 | OpenLDAP avec utilisateurs de test | `ldapsearch` et `ldapwhoami` fonctionnent |
| 3 | Certificats, nginx en HTTPS, MariaDB, Nextcloud | Nextcloud accessible en HTTPS sans alerte |
| 4 | Keycloak avec fédération LDAP | Un utilisateur de l'annuaire se connecte à Keycloak |
| 5 | Liaison Nextcloud et Keycloak | Connexion à Nextcloud par un compte LDAP |
| 6 | Lstu sans authentification | Création et visite d'un lien court |
| 7 | OAuth2 Proxy devant Lstu | Pages d'ajout protégées, liens courts publics |
| 8 | Tests automatiques, tutoriel, rétrospective, répétition de la démonstration | Rapport de tests entièrement vert, reconstruction depuis zéro |

Le temps de construction de l'image est devenu un frein dès la phase 3. Nous avons alors réorganisé le `Dockerfile` en une couche par service, et mis en place un mode de développement où le dossier `ansible/` est monté dans le conteneur, ce qui nous a fait gagner beaucoup de temps sur les phases suivantes (voir la rétrospective).

## 5. Outils utilisés

| Usage | Outil |
|---|---|
| Versionnement | Git, GitHub et dépôt sur le GitLab de l'université |
| Conteneur servant de machine Debian | Docker et Docker Compose |
| Installation automatisée | Ansible |
| Serveur web | nginx |
| Diagnostic | `journalctl`, `systemctl`, `curl`, `ldapsearch`, journaux nginx |
| Tests | `tests/run-tests.sh` (`curl` et commandes dans le conteneur, rapport en Markdown) |
| Rédaction | Markdown, comme demandé par le sujet |
| Communication | Discord, Messages, Appels Whatsapp |

## 6. Communication et suivi

- Pendant les séances, nous travaillons côte à côte et nous nous répartissons les tâches en début de séance, en fonction de l'avancement.
- Entre les séances, l'état du dépôt Git fait foi : chacun voit ce qui a été fait, et ce qui reste à faire est noté dans nos prises de notes et dans la rétrospective.
- Lorsqu'un blocage dure, nous le traitons à deux : l'un reproduit le problème pendant que l'autre lit les journaux, puis nous consignons la cause et la solution.