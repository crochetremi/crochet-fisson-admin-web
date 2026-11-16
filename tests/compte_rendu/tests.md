# Tests de l'infrastructure

_Généré le 16/11/2026 à 15:04 par `tests/run-tests.sh`._

**Bilan : 51 tests réussis, 0 échoués, sur 51.**

## Méthode

Chaque test lance une commande (`curl` depuis l'hôte, ou une commande dans le conteneur
via `docker exec`) et compare la réponse à un résultat attendu. Les `curl` utilisent
`--cacert ansible/certs/ca.crt`, ce qui vérifie aussi la validité de nos certificats,
et `--resolve` pour joindre les domaines `*.local` sans modifier `/etc/hosts`.
Les parcours de la section 8 rejouent une vraie connexion : formulaire Keycloak, envoi
du mot de passe, puis suivi des redirections jusqu'à l'application.

## 1. Services système (dans le conteneur)

### 1. Les 7 services sont actifs

- **On attend** : 7 lignes `active`
- **Verdict** : ✅ OK

```bash
docker exec debian-admin-web-prj systemctl is-active slapd mariadb php8.3-fpm nginx keycloak lstu oauth2-proxy
```

```text
active
active
active
active
active
active
active
```

### 2. Le provisioning du premier démarrage a réussi

- **On attend** : `active` (oneshot terminé)
- **Verdict** : ✅ OK

```bash
docker exec debian-admin-web-prj systemctl is-active provision
```

```text
active
```

## 2. Annuaire OpenLDAP

### 3. Les utilisateurs existent dans l'annuaire

- **On attend** : l'entrée `uid=jdoe` avec son email
- **Verdict** : ✅ OK

```bash
docker exec debian-admin-web-prj ldapsearch -x -LLL -H ldap://localhost -D "cn=admin,$BASE" -w "$LDAPPW" -b "ou=users,$BASE" uid mail
```

```text
dn: ou=users,dc=iutnc-crochet-fisson,dc=local

dn: uid=jdoe,ou=users,dc=iutnc-crochet-fisson,dc=local
uid: jdoe
mail: jdoe@iutnc-crochet-fisson.local

dn: uid=asmith,ou=users,dc=iutnc-crochet-fisson,dc=local
uid: asmith
mail: asmith@iutnc-crochet-fisson.local
```

### 4. Le mot de passe de jdoe est valide (hash correct)

- **On attend** : `ldapwhoami` renvoie le DN de l'utilisateur
- **Verdict** : ✅ OK

```bash
docker exec debian-admin-web-prj ldapwhoami -x -H ldap://localhost -D "uid=$TEST_USER,ou=users,$BASE" -w "$TEST_PW"
```

```text
dn:uid=jdoe,ou=users,dc=iutnc-crochet-fisson,dc=local
```

## 3. Nginx : redirections HTTP et certificats TLS

### 5. HTTP redirige vers HTTPS (nextcloud.local)

- **On attend** : `301 Moved Permanently` vers https://nextcloud.local/
- **Verdict** : ✅ OK

```bash
curl -sI http://nextcloud.local/
```

```text
HTTP/1.1 301 Moved Permanently
Server: nginx/1.22.1
Date: Mon, 16 Nov 2026 14:04:31 GMT
Content-Type: text/html
Content-Length: 169
Connection: keep-alive
Location: https://nextcloud.local/

```

### 6. Certificat valide pour nextcloud.local (signé par notre CA)

- **On attend** : `ssl_verify_result=0`
- **Verdict** : ✅ OK

```bash
curl -o /dev/null -w 'ssl_verify_result=%{ssl_verify_result} http_code=%{http_code}\n' https://nextcloud.local/
```

```text
ssl_verify_result=0 http_code=302
```

### 7. HTTP redirige vers HTTPS (keycloak.local)

- **On attend** : `301 Moved Permanently` vers https://keycloak.local/
- **Verdict** : ✅ OK

```bash
curl -sI http://keycloak.local/
```

```text
HTTP/1.1 301 Moved Permanently
Server: nginx/1.22.1
Date: Mon, 16 Nov 2026 14:04:32 GMT
Content-Type: text/html
Content-Length: 169
Connection: keep-alive
Location: https://keycloak.local/

```

### 8. Certificat valide pour keycloak.local (signé par notre CA)

