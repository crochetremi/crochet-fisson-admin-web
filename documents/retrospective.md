# Rétrospective

**Document critique indiquant les problèmes et difficultés rencontrées et comment, si c’était à refaire, nous ferions pour les résoudre et les affronter (ou les éviter).**

---

## Vue d'ensemble

Notre architecture (un conteneur Debian avec `systemd`, piloté par des playbooks Ansible) a bien rempli son objectif : l'infrastructure se reconstruit à l'identique avec une commande. Elle nous a aussi posé la plupart de nos difficultés, parce que nous l'utilisions de façon non conventionnelle et que c'était la première fois que nous utilisions Ansible. Les problèmes ci-dessous sont classés dans l'ordre où nous les avons rencontrés.

## 1. Un démarrage et des reconstructions beaucoup trop longs

**Symptôme.** Lancer le projet était déjà extrêmement long avec seulement nginx et OpenLDAP, et nous n'avions pas encore installé Nextcloud, Keycloak ni Lstu.

**Cause.** Tout le playbook s'exécutait dans une seule instruction `RUN ansible-playbook playbook.yml` du `Dockerfile`, donc dans une seule couche. À la moindre modification du playbook ou d'un fichier de configuration, Docker invalidait le cache et refaisait toute l'installation, y compris ce qui n'avait pas changé.

**Solution.** Nous avons découpé l'installation en huit playbooks (`01-ldap.yml` à `08-provision.yml`), chacun exécuté dans sa propre couche, avec un `COPY` ciblé juste avant chaque `RUN`. Nous avons aussi ajouté un `docker-compose.override.yml` qui monte `./ansible` dans le conteneur : on peut alors modifier un playbook et le rejouer dans le conteneur qui tourne, sans reconstruire l'image.

**Si c'était à refaire.** Nous découperions en couches dès le premier jour, avant même d'ajouter un second service. Un playbook monolithique ne coûte rien au début mais devient un frein dès que la pile grossit. Nous installerions aussi tout de suite le mode de développement avec montage de volume.

## 2. Un annuaire LDAP qui semblait fonctionner mais ne l'était pas

**Symptôme.** L'annuaire démarrait et acceptait notre mot de passe administrateur, mais nous avions dû ajouter une étape pour « forcer » ce mot de passe par un `ldapmodify`. Par ailleurs, l'utilisateur de test n'aurait jamais pu se connecter.

**Causes.** Deux erreurs se cachaient derrière ce qui semblait fonctionner :

- Les questions `debconf` que nous préremplissions pour `slapd` n'étaient pas les bonnes (`slapd/root_password` au lieu de `slapd/password1` et `slapd/password2`). Elles n'avaient donc aucun effet, et c'est l'étape de contournement qui masquait le problème.
- Le hash du mot de passe de l'utilisateur de test dans le fichier LDIF n'était pas un vrai hash `{SSHA}` valide.

**Solution.** Nous avons utilisé les bonnes questions `debconf`, supprimé l'étape de contournement, généré les mots de passe avec `slappasswd` au moment du build, et importé l'annuaire avec `slapadd` hors-ligne. Cette dernière méthode évite de démarrer et d'arrêter un `slapd` temporaire pendant la construction.

**Si c'était à refaire.** Nous testerions l'authentification d'un utilisateur dès l'import de l'annuaire, avec `ldapwhoami -D "uid=...,ou=users,..." -w ...`, au lieu de constater plus tard, depuis Keycloak, que la connexion échoue. Et nous nous méfierions d'une étape de contournement qui fait « marcher » un autre problème : elle doit nous pousser à chercher la cause.

## 3. Faire tourner des services dans un conteneur : démarrer ou ne pas démarrer ?

**Symptôme.** Pendant le build, les paquets Debian essaient de démarrer leurs services, et plusieurs installations ont besoin d'un service en marche (créer des bases de données, installer Nextcloud) alors que `systemd` ne tourne pas pendant un build.

