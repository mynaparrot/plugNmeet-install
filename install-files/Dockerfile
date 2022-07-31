FROM haproxy:2.6

USER root

RUN export DEBIAN_FRONTEND=noninteractive; \
    apt update && \
    apt install --no-install-recommends -y libcap2-bin wget && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*

RUN setcap 'cap_net_bind_service=+ep' /usr/local/sbin/haproxy

USER haproxy
