FROM alpine:edge AS builder
RUN  install -m 0644 -D /etc/apk/repositories /image/etc/apk/repositories
RUN  apk add --allow-untrusted --initdb --no-cache --root /image bash busybox tini
RUN  apk add --allow-untrusted --initdb --no-cache --root /image openssh-client
RUN  apk add --allow-untrusted --initdb --no-cache --root /image openssl
RUN  apk add --allow-untrusted --initdb --no-cache --root /image borgbackup
RUN  apk add --allow-untrusted --initdb --no-cache --root /image zstd
RUN  grep -e ^root -e ^nobody /etc/passwd | install -D -m 0644 /dev/stdin /image/etc/passwd
RUN  exec chroot /image /bin/sh -c 'exec pip3 uninstall -y pip'

FROM scratch
COPY --from=builder /image /
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
ENTRYPOINT ["docker-entrypoint.sh"]