**Causes et contournements.** Nous avons bloqué le démarrage des services pendant le build avec un script `policy-rc.d`. Pour les étapes qui exigent un service actif, nous avons d'abord lancé `slapd` « à la main » en arrière-plan, puis son arrêt propre a dû être géré. De même, le montage de `/run` en mémoire dans le conteneur cache les dossiers créés pendant le build (comme `/run/slapd`), ce qui nous a obligés à les recréer.

**Solution.** Nous avons séparé deux phases : le **build** installe et configure tout ce qui peut l'être sans service actif (et démarre brièvement MariaDB quand c'est indispensable), et une unité `provision.service` exécute **une seule fois au premier démarrage** ce qui exige que Keycloak soit actif (la déclaration du fournisseur d'identité dans Nextcloud).

**Si c'était à refaire.** Nous poserions dès le début la règle « build = installer, démarrage = configurer ce qui dépend des services actifs », et nous préférerions systématiquement les méthodes hors-ligne (comme `slapadd`) à celles qui nécessitent un démon temporaire.

## 4. Des erreurs `502` au démarrage : un problème d'ordre

**Symptôme.** Juste après le lancement, OAuth2 Proxy échouait à plusieurs reprises avec `unexpected status "502"` lors de la découverte OIDC, et les journaux de nginx montraient `Connection refused` vers Keycloak.

**Cause.** Keycloak (Java) met plus d'une minute à démarrer, alors qu'OAuth2 Proxy interroge sa configuration dès son lancement. Ce n'était pas un défaut de configuration mais une course entre services.

**Solution.** `Restart=always` avec `RestartSec=5` dans l'unité d'OAuth2 Proxy : il réessaie jusqu'à ce que Keycloak réponde, et il a effectivement fini par démarrer. Le provisioning de Nextcloud, lui, attend explicitement que le realm de Keycloak soit disponible avant de continuer.

**Si c'était à refaire.** Nous aurions su plus tôt que ces erreurs sont normales au démarrage et nous n'aurions pas perdu de temps à les traiter comme des pannes. Nous documenterions dès le départ l'ordre de démarrage attendu et le temps nécessaire.

## 5. Une connexion qui réussit mais se termine par une erreur 500

C'est le problème qui nous a coûté le plus de temps de diagnostic.

**Symptôme.** Sur `lstu.local`, après s'être authentifié sur Keycloak, nous arrivions sur une page `500 Internal Server Error` d'OAuth2 Proxy, avec seulement un identifiant de requête.

**Pistes trompeuses.** Les journaux d'OAuth2 Proxy montraient l'erreur `invalid_grant "Code not valid"` : on aurait pu croire à un problème de secret client ou de configuration Keycloak. Or les mêmes journaux contenaient aussi `[AuthSuccess] Authenticated via OAuth2 ... jdoe` : l'authentification avait **réussi**. L'erreur `invalid_grant` venait du fait que le navigateur rejouait la page de retour avec un code d'autorisation déjà consommé (un code OAuth ne sert qu'une fois).

**Cause réelle.** Le journal d'erreurs de nginx contenait `upstream sent too big header while reading response header from upstream` sur `/oauth2/callback`. OAuth2 Proxy renvoie, après connexion, un cookie de session volumineux (les jetons de Keycloak) qui dépassait les tampons par défaut de nginx. Le navigateur recevait une erreur, ne stockait jamais le cookie, puis rejouait la requête.

**Solution.** Augmenter les tampons dans le vhost de Lstu : `large_client_header_buffers 4 32k;` pour le serveur, et `proxy_buffer_size 128k; proxy_buffers 4 256k; proxy_busy_buffers_size 256k;` dans le bloc `/oauth2/`.

Nous avons aussi neutralisé une cause de bruit : les requêtes parallèles que le navigateur envoie automatiquement (`favicon.ico`) pouvaient réinitialiser le cookie de session de la connexion en cours. nginx répond maintenant lui-même à `favicon.ico` (code `204`) et à `robots.txt`.

