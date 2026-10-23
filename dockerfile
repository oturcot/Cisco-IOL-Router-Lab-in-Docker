FROM --platform=linux/amd64 debian:bookworm

RUN dpkg --add-architecture i386
RUN apt-get update && \
    apt-get install -y \
        python3 \
        libc6:i386 \
        libgcc-s1:i386 \
        libstdc++6:i386 \
        tmux \
        iproute2 \
        telnet \
        iputils-ping \
        tcpdump \
        iptables

COPY ios-images/i86bi_linux-adventerprisek9-ms.155-2.T.bin /iol.bin
COPY CiscoIOUKeygen3f.py /CiscoIOUKeygen3f.py
RUN chmod +x /iol.bin
RUN chmod +x /CiscoIOUKeygen3f.py


#ubridge
RUN apt-get update && \
    apt-get install -y \
        build-essential \
        git \
        libpcap-dev \
        cmake

RUN git clone https://github.com/GNS3/ubridge.git /tmp/ubridge && \
    cd /tmp/ubridge && \
    sed -i '/src\/hypervisor_tc.c/d' Makefile && \
    sed -i '/src\/tc_netem_dist.c/d' Makefile && \
    sed -i '/src\/tc_ebpf.c/d' Makefile && \
    sed -i '/hypervisor_tc_init/d' src/hypervisor.c && \
    make && \
    make install


#entrypoint

COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
