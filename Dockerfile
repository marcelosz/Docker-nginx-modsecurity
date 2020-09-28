#
# Dockerfile to build a container with nginx, ModSecurity and certbot
#

#
# Build modsecurity
#
FROM ubuntu:18.04 as modsecurity-build
ARG MODSECURITY_TAG
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update -qq && \
    apt install  -qq -y --no-install-recommends --no-install-suggests \
    ca-certificates      \
    automake             \
    autoconf             \
    build-essential      \
    libcurl4-openssl-dev \
    libpcre++-dev        \
    libtool              \
    libxml2-dev          \
    libyajl-dev          \
    lua5.2-dev           \
    git                  \
    pkgconf              \
    ssdeep               \
    libgeoip-dev         \
    wget             &&  \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN cd /opt && \
    git clone --branch ${MODSECURITY_TAG} --depth 1  https://github.com/SpiderLabs/ModSecurity && \
    #git clone --depth 1 -b v3/master --single-branch https://github.com/SpiderLabs/ModSecurity && \
    cd ModSecurity && \
    git submodule init && \
    git submodule update && \
    ./build.sh && \
    ./configure && \
    make && \
    make install

RUN strip /usr/local/modsecurity/bin/* /usr/local/modsecurity/lib/*.a /usr/local/modsecurity/lib/*.so*

#
# Build nginx
#
FROM ubuntu:18.04 AS nginx-build
ARG NGINX_VERSION
ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update -qq && \
apt install  -qq -y --no-install-recommends --no-install-suggests \
ca-certificates \
autoconf        \
automake        \
build-essential \
libtool         \
pkgconf         \
wget            \
git             \
zlib1g-dev      \
libssl-dev      \
libpcre3-dev    \
libxml2-dev     \
libyajl-dev     \
lua5.2-dev      \
libgeoip-dev    \
libcurl4-openssl-dev    \
openssl

RUN cd /opt && \
git clone --depth 1 https://github.com/SpiderLabs/ModSecurity-nginx.git

COPY --from=modsecurity-build /usr/local/modsecurity/ /usr/local/modsecurity/

RUN wget -q -P /opt https://nginx.org/download/nginx-"$NGINX_VERSION".tar.gz
RUN tar xvzf /opt/nginx-"$NGINX_VERSION".tar.gz -C /opt

RUN cd /opt/nginx-"$NGINX_VERSION" && \
./configure \
        --prefix=/usr/local/nginx \
        --sbin-path=/usr/local/nginx/nginx \
        --modules-path=/usr/local/nginx/modules \
        --conf-path=/etc/nginx/nginx.conf \
        --error-log-path=/var/log/nginx/error.log \
        --http-log-path=/var/log/nginx/access.log \
        --pid-path=/run/nginx.pid \
        --lock-path=/var/lock/nginx.lock \
        --user=www-data \
        --group=www-data \
        --with-pcre-jit \
        --with-file-aio \
        --with-threads \
        --with-http_addition_module \
        --with-http_auth_request_module \
        --with-http_flv_module \
        --with-http_gunzip_module \
        --with-http_gzip_static_module \
        --with-http_mp4_module \
        --with-http_random_index_module \
        --with-http_realip_module \
        --with-http_slice_module \
        --with-http_ssl_module \
        --with-http_sub_module \
        --with-http_stub_status_module \
        --with-http_v2_module \
        --with-http_secure_link_module \
        --with-stream \
        --with-stream_realip_module \
        --add-module=/opt/ModSecurity-nginx \
        --with-cc-opt='-g -O2 -specs=/usr/share/dpkg/no-pie-compile.specs -fstack-protector-strong -Wformat -Werror=format-security -Wp,-D_FORTIFY_SOURCE=2 -fPIC' \
        --with-ld-opt='-specs=/usr/share/dpkg/no-pie-link.specs -Wl,-z,relro -Wl,-z,now -Wl,--as-needed -pie' \
        --with-http_dav_module

RUN cd /opt/nginx-"$NGINX_VERSION" && \
make && \
make install && \
make modules

RUN mkdir -p /var/log/nginx/
RUN touch /var/log/nginx/access.log
RUN touch /var/log/nginx/error.log

#
# Final image build
#
FROM ubuntu:18.04
ENV DEBIAN_FRONTEND noninteractive

RUN apt update && \
apt-get install --no-install-recommends --no-install-suggests -y \
ca-certificates \
libcurl4-openssl-dev  \
libyajl-dev \
lua5.2-dev \
libgeoip-dev \
vim \
libxml2 \
certbot
RUN apt clean && \
rm -rf /var/lib/apt/lists/*

COPY --from=modsecurity-build /usr/local/modsecurity/ /usr/local/modsecurity/
RUN ldconfig

COPY --from=nginx-build /usr/local/nginx/nginx /usr/local/nginx/nginx

COPY --from=nginx-build /etc/nginx /etc/nginx

COPY --from=nginx-build /usr/local/nginx/html /usr/local/nginx/html

RUN mkdir -p /var/log/nginx/
RUN touch /var/log/nginx/access.log
RUN touch /var/log/nginx/error.log

# Adjust nginx configuration files and folders
COPY samples/nginx.conf /etc/nginx/
RUN mkdir -p /etc/nginx/sites-available
COPY samples/default.conf /etc/nginx/sites-available/
COPY samples/secure.conf /etc/nginx/sites-available/
RUN mkdir -p /etc/nginx/sites-enabled
RUN ln -sf /etc/nginx/sites-available/default.conf /etc/nginx/sites-enabled/default.conf
RUN mkdir -p /etc/nginx/modsecurity.d
RUN echo "include /etc/nginx/modsecurity.d/modsecurity.conf" > /etc/nginx/modsecurity.d/include.conf
COPY --from=modsecurity-build /opt/ModSecurity/modsecurity.conf-recommended /etc/nginx/modsecurity.d
COPY --from=modsecurity-build /opt/ModSecurity/unicode.mapping /etc/nginx/modsecurity.d
RUN cd /etc/nginx/modsecurity.d && \
    mv modsecurity.conf-recommended modsecurity.conf

VOLUME /etc/nginx
VOLUME /var/log/nginx

EXPOSE 80 443

STOPSIGNAL SIGTERM

CMD ["/usr/local/nginx/nginx", "-g", "daemon off;"]