- **On attend** : `ssl_verify_result=0`
- **Verdict** : ✅ OK

```bash
curl -o /dev/null -w 'ssl_verify_result=%{ssl_verify_result} http_code=%{http_code}\n' https://keycloak.local/
```

```text
ssl_verify_result=0 http_code=302
```

### 9. HTTP redirige vers HTTPS (lstu.local)

- **On attend** : `301 Moved Permanently` vers https://lstu.local/
- **Verdict** : ✅ OK

```bash
curl -sI http://lstu.local/
```

```text
HTTP/1.1 301 Moved Permanently
Server: nginx/1.22.1
Date: Mon, 16 Nov 2026 14:04:32 GMT
Content-Type: text/html
Content-Length: 169
Connection: keep-alive
Location: https://lstu.local/

```

### 10. Certificat valide pour lstu.local (signé par notre CA)

- **On attend** : `ssl_verify_result=0`
- **Verdict** : ✅ OK

```bash
curl -o /dev/null -w 'ssl_verify_result=%{ssl_verify_result} http_code=%{http_code}\n' https://lstu.local/
```

```text
ssl_verify_result=0 http_code=302
```

### 11. Le certificat serveur est signé par notre CA

- **On attend** : `server.crt: OK`
- **Verdict** : ✅ OK

```bash
openssl verify -CAfile ansible/certs/ca.crt ansible/certs/server.crt
```

```text
ansible/certs/server.crt: OK
```

### 12. Le certificat couvre les 3 domaines (SAN)

- **On attend** : nextcloud.local, keycloak.local et lstu.local dans le SAN
- **Verdict** : ✅ OK

```bash
openssl x509 -in ansible/certs/server.crt -noout -ext subjectAltName
```

```text
X509v3 Subject Alternative Name: 
    DNS:nextcloud.local, DNS:keycloak.local, DNS:lstu.local
```

### 13. Le certificat n'expire pas avant 7 jours (jour de la démo)

- **On attend** : `Certificate will not expire`
- **Verdict** : ✅ OK

```bash
openssl x509 -in ansible/certs/server.crt -noout -checkend 604800
```

```text
Certificate will not expire
```

### 14. Le conteneur fait confiance à la CA (sans --cacert)

- **On attend** : `http=200` sans erreur TLS
- **Verdict** : ✅ OK

```bash
docker exec debian-admin-web-prj curl -sS -o /dev/null -w 'http=%{http_code}\n' https://keycloak.local/realms/sae
```

```text
http=200
```

### 15. Nextcloud fait confiance à la CA

- **On attend** : `ca.crt` listé parmi les certificats importés
- **Verdict** : ✅ OK

```bash
docker exec debian-admin-web-prj runuser -u www-data -- php /var/www/nextcloud/occ security:certificates
```

```text
+-----------+---------------------+--------------+-----------------+---------------------+
| File Name | Common Name         | Organization | Valid Until     | Issued By           |
+-----------+---------------------+--------------+-----------------+---------------------+
| ca.crt    | CA-DACS.example.net | CA-DACS      | January 8, 2029 | CA-DACS.example.net |
+-----------+---------------------+--------------+-----------------+---------------------+
```

## 4. Keycloak

### 16. Le realm sae publie sa configuration OIDC

- **On attend** : un JSON dont l'`issuer` est https://keycloak.local/realms/sae
- **Verdict** : ✅ OK

```bash
curl -s https://keycloak.local/realms/sae/.well-known/openid-configuration
```

```text
{"issuer":"https://keycloak.local/realms/sae","authorization_endpoint":"https://keycloak.local/realms/sae/protocol/openid-connect/auth","token_endpoint":"https://keycloak.local/realms/sae/protocol/ope
```

### 17. La console d'administration répond

- **On attend** : `200` ou `302`
- **Verdict** : ✅ OK

```bash
curl -sI https://keycloak.local/admin/
```

```text
HTTP/2 302 
server: nginx/1.22.1
date: Mon, 16 Nov 2026 14:04:32 GMT
location: https://keycloak.local/admin/master/console/
referrer-policy: no-referrer
strict-transport-security: max-age=31536000; includeSubDomains
x-content-type-options: nosniff

```

### 18. La fédération LDAP est configurée dans le realm

