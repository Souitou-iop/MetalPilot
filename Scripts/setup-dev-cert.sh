#!/bin/bash
set -euo pipefail

CERT_NAME="${1:-MacGameToolbox Dev}"
KEYCHAIN="${KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

echo "==> 正在检查本地钥匙串中是否存在证书: $CERT_NAME..."
if security find-certificate -c "$CERT_NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "==> 已存在证书: $CERT_NAME"
else
    echo "==> 正在创建本地自签名代码签名证书: $CERT_NAME..."
    TMPDIR=$(mktemp -d)
    trap 'rm -rf "$TMPDIR"' EXIT

    cat << EOF > "$TMPDIR/cert.cnf"
[ req ]
default_bits        = 2048
distinguished_name  = req_distinguished_name
prompt              = no
x509_extensions     = v3_req

[ req_distinguished_name ]
CN                  = $CERT_NAME

[ v3_req ]
keyUsage            = critical, digitalSignature
extendedKeyUsage    = critical, codeSigning
basicConstraints    = critical, CA:FALSE
EOF

    openssl req -new -x509 -newkey rsa:2048 -nodes -days 3650 \
      -keyout "$TMPDIR/dev_cert.key" \
      -out "$TMPDIR/dev_cert.crt" \
      -config "$TMPDIR/cert.cnf" >/dev/null 2>&1

    openssl pkcs12 -export -out "$TMPDIR/dev_cert.p12" \
      -inkey "$TMPDIR/dev_cert.key" \
      -in "$TMPDIR/dev_cert.crt" \
      -passout pass:metalpilot >/dev/null 2>&1

    security import "$TMPDIR/dev_cert.p12" -k "$KEYCHAIN" -P metalpilot -T /usr/bin/codesign -T /usr/bin/security >/dev/null 2>&1
    security add-trusted-cert -d -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMPDIR/dev_cert.crt" >/dev/null 2>&1
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" "$KEYCHAIN" >/dev/null 2>&1
fi

echo "==> 当前有效的代码签名证书列表："
security find-identity -v -p codesigning
echo "==> 配置完成！后续本地构建将自动使用该证书进行持久签名，权限将不再随构建丢失。"
