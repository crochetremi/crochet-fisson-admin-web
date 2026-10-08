# Tests de l'infrastructure

_Généré le 08/10/2026 à 14:48 par `tests/run-tests.sh`._

**Bilan : 32 tests réussis, 2 échoués, sur 34.**

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
Date: Thu, 08 Oct 2026 12:48:05 GMT
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
Date: Thu, 08 Oct 2026 12:48:05 GMT
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
Date: Thu, 08 Oct 2026 12:48:05 GMT
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

## 4. Keycloak

### 11. Le realm sae publie sa configuration OIDC

- **On attend** : un JSON dont l'`issuer` est https://keycloak.local/realms/sae
- **Verdict** : ✅ OK

```bash
curl -s https://keycloak.local/realms/sae/.well-known/openid-configuration
```

```text
{"issuer":"https://keycloak.local/realms/sae","authorization_endpoint":"https://keycloak.local/realms/sae/protocol/openid-connect/auth","token_endpoint":"https://keycloak.local/realms/sae/protocol/ope
```

### 12. La console d'administration répond

- **On attend** : `200` ou `302`
- **Verdict** : ✅ OK

```bash
curl -sI https://keycloak.local/admin/
```

```text
HTTP/2 302 
server: nginx/1.22.1
date: Thu, 08 Oct 2026 12:48:05 GMT
location: https://keycloak.local/admin/master/console/
referrer-policy: no-referrer
strict-transport-security: max-age=31536000; includeSubDomains
x-content-type-options: nosniff

```

### 13. La fédération LDAP est configurée dans le realm

