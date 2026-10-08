#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f ca.key ]; then
  openssl genrsa -out ca.key 4096
  openssl req -new -x509 -days 825 -key ca.key -out ca.crt \
    -subj "/C=FR/ST=CA/L=CA-DACS/O=CA-DACS/CN=CA-DACS.example.net"
fi

openssl genrsa -out server.key 4096
openssl req -new -key server.key -out server.csr \
  -subj "/C=FR/ST=Lorraine/L=Nancy/O=IUTNC/CN=nextcloud.local"

# Un seul certificat valable pour les 3 domaines (SAN)
cat >server.ext <<'EOF'
subjectAltName = DNS:nextcloud.local, DNS:keycloak.local, DNS:lstu.local
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
EOF

openssl x509 -req -CA ca.crt -CAkey ca.key -CAcreateserial -days 825 \
  -in server.csr -out server.crt -extfile server.ext
rm -f server.csr server.ext
echo "OK : ca.crt / server.crt / server.key générés"
