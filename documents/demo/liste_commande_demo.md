# Commandes de démonstration

**Une section par point à prouver : la commande à copier-coller et le résultat attendu.**
À lancer depuis la racine du projet, conteneur démarré.

---

## 0. Préparation (une fois, avant la démo)

```bash
export CT=debian-admin-web-prj
cu() { curl -sS --cacert ansible/certs/ca.crt "$@"; }
```

`CT` est le nom du conteneur, `cu` un `curl` qui vérifie les certificats avec notre autorité. Il suppose que `/etc/hosts` contient `127.0.0.1 nextcloud.local keycloak.local lstu.local`. Sans cela, ajouter à `cu` : `--resolve lstu.local:443:127.0.0.1` (et de même pour les autres domaines).

---

## 1. Tout tourne

```bash
docker exec $CT systemctl is-active slapd mariadb php8.2-fpm nginx keycloak lstu oauth2-proxy provision
```
**Attendu :** huit lignes `active`.

```bash
docker exec $CT systemctl --failed --no-legend
```
**Attendu :** aucune ligne (aucun service en échec).

---

## 2. L'annuaire OpenLDAP est la source des utilisateurs

```bash
docker exec $CT ldapsearch -x -LLL -H ldap://localhost \
  -D "cn=admin,dc=iutnc-crochet-fisson,dc=local" -w "ldap-admin-pw" \
  -b "ou=users,dc=iutnc-crochet-fisson,dc=local" uid mail
```
**Attendu :** `jdoe` et `asmith` avec leur adresse mail.

```bash
docker exec $CT ldapwhoami -x -H ldap://localhost \
  -D "uid=jdoe,ou=users,dc=iutnc-crochet-fisson,dc=local" -w "password"
```
**Attendu :** `dn:uid=jdoe,ou=users,dc=iutnc-crochet-fisson,dc=local` (le mot de passe est valide).

```bash
docker exec $CT ldapwhoami -x -H ldap://localhost \
  -D "uid=jdoe,ou=users,dc=iutnc-crochet-fisson,dc=local" -w "mauvais"
```
**Attendu :** `ldap_bind: Invalid credentials (49)` (un mauvais mot de passe est refusé).

---

## 3. Chiffrement : HTTPS avec notre autorité de certification

```bash
openssl verify -CAfile ansible/certs/ca.crt ansible/certs/server.crt
```
**Attendu :** `ansible/certs/server.crt: OK`.

```bash
openssl x509 -in ansible/certs/server.crt -noout -ext subjectAltName
```
**Attendu :** `DNS:nextcloud.local, DNS:keycloak.local, DNS:lstu.local`.

```bash
for d in nextcloud.local keycloak.local lstu.local; do
  cu -o /dev/null -w "$d  tls=%{ssl_verify_result}  http=%{http_code}\n" https://$d/
done
```
**Attendu :** `tls=0` pour chacun (certificat validé, sans `-k`). Le code HTTP peut être `200`, `302` ou `303` selon le service.

```bash
cu -sI http://lstu.local/ | head -n 3
```
**Attendu :** `301 Moved Permanently` avec `location: https://lstu.local/` (HTTP redirigé vers HTTPS).

---

## 4. Installation conforme au sujet (sources officielles, pas d'images Docker)

```bash
docker exec $CT dpkg -l slapd nginx mariadb-server php8.2-fpm | grep ^ii | awk '{print $2, $3}'
```
**Attendu :** quatre paquets Debian installés : ce sont les briques autorisées par le sujet.

```bash
docker exec $CT dpkg -l nextcloud keycloak lstu oauth2-proxy 2>&1 | grep -c ^ii
```
**Attendu :** `0` : aucun de ces quatre logiciels ne vient d'un paquet Debian.

```bash
docker exec $CT runuser -u www-data -- php /var/www/nextcloud/occ status
docker exec $CT runuser -u keycloak -- /opt/keycloak/bin/kc.sh --version
docker exec $CT runuser -u lstu -- git -C /opt/lstu remote get-url origin
docker exec $CT /usr/local/bin/oauth2-proxy --version
```
**Attendu :** Nextcloud `installed: true` avec sa version, un numéro de version de Keycloak, l'URL `framagit.org/fiat-tux/hat-softwares/lstu`, et une version `v7.x` d'OAuth2 Proxy.

---

## 5. Keycloak utilise OpenLDAP comme source

```bash
cu https://keycloak.local/realms/sae/.well-known/openid-configuration | head -c 300; echo
```
**Attendu :** un JSON dont l'`issuer` est `https://keycloak.local/realms/sae`.