**Si c'était à refaire.** Nous lirions le **journal d'erreurs de nginx en premier**, avant de chercher dans l'application : la page d'erreur d'OAuth2 Proxy ne dit rien, et l'erreur visible dans ses journaux (`invalid_grant`) n'était qu'une conséquence. Nous testerions aussi toujours dans une fenêtre de navigation privée, en repartant de l'adresse d'origine et en ne rechargeant jamais la page de retour. Enfin, nous aurions configuré les tampons agrandis dès le départ : c'est un classique d'OAuth2 Proxy avec Keycloak.

## 6. Ansible : une prise en main plus lente que prévu

C'était notre première utilisation d'Ansible. Nous avons perdu du temps sur des détails que l'expérience nous aurait évités :

- Utiliser `command` ou `shell` pour tout, au lieu des modules adaptés (`apt`, `debconf`, `file`, `copy`, `get_url`, `unarchive`), ce qui rend les tâches moins lisibles et moins idempotentes.
- Laisser un `become: yes` dans le playbook alors que nous sommes déjà `root` dans le conteneur, ce qui peut échouer si `sudo` n'est pas installé.
- Écrire les mêmes valeurs à plusieurs endroits (le mot de passe `"a"` figurait six fois dans le premier playbook), avant de les regrouper dans `group_vars/all.yml`.

**Si c'était à refaire.** Nous lirions la documentation des modules avant d'écrire une tâche `shell`, et nous mettrions dès le premier fichier toutes les valeurs configurables dans un fichier de variables.

## 7. Versions et sources non figées

Notre image de départ était `debian:latest`, qui est devenue Debian 13 alors que nous avions conçu les paquets et chemins pour Debian 12 (par exemple `php8.2-fpm`). Elle aurait changé sous nos pieds à une reconstruction. Nous utilisons maintenant `debian:12`. De même, Nextcloud est téléchargé en « dernière version », et Lstu est cloné depuis `master` : une reconstruction future pourrait ne pas donner exactement la même installation.

**Si c'était à refaire.** Nous figerions toutes les versions dès le départ (image de base, Keycloak, OAuth2 Proxy, Lstu par étiquette Git) et vérifierions les sommes de contrôle des archives, comme nous le faisons pour Nextcloud.

## 8. Ce qui a bien fonctionné

- **L'approche « infrastructure as code ».** Reconstruire depuis zéro est une commande, et nous avons pu travailler depuis chez nous.
- **Le realm Keycloak importé depuis un fichier.** Nous n'avons pas eu à reproduire des dizaines de clics à chaque reconstruction.
- **Les tests automatiques.** Le script `tests/run-tests.sh` rejoue de vraies connexions (Keycloak, Nextcloud, Lstu) et produit un rapport. Il nous a permis de vérifier d'un coup que rien n'avait cassé après un changement, et de prouver que les liens courts de Lstu restent publics alors que le reste est protégé.
- **Le travail à deux avec relecture croisée.** Chacun connaît l'ensemble de l'infrastructure (voir [workflow.md](workflow.md)).

## 9. Limites actuelles et pistes d'amélioration

- **Le bonus Matomo n'est pas réalisé.** Il suivrait le même schéma que les autres briques : archive officielle, base MariaDB, vhost nginx dédié.
- **Les mots de passe sont en clair** dans `ansible/group_vars/all.yml`. C'est acceptable pour une démonstration, mais il faudrait les chiffrer avec `ansible-vault`.
- **Le conteneur est privilégié** et regroupe tous les services. C'est pratique pour simuler une machine, mais ce n'est pas une architecture à reproduire en production, où chaque service serait isolé.
- **La règle des liens courts publics repose sur une longueur de 8 caractères.** Si la configuration de Lstu change ce paramètre, la règle nginx doit être adaptée.
- **Les données ne sont pas dans des volumes.** Elles sont reconstruites depuis l'image à chaque création du conteneur, ce qui convient au développement mais pas à un usage durable.

## Conclusion

Notre plus grosse leçon est de **traiter tôt ce qui rend les itérations lentes** (couches, volume de développement) et de **chercher la cause dans le bon journal** avant de soupçonner l'application. Une grande partie du temps perdu venait d'erreurs que les journaux de nginx, de `systemd` ou d'`slapd` nous avaient données dès le début.