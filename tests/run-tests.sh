#!/usr/bin/env bash
# Usage : bash tests/run-tests.sh   (le conteneur doit tourner)
cd "$(dirname "$0")/.." || exit 1

CT=debian-admin-web-prj
CA=ansible/certs/ca.crt
OUT=tests/compte_rendu/tests.md
BODY=$(mktemp)

# À garder synchronisé avec ansible/group_vars/all.yml
BASE="dc=iutnc-crochet-fisson,dc=local"
LDAPPW="ldap-admin-pw"
KC_ADMIN=admin
KC_ADMINPW="kc-admin-pw"
REALM=sae
TEST_USER=jdoe
TEST_PW=password

D="docker exec $CT"

# curl avec notre CA et résolution forcée vers 127.0.0.1
cu() {
  curl -sS --max-time 30 --cacert "$CA" \
    --resolve nextcloud.local:443:127.0.0.1 \
    --resolve keycloak.local:443:127.0.0.1 \
    --resolve lstu.local:443:127.0.0.1 \
    --resolve nextcloud.local:80:127.0.0.1 \
    --resolve keycloak.local:80:127.0.0.1 \
    --resolve lstu.local:80:127.0.0.1 "$@"
}

n=0
ok=0
ko=0
LAST_OUT=""

section() {
  printf '## %s\n\n' "$1" >>"$BODY"
  echo
  echo "== $1"
}