```bash
TOKEN=$(cu -d grant_type=password -d client_id=admin-cli -d username=admin -d password=kc-admin-pw \
  https://keycloak.local/realms/master/protocol/openid-connect/token \
  | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')

cu -H "Authorization: Bearer $TOKEN" \
  "https://keycloak.local/admin/realms/sae/components?type=org.keycloak.storage.UserStorageProvider" \
  | grep -o '"providerId":"ldap"'
```
**Attendu :** `"providerId":"ldap"` : la fédération LDAP est déclarée dans le realm `sae`.

```bash
cu -H "Authorization: Bearer $TOKEN" "https://keycloak.local/admin/realms/sae/users?search=jdoe" \
  | grep -o '"username":"jdoe"'
```
**Attendu :** `"username":"jdoe"` : Keycloak voit l'utilisateur de l'annuaire.

---

## 6. Nextcloud délègue l'authentification à Keycloak

```bash
cu https://nextcloud.local/status.php
```
**Attendu :** `"installed":true`.

```bash
docker exec $CT runuser -u www-data -- php /var/www/nextcloud/occ user_oidc:provider
```
**Attendu :** un fournisseur nommé `keycloak`.

```bash
cu -sI https://nextcloud.local/apps/user_oidc/login/1 | grep -i '^location'
```
**Attendu :** `location: https://keycloak.local/realms/sae/protocol/openid-connect/auth?...` : Nextcloud renvoie vers Keycloak.

---

## 7. Lstu : les pages d'ajout sont protégées

```bash
for p in / /stats /fullstats /a /un/chemin/inconnu; do
  cu -o /dev/null -w "$p  http=%{http_code}\n" https://lstu.local$p
done
```
**Attendu :** `http=302` partout (redirection vers la connexion, jamais le contenu de Lstu).

```bash
cu -o /dev/null -w "ajout sans connexion : http=%{http_code}\n" \
  -d "lsturl=https://refuse.example&format=json" https://lstu.local/a
```
**Attendu :** `302`, `401` ou `403` : le lien n'est pas créé.

```bash
cu -sI https://lstu.local/oauth2/start | grep -i '^location' | cut -c1-110
```
**Attendu :** `location: https://keycloak.local/realms/sae/protocol/openid-connect/auth...` : OAuth2 Proxy renvoie vers Keycloak.

Pour **contraster**, Lstu seul (sans la protection) répond normalement :
```bash
docker exec $CT curl -sI http://127.0.0.1:8080/ | head -n 1
```
**Attendu :** `HTTP/1.1 200 OK` : c'est bien nginx et OAuth2 Proxy qui protègent l'accès.

---

## 8. Lstu : les liens courts sont publics

```bash
SHORT=$(docker exec $CT curl -s -d "lsturl=https://example.org&format=json" http://127.0.0.1:8080/a \
  | sed -n 's/.*"short":"\([^"]*\)".*/\1/p')
echo "code court : $SHORT (${#SHORT} caractères)"
```
**Attendu :** un code de 8 caractères.

```bash
cu -o /dev/null -w "http=%{http_code}  location=%{redirect_url}\n" https://lstu.local/$SHORT
```
**Attendu :** `http=30x  location=https://example.org` : le lien fonctionne **sans aucune connexion**.

---

## 9. Tous les tests d'un coup

```bash
bash tests/run-tests.sh
```
**Attendu :** une ligne ✅ par test, un bilan sans échec, et le rapport écrit dans `documents/tests.md`.

---

## 10. Si quelque chose ne répond pas

```bash
docker exec $CT journalctl -u keycloak -n 50 --no-pager
docker exec $CT journalctl -u oauth2-proxy -n 50 --no-pager
docker exec $CT tail -n 30 /var/log/nginx/error.log
```
Keycloak met une à deux minutes à démarrer : des `502` juste après le lancement sont normaux.

---

## Ce qui se prouve dans le navigateur (pas en ligne de commande)

Ces points se montrent à l'écran, avec les comptes `jdoe` / `password` ou `asmith` / `password` :

- Connexion à Nextcloud via Keycloak, y compris le refus d'un mauvais mot de passe.
- Création d'un lien dans Lstu après connexion.
- Ouverture du lien court dans une fenêtre privée, sans connexion.
- Passage par la page de Keycloak en ouvrant `https://lstu.local` dans une fenêtre privée.

Le déroulé détaillé est dans [demo.md](demo.md).
