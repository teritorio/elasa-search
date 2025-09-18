FROM python:3.13-slim

ARG ADDOK_VERSION
ENV ADDOK_VERSION ${ADDOK_VERSION:-1.2.1}
ENV ADDOK_FR_VERSION 1.0.1
ENV ADDOK_FRANCE_VERSION 1.1.3

RUN apt-get -q update && \
    apt-get -qy install redis-tools jq g++ wget && \
    \
    pip install gunicorn addok==${ADDOK_VERSION} addok-fr==${ADDOK_FR_VERSION} addok-france==${ADDOK_FRANCE_VERSION} && \
    mkdir /etc/addok && \
    \
# Cleanup Debian packages
    apt-get remove -y git build-essential zlib1g-dev gdal-bin && \
    apt-get autoremove -y && \
    apt-get clean && \
    echo -n > /var/lib/apt/extended_states && \
    rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/*

ADD ./addok.conf /etc/addok/addok.conf

ENTRYPOINT ["gunicorn"]

CMD ["--bind", "0.0.0.0:7878", "--timeout", "7200", "--workers", "8", "addok.http.wsgi"]

EXPOSE 7878

HEALTHCHECK \
    --start-interval=1s \
    --start-period=30s \
    --interval=30s \
    --timeout=20s \
    --retries=5 \
    CMD wget --no-verbose --tries=1 -O /dev/null http://127.0.0.1:7878/health || exit 1