# t "titre" "résultat attendu" 'commande' 'regex qui doit matcher' ['regex qui ne doit PAS matcher']
t() {
  local title=$1 expect=$2 cmd=$3 must=$4 mustnot=${5:-}
  local full verdict shown
  n=$((n + 1))
  full=$(eval "$cmd" 2>&1)
  LAST_OUT=$full

  verdict="✅ OK"
  grep -qiE -- "$must" <<<"$full" || verdict="❌ KO"
  if [ -n "$mustnot" ] && grep -qiE -- "$mustnot" <<<"$full"; then verdict="❌ KO"; fi
  if [ "$verdict" = "✅ OK" ]; then ok=$((ok + 1)); else ko=$((ko + 1)); fi

  shown=${cmd//\$D/docker exec $CT}
  shown=${shown//cu /curl }

  {
    echo "### $n. $title"
    echo
    echo "- **On attend** : $expect"
    echo "- **Verdict** : $verdict"
    echo
    echo '```bash'
    printf '%s\n' "$shown"
    echo '```'
    echo
    echo '```text'
    printf '%s\n' "$full" | head -n 20 | cut -c1-200
    echo '```'
    echo
  } >>"$BODY"

  echo "$verdict  $n. $title"
}

# Connexion Keycloak scriptée : récupère le formulaire, poste identifiants, suit les redirections
kc_login() { # jar start_url user pass
  local jar=$1 url=$2 user=$3 pass=$4 page action
  page=$(cu -L -c "$jar" -b "$jar" "$url") || true
  action=$(tr '\n' ' ' <<<"$page" |
    grep -o 'action="[^"]*login-actions/authenticate[^"]*"' | head -1 |
    sed 's/^action="//; s/"$//; s/&amp;/\&/g')
  if [ -z "$action" ]; then
    echo "formulaire Keycloak introuvable"
    return
  fi
  cu -L -c "$jar" -b "$jar" -o /tmp/kc_body.html \
    -w 'status=%{http_code} final_url=%{url_effective}\n' \
    --data-urlencode "username=$user" --data-urlencode "password=$pass" "$action"
  grep -q 'Invalid username or password' /tmp/kc_body.html && echo "keycloak: Invalid username or password"
}

############################################################
section "1. Services système (dans le conteneur)"

t "Les 7 services sont actifs" \
  "7 lignes \`active\`" \
  '$D systemctl is-active slapd mariadb php8.3-fpm nginx keycloak lstu oauth2-proxy' \
  '^active$' 'inactive|failed|activating|unknown'

t "Le provisioning du premier démarrage a réussi" \
  "\`active\` (oneshot terminé)" \
  '$D systemctl is-active provision' \
  '^active$' 'failed|inactive'

############################################################
section "2. Annuaire OpenLDAP"

t "Les utilisateurs existent dans l'annuaire" \
  "l'entrée \`uid=jdoe\` avec son email" \
  '$D ldapsearch -x -LLL -H ldap://localhost -D "cn=admin,$BASE" -w "$LDAPPW" -b "ou=users,$BASE" uid mail' \
  "uid: $TEST_USER"

t "Le mot de passe de $TEST_USER est valide (hash correct)" \
  "\`ldapwhoami\` renvoie le DN de l'utilisateur" \
  '$D ldapwhoami -x -H ldap://localhost -D "uid=$TEST_USER,ou=users,$BASE" -w "$TEST_PW"' \
  "dn:uid=$TEST_USER" 'invalid|error'

############################################################
section "3. Nginx : redirections HTTP et certificats TLS"

for d in nextcloud.local keycloak.local lstu.local; do
  t "HTTP redirige vers HTTPS ($d)" \
    "\`301 Moved Permanently\` vers https://$d/" \
    "cu -sI http://$d/" \
    '301 Moved Permanently'

  t "Certificat valide pour $d (signé par notre CA)" \
    "\`ssl_verify_result=0\`" \
    "cu -o /dev/null -w 'ssl_verify_result=%{ssl_verify_result} http_code=%{http_code}\n' https://$d/" \
    'ssl_verify_result=0'
done

############################################################
section "4. Keycloak"

t "Le realm $REALM publie sa configuration OIDC" \
  "un JSON dont l'\`issuer\` est https://keycloak.local/realms/$REALM" \
  "cu -s https://keycloak.local/realms/$REALM/.well-known/openid-configuration" \
  "\"issuer\":\"https://keycloak.local/realms/$REALM\""

t "La console d'administration répond" \
  "\`200\` ou \`302\`" \
  'cu -sI https://keycloak.local/admin/' \
  'HTTP/2 (200|302)'

KC_TOKEN=$(cu -s -d grant_type=password -d client_id=admin-cli \
  -d "username=$KC_ADMIN" -d "password=$KC_ADMINPW" \
  https://keycloak.local/realms/master/protocol/openid-connect/token |
  sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')

t "La fédération LDAP est configurée dans le realm" \
  "un composant de type \`ldap\` (jeton admin obtenu via l'API, non affiché)" \
  'cu -s -H "Authorization: Bearer $KC_TOKEN" "https://keycloak.local/admin/realms/$REALM/components?type=org.keycloak.storage.UserStorageProvider"' \
  '"providerId":"ldap"'

t "Keycloak voit les utilisateurs de l'annuaire LDAP" \
  "l'utilisateur $TEST_USER est trouvé via la fédération" \
  'cu -s -H "Authorization: Bearer $KC_TOKEN" "https://keycloak.local/admin/realms/$REALM/users?search=$TEST_USER"' \
  "\"username\":\"$TEST_USER\""

############################################################
section "5. Nextcloud"

t "Nextcloud est installé" \
  "\`\"installed\":true\`" \
  'cu -s https://nextcloud.local/status.php' \
  '"installed":true'

t "La page de connexion répond" \
  "\`HTTP/2 200\`" \
  'cu -sI https://nextcloud.local/login' \
  'HTTP/2 200'

t "Le provider OIDC Keycloak est déclaré dans Nextcloud" \
  "un provider nommé \`keycloak\`" \
  '$D runuser -u www-data -- php /var/www/nextcloud/occ user_oidc:provider' \
  'keycloak'

t "Le bouton de connexion renvoie vers Keycloak" \
  "redirection vers l'endpoint d'authentification du realm" \
  'cu -sI https://nextcloud.local/apps/user_oidc/login/1' \
  "location: https://keycloak.local/realms/$REALM/protocol/openid-connect/auth"

############################################################
section "6. Lstu et OAuth2 Proxy : protection des pages"

t "Le backend Lstu répond directement (sans nginx)" \
  "\`HTTP/1.1 200\` sur 127.0.0.1:8080 dans le conteneur" \
  '$D curl -sI http://127.0.0.1:8080/' \
  'HTTP/1.1 200'

for p in / /stats /fullstats /a; do
  t "Page protégée sans cookie : $p" \
    "\`302\` (redirection vers la connexion), jamais le contenu de Lstu" \
    "cu -o /dev/null -w 'http=%{http_code} location=%{redirect_url}\n' https://lstu.local$p" \
    'http=302'
done

t "Ajout d'une URL refusé sans authentification" \
  "\`302\`, \`401\` ou \`403\` (le lien n'est pas créé)" \
  "cu -o /dev/null -w 'http=%{http_code}\n' -d 'lsturl=https://refuse.example&format=json' https://lstu.local/a" \
  'http=(302|401|403)'

t "OAuth2 Proxy redirige vers Keycloak" \
  "\`302\` avec \`location\` vers keycloak.local" \
  'cu -sI https://lstu.local/oauth2/start' \
  'location: https://keycloak.local/realms/'

t "favicon.ico est servi localement par nginx" \
  "\`204\`" \
  "cu -o /dev/null -w 'http=%{http_code}\n' https://lstu.local/favicon.ico" \
  'http=204'

############################################################
section "7. Lstu : les URL raccourcies sont publiques"

t "Création d'un lien court directement sur le backend" \
  "un JSON contenant la clé \`short\`" \
  '$D curl -s -d "lsturl=https://example.org&format=json" http://127.0.0.1:8080/a' \
  '"short"'
SHORT=$(sed -n 's/.*"short":"\([^"]*\)".*/\1/p' <<<"$LAST_OUT")

t "Le code court fait 8 caractères" \
  "\`8\` (c'est ce que suppose la regex publique de nginx)" \
  'printf %s "$SHORT" | wc -c' \
  '^8$'

t "Visiter le lien court SANS être authentifié" \
  "redirection \`30x\` vers https://example.org" \
  'cu -o /dev/null -w "http=%{http_code} location=%{redirect_url}\n" https://lstu.local/$SHORT' \
  'http=30[0-9] location=https://example.org'

############################################################
section "8. Parcours complets avec connexion (OIDC)"

JAR1=$(mktemp)
JAR2=$(mktemp)
JAR3=$(mktemp)

t "Connexion à Lstu via OAuth2 Proxy puis Keycloak puis LDAP" \
  "arrivée sur https://lstu.local/ avec \`status=200\`" \
  'kc_login "$JAR1" https://lstu.local/ "$TEST_USER" "$TEST_PW"' \
  'status=200 final_url=https://lstu.local/' 'status=5|introuvable|Invalid'

t "Ajout d'un lien une fois authentifié" \
  "un JSON contenant la clé \`short\`" \
  'cu -s -b "$JAR1" -d "lsturl=https://example.org/protege&format=json" https://lstu.local/a' \
  '"short"'

t "Un mauvais mot de passe est refusé par Keycloak" \
  "le message \`Invalid username or password\`" \
  'kc_login "$JAR3" https://lstu.local/ "$TEST_USER" "mauvais-mot-de-passe"' \
  'Invalid username or password'

t "Connexion à Nextcloud via Keycloak" \
  "arrivée sur https://nextcloud.local/ avec \`status=200\`" \
  'kc_login "$JAR2" https://nextcloud.local/apps/user_oidc/login/1 "$TEST_USER" "$TEST_PW"' \
  'status=200 final_url=https://nextcloud.local/' 'status=5|introuvable|Invalid'

t "La session Nextcloud appartient bien à l'utilisateur LDAP" \
  "l'API OCS renvoie \`\"id\":\"$TEST_USER\"\`" \
  'cu -s -b "$JAR2" -H "OCS-APIRequest: true" "https://nextcloud.local/ocs/v2.php/cloud/user?format=json"' \
  "\"id\":\"$TEST_USER\""

rm -f "$JAR1" "$JAR2" "$JAR3" /tmp/kc_body.html

############################################################
mkdir -p "$(dirname "$OUT")"
{
  echo "# Tests de l'infrastructure"
  echo
  echo "_Généré le $(date '+%d/%m/%Y à %H:%M') par \`tests/run-tests.sh\`._"
  echo
  echo "**Bilan : $ok tests réussis, $ko échoués, sur $n.**"
  echo
  echo "## Méthode"
  echo
  echo "Chaque test lance une commande (\`curl\` depuis l'hôte, ou une commande dans le conteneur"
  echo "via \`docker exec\`) et compare la réponse à un résultat attendu. Les \`curl\` utilisent"
  echo "\`--cacert ansible/certs/ca.crt\`, ce qui vérifie aussi la validité de nos certificats,"
  echo "et \`--resolve\` pour joindre les domaines \`*.local\` sans modifier \`/etc/hosts\`."
  echo "Les parcours de la section 8 rejouent une vraie connexion : formulaire Keycloak, envoi"
  echo "du mot de passe, puis suivi des redirections jusqu'à l'application."
  echo
  cat "$BODY"
} >"$OUT"
rm -f "$BODY"

echo
echo "Bilan : $ok OK / $ko KO sur $n  ->  $OUT"
[ "$ko" -eq 0 ]
