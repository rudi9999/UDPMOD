#!/bin/bash

rm -rf $(pwd)/$0

read -p " ingresa tu dominio: " domain

apt update -y; apt upgrade -y; apt install git -y

git clone https://github.com/rudi9999/UDPMOD.git

dir=$(pwd)

OBFS=$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 8)

interfas=$(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1)

sys=$(which sysctl)

ip4t=$(which iptables)
ip6t=$(which ip6tables)

openssl genrsa -out ${dir}/UDPMOD/udpmod.ca.key 2048
openssl req -new -x509 -days 3650 -key ${dir}/UDPMOD/udpmod.ca.key -subj "/C=CN/ST=GD/L=SZ/O=Udpmod, Inc./CN=Udpmod Root CA" -out ${dir}/UDPMOD/udpmod.ca.crt
openssl req -newkey rsa:2048 -nodes -keyout ${dir}/UDPMOD/udpmod.server.key -subj "/C=CN/ST=GD/L=SZ/O=Udpmod, Inc./CN=${domain}" -out ${dir}/UDPMOD/udpmod.server.csr
openssl x509 -req -extfile <(printf "subjectAltName=DNS:${domain},DNS:${domain}") -days 3650 -in ${dir}/UDPMOD/udpmod.server.csr -CA ${dir}/UDPMOD/udpmod.ca.crt -CAkey ${dir}/UDPMOD/udpmod.ca.key -CAcreateserial -out ${dir}/UDPMOD/udpmod.server.crt

sed -i "s/setobfs/${OBFS}/" ${dir}/UDPMOD/config.json
sed -i "s#instDir#${dir}#g" ${dir}/UDPMOD/config.json
sed -i "s#instDir#${dir}#g" ${dir}/UDPMOD/udpmod.service
sed -i "s#iptb#${interfas}#g" ${dir}/UDPMOD/udpmod.service
sed -i "s#sysb#${sys}#g" ${dir}/UDPMOD/udpmod.service
sed -i "s#ip4tbin#${ip4t}#g" ${dir}/UDPMOD/udpmod.service
sed -i "s#ip6tbin#${ip6t}#g" ${dir}/UDPMOD/udpmod.service

chmod +x ${dir}/UDPMOD/*

install -Dm644 ${dir}/UDPMOD/udpmod.service /etc/systemd/system

systemctl daemon-reload
systemctl start udpmod
systemctl enable udpmod

echo " obfs: ${OBFS}" > ${dir}/UDPMOD/data
echo "port: 36712" >> ${dir}/UDPMOD/data
echo "rago de puertos: 10000:65000" >> ${dir}/UDPMOD/data
cat ${dir}/UDPMOD/data