- **On attend** : un composant de type `ldap` (jeton admin obtenu via l'API, non affiché)
- **Verdict** : ✅ OK

```bash
curl -s -H "Authorization: Bearer $KC_TOKEN" "https://keycloak.local/admin/realms/$REALM/components?type=org.keycloak.storage.UserStorageProvider"
```

```text
[{"id":"jvqvC4j7SY6XaRVvecFwsw","name":"openldap","providerId":"ldap","providerType":"org.keycloak.storage.UserStorageProvider","parentId":"fc6473b4-89c7-4c3d-bb51-f416afed3290","config":{"pagination"
```

### 19. Keycloak voit les utilisateurs de l'annuaire LDAP

- **On attend** : l'utilisateur jdoe est trouvé via la fédération
- **Verdict** : ✅ OK

```bash
curl -s -H "Authorization: Bearer $KC_TOKEN" "https://keycloak.local/admin/realms/$REALM/users?search=$TEST_USER"
```

```text
[{"id":"4a000c6b-5a43-4dc5-b786-2be8c5866013","username":"jdoe","firstName":"John","lastName":"Doe","email":"jdoe@iutnc-crochet-fisson.local","emailVerified":true,"attributes":{"LDAP_ENTRY_DN":["uid=j
```

## 5. Nextcloud

### 20. Nextcloud est installé

- **On attend** : `"installed":true`
- **Verdict** : ✅ OK

```bash
curl -s https://nextcloud.local/status.php
```

```text
{"installed":true,"maintenance":false,"needsDbUpgrade":false,"version":"35.0.3.2","versionstring":"35.0.3","edition":"","productname":"Nextcloud","extendedSupport":false}
```

### 21. La page de connexion répond

- **On attend** : `HTTP/2 200`
- **Verdict** : ✅ OK

```bash
curl -sI https://nextcloud.local/login
```

```text
HTTP/2 200 
server: nginx/1.22.1
date: Mon, 16 Nov 2026 14:04:32 GMT
content-type: text/html; charset=UTF-8
content-length: 18274
vary: Accept-Encoding
set-cookie: ocpepvxzpbeb=50q3h7jmb3lshfhgparlaucd7i; path=/; secure; HttpOnly; SameSite=Lax
set-cookie: oc_sessionPassphrase=4bqzT%2Fe98O5uFsrKsJ2wV3bv004%2BXwsHJAXFuKrGO9jcAFiTmBNkia1iGCqenQYjA6oXuipHTYF3HXD1jFMgEwBwlilIt%2Fv6wxTrJAXnEUORYpe54fVXCxWO0VAgWtwn; path=/; secure; HttpOnly; SameS
set-cookie: __Host-nc_sameSiteCookielax=true; path=/; httponly;secure; expires=Fri, 31-Dec-2100 23:59:59 GMT; SameSite=lax
set-cookie: __Host-nc_sameSiteCookiestrict=true; path=/; httponly;secure; expires=Fri, 31-Dec-2100 23:59:59 GMT; SameSite=strict
x-request-id: mpaKauT4xZ7lN1fErqUH
cache-control: no-cache, no-store, must-revalidate
content-security-policy: default-src 'none';base-uri 'none';manifest-src 'self';script-src 'nonce-0aPQtHlS+HM1L9fSng8KfV9+wLxJymqRLqt0JU2dfFs=';script-src-elem 'strict-dynamic' 'nonce-0aPQtHlS+HM1L9fS
feature-policy: autoplay 'self';camera 'none';fullscreen 'self';geolocation 'none';microphone 'none';payment 'none'
x-robots-tag: noindex, nofollow
referrer-policy: no-referrer
x-content-type-options: nosniff
x-frame-options: SAMEORIGIN
x-robots-tag: noindex, nofollow

```

### 22. Le provider OIDC Keycloak est déclaré dans Nextcloud

- **On attend** : un provider nommé `keycloak`
- **Verdict** : ✅ OK

```bash
docker exec debian-admin-web-prj runuser -u www-data -- php /var/www/nextcloud/occ user_oidc:provider
```

```text
+----+------------+--------------------------------------------------------------------+----------------------+-----------+
| ID | Identifier | Discovery endpoint                                                 | End session endpoint | Client ID |
+----+------------+--------------------------------------------------------------------+----------------------+-----------+
| 1  | keycloak   | https://keycloak.local/realms/sae/.well-known/openid-configuration |                      | nextcloud |
+----+------------+--------------------------------------------------------------------+----------------------+-----------+
```

### 23. Le bouton de connexion renvoie vers Keycloak

- **On attend** : redirection vers l'endpoint d'authentification du realm
- **Verdict** : ✅ OK

```bash
curl -sI https://nextcloud.local/apps/user_oidc/login/1
```

```text
HTTP/2 303 
server: nginx/1.22.1
date: Mon, 16 Nov 2026 14:04:32 GMT
content-type: text/html; charset=UTF-8
content-length: 0
location: https://keycloak.local/realms/sae/protocol/openid-connect/auth?client_id=nextcloud&response_type=code&scope=openid+email+profile&redirect_uri=https%3A%2F%2Fnextcloud.local%2Fapps%2Fuser_oidc
set-cookie: ocpepvxzpbeb=nqu7egktqarnlj1dumpi0k3gqh; path=/; secure; HttpOnly; SameSite=Lax
set-cookie: oc_sessionPassphrase=%2B223xs6t8CWcDUN8laL45QOg2lzHP1Ie3zmnTW%2FRzDBJqBrwQJVxG3KL86hJodQIS400gN8T%2B%2BH4tD6HFIXbepn5MmAOFBoMVLlKXcpgN6pgd%2F72TNOpUuAJW49twD8V; path=/; secure; HttpOnly; S
set-cookie: __Host-nc_sameSiteCookielax=true; path=/; httponly;secure; expires=Fri, 31-Dec-2100 23:59:59 GMT; SameSite=lax
set-cookie: __Host-nc_sameSiteCookiestrict=true; path=/; httponly;secure; expires=Fri, 31-Dec-2100 23:59:59 GMT; SameSite=strict
x-request-id: CrB5FUSYj9kWu9Y9FKu7
cache-control: no-cache, no-store, must-revalidate
content-security-policy: default-src 'none';base-uri 'none';manifest-src 'self';frame-ancestors 'none'
feature-policy: autoplay 'none';camera 'none';fullscreen 'none';geolocation 'none';microphone 'none';payment 'none'
x-robots-tag: noindex, nofollow
referrer-policy: no-referrer
x-content-type-options: nosniff
x-frame-options: SAMEORIGIN
x-robots-tag: noindex, nofollow

```

## 6. Lstu et OAuth2 Proxy : protection des pages

### 24. Le backend Lstu répond directement (sans nginx)

- **On attend** : `HTTP/1.1 200` sur 127.0.0.1:8080 dans le conteneur
- **Verdict** : ✅ OK

```bash
docker exec debian-admin-web-prj curl -sI http://127.0.0.1:8080/
```

```text
HTTP/1.1 200 OK
Content-Length: 3334
Content-Security-Policy: base-uri 'self'; default-src 'none'; font-src 'self'; form-action 'self'; frame-ancestors 'none'; img-src 'self' data:; script-src 'self'; style-src 'self'
Content-Type: text/html;charset=UTF-8
Date: Mon, 16 Nov 2026 14:04:33 GMT
Server: Mojolicious (Perl)
Set-Cookie: mojolicious=eyJjc3JmX3Rva2VuIjoiZjM4YzhmMWIyODVlMmIxMzE2MjVjYWQ3OTc0NDgwZjM1YWYwZDVhNCIsImV4cGlyZXMiOjE3OTQ4NDE0NzN9WlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpa
Vary: Accept-Encoding
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
X-XSS-Protection: 1; mode=block

```

### 25. Page protégée sans cookie : /

- **On attend** : `302` (redirection vers la connexion), jamais le contenu de Lstu
- **Verdict** : ✅ OK

```bash
curl -o /dev/null -w 'http=%{http_code} location=%{redirect_url}\n' https://lstu.local/
```

```text
http=302 location=https://keycloak.local/realms/sae/protocol/openid-connect/auth?approval_prompt=force&client_id=lstu&code_challenge=YTpc5WVPlCcyPg8Lc5a2M_hsXRIfDlfU5UTlFQqzdOk&code_challenge_method=S
```

### 26. Page protégée sans cookie : /stats

- **On attend** : `302` (redirection vers la connexion), jamais le contenu de Lstu
- **Verdict** : ✅ OK

```bash
curl -o /dev/null -w 'http=%{http_code} location=%{redirect_url}\n' https://lstu.local/stats
```

```text
http=302 location=https://keycloak.local/realms/sae/protocol/openid-connect/auth?approval_prompt=force&client_id=lstu&code_challenge=5OPbHpw_sWiQr8AkoaOoQmGzaMHDmzdKh8GRGp3Q3W4&code_challenge_method=S
```

### 27. Page protégée sans cookie : /fullstats

- **On attend** : `302` (redirection vers la connexion), jamais le contenu de Lstu
- **Verdict** : ✅ OK

```bash
curl -o /dev/null -w 'http=%{http_code} location=%{redirect_url}\n' https://lstu.local/fullstats
```

```text
http=302 location=https://keycloak.local/realms/sae/protocol/openid-connect/auth?approval_prompt=force&client_id=lstu&code_challenge=C0hXDOa0itcUNvENb9oJXZMVw_1i3fhgqOJUyq_kseg&code_challenge_method=S
```

### 28. Page protégée sans cookie : /a

- **On attend** : `302` (redirection vers la connexion), jamais le contenu de Lstu
- **Verdict** : ✅ OK

```bash
curl -o /dev/null -w 'http=%{http_code} location=%{redirect_url}\n' https://lstu.local/a
```

```text
http=302 location=https://keycloak.local/realms/sae/protocol/openid-connect/auth?approval_prompt=force&client_id=lstu&code_challenge=FOdjQT_UTjdePgCh6HOHVE8nlvDQreoF9EyXlX8rlxw&code_challenge_method=S
```

### 29. Ajout d'une URL refusé sans authentification

- **On attend** : `302`, `401` ou `403` (le lien n'est pas créé)
- **Verdict** : ✅ OK

```bash
curl -o /dev/null -w 'http=%{http_code}\n' -d 'lsturl=https://refuse.example&format=json' https://lstu.local/a
```

```text
http=302
```

### 30. OAuth2 Proxy redirige vers Keycloak

- **On attend** : `302` avec `location` vers keycloak.local
- **Verdict** : ✅ OK

```bash
curl -sI https://lstu.local/oauth2/start
```

```text
HTTP/2 302 
server: nginx/1.22.1
date: Mon, 16 Nov 2026 14:04:33 GMT
content-type: text/html; charset=utf-8
cache-control: no-cache, no-store, must-revalidate, max-age=0
expires: Thu, 01 Jan 1970 00:00:00 UTC
location: https://keycloak.local/realms/sae/protocol/openid-connect/auth?approval_prompt=force&client_id=lstu&code_challenge=Upf35FuqZgR6D-wuTX-wJlleQZX9bddEvnGnUJCCn0k&code_challenge_method=S256&redi
set-cookie: _oauth2_proxy_csrf=mwElaoqlaQxkVna7b_IqPUXqs_3XEmoz69XIsFkC7jCO1cVNgPETeMPAVrc1ZKq2Qta_ZwySI2TlGwHwDapsNeuEWxw02fuY0myxX5sGW_u_lWU3xtff0bfbMHSyzHRCv4VPnAHMyszpOjupCgmElO0bz75LvmfjV16pTC-bT

```

### 31. favicon.ico est servi localement par nginx

- **On attend** : `204`
- **Verdict** : ✅ OK

```bash
curl -o /dev/null -w 'http=%{http_code}\n' https://lstu.local/favicon.ico
```

```text
http=204
```

### 32. Chemin inconnu protégé par défaut (refus par défaut)

- **On attend** : `302` : tout ce qui n'est pas une URL courte exige l'authentification
- **Verdict** : ✅ OK

```bash
curl -o /dev/null -w 'http=%{http_code}\n' https://lstu.local/un/chemin/inconnu
```

```text
http=302
```

### 33. Suppression d'un lien refusée sans authentification

- **On attend** : `302`, `401` ou `403`
- **Verdict** : ✅ OK

```bash
curl -o /dev/null -w 'http=%{http_code}\n' https://lstu.local/d/aaaaaaaa
```

```text
http=302
```

### 34. Ajout par GET refusé sans authentification

- **On attend** : `302`, `401` ou `403`
- **Verdict** : ✅ OK

```bash
curl -o /dev/null -w 'http=%{http_code}\n' 'https://lstu.local/a?lsturl=https://refuse.example&format=json'
```

```text
http=302
```

## 7. Lstu : les URL raccourcies sont publiques

### 35. Création d'un lien court directement sur le backend

- **On attend** : un JSON contenant la clé `short`
- **Verdict** : ✅ OK

```bash
docker exec debian-admin-web-prj curl -s -d "lsturl=https://example.org&format=json" http://127.0.0.1:8080/a
```

```text
{"qrcode":"iVBORw0KGgoAAAANSUhEUgAAAGMAAABjAQAAAACnQIM4AAAA7ElEQVQ4jc3Uuw3EIAwAUCMKyiyA\nxBp0rBQWyGeBZCU61ojEAtClQPI591HSJI6uOJ1FwSsQtvkAHgP+WBmgX5c+gOBUsHo0c6QJp6A7\nZTCCv6HWynJPPdb+jiiXaMZDZmei+nzUf
```

## 8. Parcours complets avec connexion (OIDC)

### 36. Connexion à Lstu via OAuth2 Proxy puis Keycloak puis LDAP

- **On attend** : arrivée sur https://lstu.local/ avec `status=200`
- **Verdict** : ✅ OK

```bash
kc_login "$JAR1" https://lstu.local/ "$TEST_USER" "$TEST_PW"
```

```text
status=200 final_url=https://lstu.local/
```

### 37. Ajout d'un lien une fois authentifié

- **On attend** : un JSON contenant la clé `short`
- **Verdict** : ✅ OK

```bash
curl -s -b "$JAR1" -d "lsturl=https://example.org/protege&format=json" https://lstu.local/a
```

```text
{"qrcode":"iVBORw0KGgoAAAANSUhEUgAAAGMAAABjAQAAAACnQIM4AAAA60lEQVQ4jc3Uuw3DIBAA0LMo6JIF\nkFiDjpXMAmBP4JXoWCMSC0BHgXIBJVHSmKNLruIV6H4IwO+AP1YCMEU4DwuljNXymEM7UPLCBbYH\nMDNCMHOy6jYlrC6A+1R2qt5fEOar2zO1y
```

### 38. Un mauvais mot de passe est refusé par Keycloak

- **On attend** : le message `Invalid username or password`
- **Verdict** : ✅ OK

```bash
kc_login "$JAR3" https://lstu.local/ "$TEST_USER" "mauvais-mot-de-passe"
```

```text
status=200 final_url=https://keycloak.local/realms/sae/login-actions/authenticate?session_code=3y2NUIIRun3j6B5xI3lUwertdJldBLbqXN5q1gekTnY&execution=91bbe085-b5c4-4a19-99ce-c5c64bd0c54c&client_id=lstu
keycloak: Invalid username or password
```

### 39. Connexion à Nextcloud via Keycloak

- **On attend** : arrivée sur https://nextcloud.local/ avec `status=200`
- **Verdict** : ✅ OK

```bash
kc_login "$JAR2" https://nextcloud.local/apps/user_oidc/login/1 "$TEST_USER" "$TEST_PW"
```

```text
status=200 final_url=https://nextcloud.local/apps/dashboard/
```

### 40. La session Nextcloud appartient bien à l'utilisateur LDAP

- **On attend** : l'API OCS renvoie `"id":"jdoe"`
- **Verdict** : ✅ OK

```bash
curl -s -b "$JAR2" -H "OCS-APIRequest: true" "https://nextcloud.local/ocs/v2.php/cloud/user?format=json"
```

```text
{"ocs":{"meta":{"status":"ok","statuscode":200,"message":"OK"},"data":{"enabled":true,"id":"jdoe","firstLoginTimestamp":1794834519,"lastLoginTimestamp":1794837874,"lastLogin":1794837874000,"backend":"
```

### 41. Un utilisateur absent de l'annuaire est refusé (Nextcloud)

- **On attend** : `Invalid username or password`
- **Verdict** : ✅ OK

```bash
kc_login "$JAR4" https://nextcloud.local/apps/user_oidc/login/1 "inconnu" "password"
```

```text
status=200 final_url=https://keycloak.local/realms/sae/login-actions/authenticate?session_code=znt3rrUXlYx7l2nvuDo5Ou9O4dIe7bEezfLXAeyo-k0&execution=91bbe085-b5c4-4a19-99ce-c5c64bd0c54c&client_id=next
keycloak: Invalid username or password
```

### 42. Un mauvais mot de passe est refusé (Nextcloud)

- **On attend** : `Invalid username or password`
- **Verdict** : ✅ OK

```bash
kc_login "$JAR6" https://nextcloud.local/apps/user_oidc/login/1 "$TEST_USER" "mauvais-mot-de-passe"
```

```text
status=200 final_url=https://keycloak.local/realms/sae/login-actions/authenticate?session_code=LhY4r2jBzAIP5Ra_g_GwhZ16UCPNnLDtpR1V5GOayiQ&execution=91bbe085-b5c4-4a19-99ce-c5c64bd0c54c&client_id=next
keycloak: Invalid username or password
```

### 43. Un second utilisateur LDAP (asmith) se connecte à Nextcloud

- **On attend** : arrivée sur Nextcloud avec `status=200`
- **Verdict** : ✅ OK

```bash
kc_login "$JAR5" https://nextcloud.local/apps/user_oidc/login/1 asmith "$TEST_PW"
```

```text
status=200 final_url=https://nextcloud.local/apps/dashboard/
```

### 44. La session Nextcloud d'asmith est bien celle d'asmith

- **On attend** : l'API OCS renvoie `"id":"asmith"`
- **Verdict** : ✅ OK

```bash
curl -s -b "$JAR5" -H "OCS-APIRequest: true" "https://nextcloud.local/ocs/v2.php/cloud/user?format=json"
```

```text
{"ocs":{"meta":{"status":"ok","statuscode":200,"message":"OK"},"data":{"enabled":true,"id":"asmith","firstLoginTimestamp":1794834521,"lastLoginTimestamp":1794837874,"lastLogin":1794837874000,"backend"
```

## 9. Installation conforme au sujet

### 45. OpenLDAP, nginx, MariaDB et PHP viennent de paquets Debian

- **On attend** : `4` paquets au statut installé
- **Verdict** : ✅ OK

```bash
docker exec debian-admin-web-prj dpkg -l slapd nginx mariadb-server php8.3-fpm | grep -c ^ii
```

```text
4
```

### 46. Nextcloud, Keycloak, Lstu et OAuth2 Proxy ne viennent PAS de paquets Debian

- **On attend** : `0` paquet : ils sont installés depuis les sources officielles
- **Verdict** : ✅ OK

```bash
docker exec debian-admin-web-prj dpkg -l nextcloud keycloak lstu oauth2-proxy 2>&1 | grep -c ^ii
```

```text
0
```

### 47. Nextcloud : archive officielle en place

- **On attend** : `installed: true`
- **Verdict** : ✅ OK

```bash
docker exec debian-admin-web-prj runuser -u www-data -- php /var/www/nextcloud/occ status
```

```text
  - installed: true
  - version: 35.0.3.2
  - versionstring: 35.0.3
  - edition: 
  - maintenance: false
  - needsDbUpgrade: false
  - productname: Nextcloud
  - extendedSupport: false
```

### 48. Keycloak : archive officielle dans /opt/keycloak

- **On attend** : un numéro de version
- **Verdict** : ✅ OK

```bash
docker exec debian-admin-web-prj runuser -u keycloak -- /opt/keycloak/bin/kc.sh --version
```

```text
Keycloak 26.4.0
JVM: 17.0.21 (Debian OpenJDK 64-Bit Server VM 17.0.21+9-1-deb12u1-Debian)
OS: Linux 7.2.15-arch1-1 amd64
```

### 49. Lstu : dépôt officiel cloné depuis framagit

- **On attend** : l'URL du dépôt `origin`
- **Verdict** : ✅ OK

```bash
docker exec debian-admin-web-prj runuser -u lstu -- git -C /opt/lstu remote get-url origin
```

```text
https://framagit.org/fiat-tux/hat-softwares/lstu.git
```

### 50. OAuth2 Proxy : binaire de la release officielle

- **On attend** : une version `v7.x`
- **Verdict** : ✅ OK

```bash
docker exec debian-admin-web-prj /usr/local/bin/oauth2-proxy --version
```

```text
oauth2-proxy v7.12.0 (built with go1.24.6)
```

## 10. Livrables

### 51. Les documents demandés existent et ne sont pas vides

- **On attend** : 4 lignes « présent »
- **Verdict** : ✅ OK

```bash
check_docs
```

```text
présent  README.md
présent  documents/tutoriel.md
présent  documents/workflow.md
présent  documents/retrospective.md
```