- **On attend** : un composant de type `ldap` (jeton admin obtenu via l'API, non affiché)
- **Verdict** : ✅ OK

```bash
curl -s -H "Authorization: Bearer $KC_TOKEN" "https://keycloak.local/admin/realms/$REALM/components?type=org.keycloak.storage.UserStorageProvider"
```

```text
[{"id":"9Sh_2GYeS8uFfh7Tmm1S_A","name":"openldap","providerId":"ldap","providerType":"org.keycloak.storage.UserStorageProvider","parentId":"b1d3aed0-6abb-4699-874a-16089bd383eb","config":{"pagination"
```

### 14. Keycloak voit les utilisateurs de l'annuaire LDAP

- **On attend** : l'utilisateur jdoe est trouvé via la fédération
- **Verdict** : ✅ OK

```bash
curl -s -H "Authorization: Bearer $KC_TOKEN" "https://keycloak.local/admin/realms/$REALM/users?search=$TEST_USER"
```

```text
[{"id":"6840c0ae-7ba7-4ec0-9ce4-ebf732a96589","username":"jdoe","firstName":"John","lastName":"Doe","email":"jdoe@iutnc-crochet-fisson.local","emailVerified":true,"attributes":{"LDAP_ENTRY_DN":["uid=j
```

## 5. Nextcloud

### 15. Nextcloud est installé

- **On attend** : `"installed":true`
- **Verdict** : ✅ OK

```bash
curl -s https://nextcloud.local/status.php
```

```text
{"installed":true,"maintenance":false,"needsDbUpgrade":false,"version":"35.0.1.1","versionstring":"35.0.1","edition":"","productname":"Nextcloud","extendedSupport":false}
```

### 16. La page de connexion répond

- **On attend** : `HTTP/2 200`
- **Verdict** : ✅ OK

```bash
curl -sI https://nextcloud.local/login
```

```text
HTTP/2 200 
server: nginx/1.22.1
date: Thu, 08 Oct 2026 12:48:05 GMT
content-type: text/html; charset=UTF-8
content-length: 18261
vary: Accept-Encoding
set-cookie: oc_sessionPassphrase=n2rl7MCWBJiAYQxARVug4nnGzync7Edk3Sb21w8wCZa1rmOmntDqYHMSNEfKuIjeDCwV9jrx1hrbp2Jl29RXnKpmIV5N%2BKGaPSMkgtKZIgPTPGUuqo8jXr4YITAoKGXI; path=/; secure; HttpOnly; SameSite=
set-cookie: __Host-nc_sameSiteCookielax=true; path=/; httponly;secure; expires=Fri, 31-Dec-2100 23:59:59 GMT; SameSite=lax
set-cookie: __Host-nc_sameSiteCookiestrict=true; path=/; httponly;secure; expires=Fri, 31-Dec-2100 23:59:59 GMT; SameSite=strict
set-cookie: ocsirtls87x9=n73k0ci4mdhsgevhoasl2schvp; path=/; secure; HttpOnly; SameSite=Lax
x-request-id: 7t9geE1lXjbKrU1bNQTz
cache-control: no-cache, no-store, must-revalidate
content-security-policy: default-src 'none';base-uri 'none';manifest-src 'self';script-src 'nonce-PgWVcRUQfyBUi9muB0PPGhdka7bIgaCxqwG2dPlSW6A=';script-src-elem 'strict-dynamic' 'nonce-PgWVcRUQfyBUi9mu
feature-policy: autoplay 'self';camera 'none';fullscreen 'self';geolocation 'none';microphone 'none';payment 'none'
x-robots-tag: noindex, nofollow
referrer-policy: no-referrer
x-content-type-options: nosniff
x-frame-options: SAMEORIGIN
x-robots-tag: noindex, nofollow

```

### 17. Le provider OIDC Keycloak est déclaré dans Nextcloud

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

### 18. Le bouton de connexion renvoie vers Keycloak

- **On attend** : redirection vers l'endpoint d'authentification du realm
- **Verdict** : ✅ OK

```bash
curl -sI https://nextcloud.local/apps/user_oidc/login/1
```

```text
HTTP/2 303 
server: nginx/1.22.1
date: Thu, 08 Oct 2026 12:48:05 GMT
content-type: text/html; charset=UTF-8
content-length: 0
location: https://keycloak.local/realms/sae/protocol/openid-connect/auth?client_id=nextcloud&response_type=code&scope=openid+email+profile&redirect_uri=https%3A%2F%2Fnextcloud.local%2Fapps%2Fuser_oidc
set-cookie: oc_sessionPassphrase=JedjsaaSjTzxTZkf4gnhY5BajxS3MOEp%2FgQaQlKiPOaBUbZE3jK9EHx5Dq%2FpoB%2BzidCR2omZQD4DempNT6I9PSUaFRjmSYqC3NZyQPKJlr7I6iXyhpcUJEe9FeE1Z6Dg; path=/; secure; HttpOnly; SameS
set-cookie: __Host-nc_sameSiteCookielax=true; path=/; httponly;secure; expires=Fri, 31-Dec-2100 23:59:59 GMT; SameSite=lax
set-cookie: __Host-nc_sameSiteCookiestrict=true; path=/; httponly;secure; expires=Fri, 31-Dec-2100 23:59:59 GMT; SameSite=strict
set-cookie: ocsirtls87x9=h9nq2kgd2fvs40t6ttp26k8n3j; path=/; secure; HttpOnly; SameSite=Lax
x-request-id: hmlHE5ipCvc2kogPiiBh
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

### 19. Le backend Lstu répond directement (sans nginx)

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
Date: Thu, 08 Oct 2026 12:48:05 GMT
Server: Mojolicious (Perl)
Set-Cookie: mojolicious=eyJjc3JmX3Rva2VuIjoiMDhlMGYzYjk1MWVhODIzZTBhZmFmODcwNWViYmQwY2MxNDQyMGZlYSIsImV4cGlyZXMiOjE3OTE0NjcyODV9WlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpa
Vary: Accept-Encoding
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
X-XSS-Protection: 1; mode=block

```

### 20. Page protégée sans cookie : /

- **On attend** : `302` (redirection vers la connexion), jamais le contenu de Lstu
- **Verdict** : ✅ OK

```bash
curl -o /dev/null -w 'http=%{http_code} location=%{redirect_url}\n' https://lstu.local/
```

```text
http=302 location=https://keycloak.local/realms/sae/protocol/openid-connect/auth?approval_prompt=force&client_id=lstu&code_challenge=_vsAu2OSQjB4NCAlIyBvHtoOMozBAbcgaw-iUh2YANw&code_challenge_method=S
```

### 21. Page protégée sans cookie : /stats

- **On attend** : `302` (redirection vers la connexion), jamais le contenu de Lstu
- **Verdict** : ✅ OK

```bash
curl -o /dev/null -w 'http=%{http_code} location=%{redirect_url}\n' https://lstu.local/stats
```

```text
http=302 location=https://keycloak.local/realms/sae/protocol/openid-connect/auth?approval_prompt=force&client_id=lstu&code_challenge=oVGfN_WK2_NFaLqvD-kwMB1cZJjPiWaqXNyltA-SFWw&code_challenge_method=S
```

### 22. Page protégée sans cookie : /fullstats

- **On attend** : `302` (redirection vers la connexion), jamais le contenu de Lstu
- **Verdict** : ✅ OK

```bash
curl -o /dev/null -w 'http=%{http_code} location=%{redirect_url}\n' https://lstu.local/fullstats
```

```text
http=302 location=https://keycloak.local/realms/sae/protocol/openid-connect/auth?approval_prompt=force&client_id=lstu&code_challenge=uHAA6l3GiRfFhXOqFmSeVUspSYDzd7U58kM-pC5lWWs&code_challenge_method=S
```

### 23. Page protégée sans cookie : /a

- **On attend** : `302` (redirection vers la connexion), jamais le contenu de Lstu
- **Verdict** : ✅ OK

```bash
curl -o /dev/null -w 'http=%{http_code} location=%{redirect_url}\n' https://lstu.local/a
```

```text
http=302 location=https://keycloak.local/realms/sae/protocol/openid-connect/auth?approval_prompt=force&client_id=lstu&code_challenge=HVt6KkCvOA0kpM6ow-5Sx7-t_BspDQlznYBvKTzNV-Y&code_challenge_method=S
```

### 24. Ajout d'une URL refusé sans authentification

- **On attend** : `302`, `401` ou `403` (le lien n'est pas créé)
- **Verdict** : ✅ OK

```bash
curl -o /dev/null -w 'http=%{http_code}\n' -d 'lsturl=https://refuse.example&format=json' https://lstu.local/a
```

```text
http=302
```

### 25. OAuth2 Proxy redirige vers Keycloak

- **On attend** : `302` avec `location` vers keycloak.local
- **Verdict** : ✅ OK

```bash
curl -sI https://lstu.local/oauth2/start
```

```text
HTTP/2 302 
server: nginx/1.22.1
date: Thu, 08 Oct 2026 12:48:05 GMT
content-type: text/html; charset=utf-8
cache-control: no-cache, no-store, must-revalidate, max-age=0
expires: Thu, 01 Jan 1970 00:00:00 UTC
location: https://keycloak.local/realms/sae/protocol/openid-connect/auth?approval_prompt=force&client_id=lstu&code_challenge=sGEoe4KaD2OPsXjixrAOMJcEW-9nn5GaJlb9VC5EGXU&code_challenge_method=S256&redi
set-cookie: _oauth2_proxy_csrf=XFxcepBjHe_Qxisx7-gCKMMHrJ6LMYgszNvRSCp2JmkTVxudL5R7ymAhI20tjO6SHhaCN6QIsoDAv0NRxEw-AKcAN-0ThvNqjD72cXCIES5sWNkyLndbtxPLmHlo3Hs4vH5gpKWa1m-B1RT3Mj9fY6rCEIE75ZCDpqb1n5xJu

```

### 26. favicon.ico est servi localement par nginx

- **On attend** : `204`
- **Verdict** : ✅ OK

```bash
curl -o /dev/null -w 'http=%{http_code}\n' https://lstu.local/favicon.ico
```

```text
http=204
```

## 7. Lstu : les URL raccourcies sont publiques

### 27. Création d'un lien court directement sur le backend

- **On attend** : un JSON contenant la clé `short`
- **Verdict** : ✅ OK

```bash
docker exec debian-admin-web-prj curl -s -d "lsturl=https://example.org&format=json" http://127.0.0.1:8080/a
```

```text
{"qrcode":"iVBORw0KGgoAAAANSUhEUgAAAGMAAABjAQAAAACnQIM4AAAA6klEQVQ4jc3UOw7DIAwGYEcZGHMB\nJK7BliuFC4T0BFyJjWsgcYF4Y0B13UZ9LImjDlXZPiTkH2MB9Lngj7UCuEQYoZOE1HwCzxuiop7H\nHhO4E\/IpDydFhs6I2mxZr2S7etxPu8\/
```

### 28. Le code court fait 8 caractères

- **On attend** : `8` (c'est ce que suppose la regex publique de nginx)
- **Verdict** : ❌ KO

```bash
printf %s "$SHORT" | wc -c
```

```text
33
```

### 29. Visiter le lien court SANS être authentifié

- **On attend** : redirection `30x` vers https://example.org
- **Verdict** : ❌ KO

```bash
curl -o /dev/null -w "http=%{http_code} location=%{redirect_url}\n" https://lstu.local/$SHORT
```

```text
http=302 location=https://keycloak.local/realms/sae/protocol/openid-connect/auth?approval_prompt=force&client_id=lstu&code_challenge=VffdLZDGKG3sHhNKv7S5utCUJZD8aogrRw4lnz6_R8Q&code_challenge_method=S
```

## 8. Parcours complets avec connexion (OIDC)

### 30. Connexion à Lstu via OAuth2 Proxy puis Keycloak puis LDAP

- **On attend** : arrivée sur https://lstu.local/ avec `status=200`
- **Verdict** : ✅ OK

```bash
kc_login "$JAR1" https://lstu.local/ "$TEST_USER" "$TEST_PW"
```

```text
status=200 final_url=https://lstu.local/
```

### 31. Ajout d'un lien une fois authentifié

- **On attend** : un JSON contenant la clé `short`
- **Verdict** : ✅ OK

```bash
curl -s -b "$JAR1" -d "lsturl=https://example.org/protege&format=json" https://lstu.local/a
```

```text
{"qrcode":"iVBORw0KGgoAAAANSUhEUgAAAGMAAABjAQAAAACnQIM4AAAA8ElEQVQ4jc3UMY7DIBAF0IlcuNtc\nAIlr0PlKywUgvkB8pem4hiUu4Oko0M6OpXiTBg\/aIgqVX4H480EGfl3wwdoAfDER4aKJuIYxU5IP\nTWhiGuYEvkcMvk\/BrV3iGhPEZ7Km9vm
```

### 32. Un mauvais mot de passe est refusé par Keycloak

- **On attend** : le message `Invalid username or password`
- **Verdict** : ✅ OK

```bash
kc_login "$JAR3" https://lstu.local/ "$TEST_USER" "mauvais-mot-de-passe"
```

```text
status=200 final_url=https://keycloak.local/realms/sae/login-actions/authenticate?session_code=6SxrzKERqJwGTl3KUMQ9Xig4iwYc0jTExa0uN7XaC7c&execution=ea0821e3-1950-4364-9ebb-74cc0b078a90&client_id=lstu
keycloak: Invalid username or password
```

### 33. Connexion à Nextcloud via Keycloak

- **On attend** : arrivée sur https://nextcloud.local/ avec `status=200`
- **Verdict** : ✅ OK

```bash
kc_login "$JAR2" https://nextcloud.local/apps/user_oidc/login/1 "$TEST_USER" "$TEST_PW"
```

```text
status=200 final_url=https://nextcloud.local/apps/dashboard/
```

### 34. La session Nextcloud appartient bien à l'utilisateur LDAP

- **On attend** : l'API OCS renvoie `"id":"jdoe"`
- **Verdict** : ✅ OK

```bash
curl -s -b "$JAR2" -H "OCS-APIRequest: true" "https://nextcloud.local/ocs/v2.php/cloud/user?format=json"
```

```text
{"ocs":{"meta":{"status":"ok","statuscode":200,"message":"OK"},"data":{"enabled":true,"id":"jdoe","firstLoginTimestamp":1791462155,"lastLoginTimestamp":1791463686,"lastLogin":1791463686000,"backend":"
```

