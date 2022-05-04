#!/bin/sh

hb_generate_auth_token() {
  secret=$1
  header=$(printf '{"alg":"HS256","typ":"JWT"}' | openssl base64 -e -A | sed s/\+/-/g | sed -E s/=+$// | sed 's/\//_/g')
  payload=$(printf '{"username":"homebridge-macos-pkg","name":"homebridge-macos-pkg","admin":true,"instanceId":"xxxxxxxx"}' | openssl base64 -e -A | sed s/\+/-/g | sed -E s/=+$// | sed 's/\//_/g')
  signature=$(printf "${header}.${payload}" | openssl dgst -sha256 -hmac $secret -binary | openssl base64 -e -A | sed s/\+/-/g | sed -E s/=+$// | sed 's/\//_/g')
  token="${header}.${payload}.${signature}"
  echo $token;
}

export -f hb_generate_auth_token
