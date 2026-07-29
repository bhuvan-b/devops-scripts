#!/bin/bash
set -e

apt update
apt install -y git nodejs npm

cd /home/ubuntu

git clone https://github.com/bhuvan-b/framer-portfolio.git
cd framer-portfolio
git checkout app-v1

sudo chown ubuntu:ubuntu -R /home/ubuntu/framer-portfolio/
nohup node server.js > app.log 2>&1 &