# Tests de l'infrastructure

_Généré le 16/11/2026 à 10:02 par `tests/run-tests.sh`._

**Bilan : 51 tests réussis, 2 échoués, sur 53.**

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
Date: Mon, 16 Nov 2026 09:02:36 GMT
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
Date: Mon, 16 Nov 2026 09:02:36 GMT
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
Date: Mon, 16 Nov 2026 09:02:36 GMT
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
date: Mon, 16 Nov 2026 09:02:37 GMT
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
[{"id":"kiwB3_UjT0iQcvEXIN4PCg","name":"openldap","providerId":"ldap","providerType":"org.keycloak.storage.UserStorageProvider","parentId":"f22010fb-100e-4144-ac2e-85b9cd18e803","config":{"fullSyncPer
```

### 19. Keycloak voit les utilisateurs de l'annuaire LDAP

- **On attend** : l'utilisateur jdoe est trouvé via la fédération
- **Verdict** : ✅ OK

```bash
curl -s -H "Authorization: Bearer $KC_TOKEN" "https://keycloak.local/admin/realms/$REALM/users?search=$TEST_USER"
```

```text
[{"id":"0f8b8d2b-b080-4871-8b27-9d48de36ba42","username":"jdoe","firstName":"John","lastName":"Doe","email":"jdoe@iutnc-crochet-fisson.local","emailVerified":true,"attributes":{"LDAP_ENTRY_DN":["uid=j
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
date: Mon, 16 Nov 2026 09:02:37 GMT
content-type: text/html; charset=UTF-8
content-length: 18274
vary: Accept-Encoding
set-cookie: oc9snx6dcy6s=s5nfv6f5r2phb3cnr95ibqjdtp; path=/; secure; HttpOnly; SameSite=Lax
set-cookie: oc_sessionPassphrase=y2HDw7BMnqHX9WL9G6D57MXr21UalijGQY1iL1UmoiEETnYBdg54B5CU9pv4OjIwei%2BCef%2BrmSPLgEe%2FJ2qotzWD2a%2BWmRR%2FpFrfbuOftnZbNSMTa%2FyFVHCgjwcuMjX9; path=/; secure; HttpOnly;
set-cookie: __Host-nc_sameSiteCookielax=true; path=/; httponly;secure; expires=Fri, 31-Dec-2100 23:59:59 GMT; SameSite=lax
set-cookie: __Host-nc_sameSiteCookiestrict=true; path=/; httponly;secure; expires=Fri, 31-Dec-2100 23:59:59 GMT; SameSite=strict
x-request-id: ARK4NlaiJblfjEK2wu3z
cache-control: no-cache, no-store, must-revalidate
content-security-policy: default-src 'none';base-uri 'none';manifest-src 'self';script-src 'nonce-Co77330dGj4FuIJQ0tFfB39ZPdN9qgyXkwCeCIneF3Q=';script-src-elem 'strict-dynamic' 'nonce-Co77330dGj4FuIJQ
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
date: Mon, 16 Nov 2026 09:02:37 GMT
content-type: text/html; charset=UTF-8
content-length: 0
location: https://keycloak.local/realms/sae/protocol/openid-connect/auth?client_id=nextcloud&response_type=code&scope=openid+email+profile&redirect_uri=https%3A%2F%2Fnextcloud.local%2Fapps%2Fuser_oidc
set-cookie: oc9snx6dcy6s=47fagiohvtisi03dkifkbhu32n; path=/; secure; HttpOnly; SameSite=Lax
set-cookie: oc_sessionPassphrase=Lun%2BqcpFOp0braJRH6iRD2TjTsqVAHSBe06ANkQPgwjR2mQbleXasRZyKoH0p8YyHhENZjppeTeAZAnaTyP9J6wl1n1BU93TsTpyWcaGoQmqwJVwktziU%2FM2TgLVgEL8; path=/; secure; HttpOnly; SameSit
set-cookie: __Host-nc_sameSiteCookielax=true; path=/; httponly;secure; expires=Fri, 31-Dec-2100 23:59:59 GMT; SameSite=lax
set-cookie: __Host-nc_sameSiteCookiestrict=true; path=/; httponly;secure; expires=Fri, 31-Dec-2100 23:59:59 GMT; SameSite=strict
x-request-id: T8iRWMUQGG2aPMbb3chO
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
Date: Mon, 16 Nov 2026 09:02:37 GMT
Server: Mojolicious (Perl)
Set-Cookie: mojolicious=eyJjc3JmX3Rva2VuIjoiODRmMjQ2OGM4NDczOTA4Njc0MmQ5MDMzMWNlMzgwN2MzYmIyZTI2MiIsImV4cGlyZXMiOjE3OTQ4MjMzNTd9WlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpaWlpa
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
http=302 location=https://keycloak.local/realms/sae/protocol/openid-connect/auth?approval_prompt=force&client_id=lstu&code_challenge=-XJ0XrJf-ZAcVhlpZu08X49JpnvdZYSNZJGVQ9mwkiE&code_challenge_method=S
```

### 26. Page protégée sans cookie : /stats

- **On attend** : `302` (redirection vers la connexion), jamais le contenu de Lstu
- **Verdict** : ✅ OK

```bash
curl -o /dev/null -w 'http=%{http_code} location=%{redirect_url}\n' https://lstu.local/stats
```

```text
http=302 location=https://keycloak.local/realms/sae/protocol/openid-connect/auth?approval_prompt=force&client_id=lstu&code_challenge=Xl4QZ6AbH-vCISQj2dJaLd3hXrSkv8w_hYsln2Tps-U&code_challenge_method=S
```

### 27. Page protégée sans cookie : /fullstats

- **On attend** : `302` (redirection vers la connexion), jamais le contenu de Lstu
- **Verdict** : ✅ OK

```bash
curl -o /dev/null -w 'http=%{http_code} location=%{redirect_url}\n' https://lstu.local/fullstats
```

```text
http=302 location=https://keycloak.local/realms/sae/protocol/openid-connect/auth?approval_prompt=force&client_id=lstu&code_challenge=fS3sKmqw159927YOI1GlgPuttGtKM66ClFsnYsTkLR0&code_challenge_method=S
```

### 28. Page protégée sans cookie : /a

- **On attend** : `302` (redirection vers la connexion), jamais le contenu de Lstu
- **Verdict** : ✅ OK

```bash
curl -o /dev/null -w 'http=%{http_code} location=%{redirect_url}\n' https://lstu.local/a
```

```text
http=302 location=https://keycloak.local/realms/sae/protocol/openid-connect/auth?approval_prompt=force&client_id=lstu&code_challenge=JzxXumRU7tBxayXAd94ms8aEkWaYja6w4_Xu_cR4Adc&code_challenge_method=S
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
date: Mon, 16 Nov 2026 09:02:38 GMT
content-type: text/html; charset=utf-8
cache-control: no-cache, no-store, must-revalidate, max-age=0
expires: Thu, 01 Jan 1970 00:00:00 UTC
location: https://keycloak.local/realms/sae/protocol/openid-connect/auth?approval_prompt=force&client_id=lstu&code_challenge=8NPBJfPPNq_DlGY3v8KIsL0xRsWCKVYrAvjq8vi2DQw&code_challenge_method=S256&redi
set-cookie: _oauth2_proxy_csrf=8BxgV04Nj8SaPK2usiy5oB0GZ5kDExU7z1nHwhFnsxO5eSmhmDBilZ9PNpUJyCAmvZ1ysxpQfW61Y1xjY12yRBBPkFo0fqumY0Qw2ht4l9lI4raSPgLKtbUXFWsUmgWi6GFR8unAIZaj09DiIxacB-AH2lsZHuIYiXrRtGn8g

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
{"qrcode":"iVBORw0KGgoAAAANSUhEUgAAAGMAAABjAQAAAACnQIM4AAAA7klEQVQ4jc3UMa6DMAwGYCOGbOUC\nlnKNbFyJXADoCXKlbLlGpFwg3hii+rmv7etbwOgNT\/UCH1KU3yYA\/Lvgg1UBJmCK0GkibkvKS5Ib\nTRFn6CmBPyFZN5zUxnxG3GYn+km2K+n
```

### 36. Le code court fait 8 caractères

- **On attend** : `8` (c'est ce que suppose la regex publique de nginx)
- **Verdict** : ❌ KO

```bash
printf %s "$SHORT" | wc -c
```

```text
33
```

### 37. Visiter le lien court SANS être authentifié

- **On attend** : redirection `30x` vers https://example.org
- **Verdict** : ❌ KO

```bash
curl -o /dev/null -w "http=%{http_code} location=%{redirect_url}\n" https://lstu.local/$SHORT
```

```text
http=302 location=https://keycloak.local/realms/sae/protocol/openid-connect/auth?approval_prompt=force&client_id=lstu&code_challenge=7zBEu4qWZMiVZOL-FN6zlo12m1jk4cRSASPKxP-ZO90&code_challenge_method=S
```

## 8. Parcours complets avec connexion (OIDC)

### 38. Connexion à Lstu via OAuth2 Proxy puis Keycloak puis LDAP

- **On attend** : arrivée sur https://lstu.local/ avec `status=200`
- **Verdict** : ✅ OK

```bash
kc_login "$JAR1" https://lstu.local/ "$TEST_USER" "$TEST_PW"
```

```text
status=200 final_url=https://lstu.local/
```

### 39. Ajout d'un lien une fois authentifié

- **On attend** : un JSON contenant la clé `short`
- **Verdict** : ✅ OK

```bash
curl -s -b "$JAR1" -d "lsturl=https://example.org/protege&format=json" https://lstu.local/a
```

```text
{"qrcode":"iVBORw0KGgoAAAANSUhEUgAAAGMAAABjAQAAAACnQIM4AAAA50lEQVQ4jc3UMa7DIAwGYFcM2doL\nIHENNq4UX+ARLtBeiY1rRMoFwpYB9X+m0lOzRI7eUNWTP6bfYEHYF32xVqK42Zjpoqmi\/QyNizSa\nso1wj0J8QgzicxrDUs8ILW60S3YomY+L
```

### 40. Un mauvais mot de passe est refusé par Keycloak

- **On attend** : le message `Invalid username or password`
- **Verdict** : ✅ OK

```bash
kc_login "$JAR3" https://lstu.local/ "$TEST_USER" "mauvais-mot-de-passe"
```

```text
status=200 final_url=https://keycloak.local/realms/sae/login-actions/authenticate?session_code=9FWNrKTzm55QLfhyqivUgEAM16h6Tp0iYkj8VKks8-Y&execution=61f56f70-af3a-4b09-934c-6bc8e9214e6b&client_id=lstu
keycloak: Invalid username or password
```

### 41. Connexion à Nextcloud via Keycloak

- **On attend** : arrivée sur https://nextcloud.local/ avec `status=200`
- **Verdict** : ✅ OK

```bash
kc_login "$JAR2" https://nextcloud.local/apps/user_oidc/login/1 "$TEST_USER" "$TEST_PW"
```

```text
status=200 final_url=https://nextcloud.local/apps/dashboard/
```

### 42. La session Nextcloud appartient bien à l'utilisateur LDAP

- **On attend** : l'API OCS renvoie `"id":"jdoe"`
- **Verdict** : ✅ OK

```bash
curl -s -b "$JAR2" -H "OCS-APIRequest: true" "https://nextcloud.local/ocs/v2.php/cloud/user?format=json"
```

```text
{"ocs":{"meta":{"status":"ok","statuscode":200,"message":"OK"},"data":{"enabled":true,"id":"jdoe","firstLoginTimestamp":1794819726,"lastLoginTimestamp":1794819726,"lastLogin":1794819726000,"backend":"
```

### 43. Un utilisateur absent de l'annuaire est refusé (Nextcloud)

- **On attend** : `Invalid username or password`
- **Verdict** : ✅ OK

```bash
kc_login "$JAR4" https://nextcloud.local/apps/user_oidc/login/1 "inconnu" "password"
```

```text
status=200 final_url=https://keycloak.local/realms/sae/login-actions/authenticate?session_code=BDuYVS4cDM7A7SNsBPzVBWi7W4ZzEVNYwn-SrMr4wvw&execution=61f56f70-af3a-4b09-934c-6bc8e9214e6b&client_id=next
keycloak: Invalid username or password
```

### 44. Un mauvais mot de passe est refusé (Nextcloud)

- **On attend** : `Invalid username or password`
- **Verdict** : ✅ OK

```bash
kc_login "$JAR6" https://nextcloud.local/apps/user_oidc/login/1 "$TEST_USER" "mauvais-mot-de-passe"
```

```text
status=200 final_url=https://keycloak.local/realms/sae/login-actions/authenticate?session_code=hCqkdC2nr1EgPeIGVSCbHkddbrjbVTqR5O8OYP3abpE&execution=61f56f70-af3a-4b09-934c-6bc8e9214e6b&client_id=next
keycloak: Invalid username or password
```

### 45. Un second utilisateur LDAP (asmith) se connecte à Nextcloud

- **On attend** : arrivée sur Nextcloud avec `status=200`
- **Verdict** : ✅ OK

```bash
kc_login "$JAR5" https://nextcloud.local/apps/user_oidc/login/1 asmith "$TEST_PW"
```

```text
status=200 final_url=https://nextcloud.local/apps/dashboard/
```

### 46. La session Nextcloud d'asmith est bien celle d'asmith

- **On attend** : l'API OCS renvoie `"id":"asmith"`
- **Verdict** : ✅ OK

```bash
curl -s -b "$JAR5" -H "OCS-APIRequest: true" "https://nextcloud.local/ocs/v2.php/cloud/user?format=json"
```

```text
{"ocs":{"meta":{"status":"ok","statuscode":200,"message":"OK"},"data":{"enabled":true,"id":"asmith","firstLoginTimestamp":1794819728,"lastLoginTimestamp":1794819728,"lastLogin":1794819728000,"backend"
```

## 9. Installation conforme au sujet

### 47. OpenLDAP, nginx, MariaDB et PHP viennent de paquets Debian

- **On attend** : `4` paquets au statut installé
- **Verdict** : ✅ OK

```bash
docker exec debian-admin-web-prj dpkg -l slapd nginx mariadb-server php8.3-fpm | grep -c ^ii
```

```text
4
```

### 48. Nextcloud, Keycloak, Lstu et OAuth2 Proxy ne viennent PAS de paquets Debian

- **On attend** : `0` paquet : ils sont installés depuis les sources officielles
- **Verdict** : ✅ OK

```bash
docker exec debian-admin-web-prj dpkg -l nextcloud keycloak lstu oauth2-proxy 2>&1 | grep -c ^ii
```

```text
0
```

### 49. Nextcloud : archive officielle en place

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

### 50. Keycloak : archive officielle dans /opt/keycloak

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

### 51. Lstu : dépôt officiel cloné depuis framagit

- **On attend** : l'URL du dépôt `origin`
- **Verdict** : ✅ OK

```bash
docker exec debian-admin-web-prj runuser -u lstu -- git -C /opt/lstu remote get-url origin
```

```text
https://framagit.org/fiat-tux/hat-softwares/lstu.git
```

### 52. OAuth2 Proxy : binaire de la release officielle

- **On attend** : une version `v7.x`
- **Verdict** : ✅ OK

```bash
docker exec debian-admin-web-prj /usr/local/bin/oauth2-proxy --version
```

```text
oauth2-proxy v7.12.0 (built with go1.24.6)
```

## 10. Livrables

### 53. Les documents demandés existent et ne sont pas vides

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

