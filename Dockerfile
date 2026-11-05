# Driver source snapshot is bundled in vendor/ with its upstream GPL-3.0 license.
FROM debian:bookworm-slim AS captdriver-build
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential autoconf automake libtool pkg-config \
    libcups2-dev libcupsimage2-dev cups-ppdc unzip ca-certificates && \
    rm -rf /var/lib/apt/lists/*
COPY vendor/captdriver-master.zip /tmp/captdriver.zip
RUN echo '9a9027e8a736c91201bc7b216f3ab084b578a3f745b6f0808f73706512dc671e  /tmp/captdriver.zip' | sha256sum -c - && \
    unzip -q /tmp/captdriver.zip -d /build && \
    cd /build/captdriver-master && \
    aclocal && autoconf && automake --add-missing && \
    ./configure && make -j2 && make ppd && \
    test -s src/rastertocapt && test -s ppd/CanonLBP-2900-3000.ppd

FROM debian:bookworm-slim
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    cups cups-client cups-filters libcups2 usbutils ghostscript \
    ca-certificates socat supervisor curl && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /opt/canon /opt/cups-defaults /run/cups /var/spool/cups && \
    cp -a /etc/cups/. /opt/cups-defaults/
COPY --from=captdriver-build /build/captdriver-master/src/rastertocapt /usr/lib/cups/filter/rastertocapt
COPY --from=captdriver-build /build/captdriver-master/ppd/CanonLBP-2900-3000.ppd /opt/canon/CanonLBP-2900-3000.ppd
COPY --from=captdriver-build /build/captdriver-master/COPYING /usr/share/doc/captdriver/COPYING
COPY cups-config/cupsd.conf /opt/canon/cupsd.conf
COPY supervisor.conf /etc/supervisor/conf.d/canon.conf
COPY start.sh /usr/local/bin/start.sh
RUN chmod 755 /usr/lib/cups/filter/rastertocapt /usr/local/bin/start.sh
EXPOSE 631 515
CMD ["/usr/local/bin/start.sh"]
