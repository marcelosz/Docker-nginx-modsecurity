# Docker-nginx-modsecurity

TODO
- Add instructions for OWASP CRS mod_security rules enablement.

Run:
$ docker run -d -p 80:80 -p 443:443 --name=nginx-modsecurity --restart=unless-stopped -v nginx-modsecurity_cfg:/etc/nginx -v nginx-modsecurity_log:/var/log/nginx marcelosz/nginx-modsecurity