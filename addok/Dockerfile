FROM python:3.4

ARG ADDOK_VERSION
ENV ADDOK_VERSION ${ADDOK_VERSION:-1.1.0-rc1}
ENV ADDOK_FR_VERSION 1.0.1
ENV ADDOK_FRANCE_VERSION 1.1.0

RUN apt-get -q update && \
    apt-get -qy install redis-tools jq && \
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

EXPOSE 7878

ADD ./addok.conf /etc/addok/addok.conf

ENTRYPOINT ["gunicorn"]

CMD ["--bind", "0.0.0.0:7878", "--timeout", "7200", "--workers", "8", "addok.http.wsgi"]
