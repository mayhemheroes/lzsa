FROM --platform=linux/amd64 ubuntu:20.04 as builder

RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y clang make

ADD . /lzsa
WORKDIR /lzsa
RUN make -j8

RUN mkdir -p /deps
RUN ldd /lzsa/lzsa | tr -s '[:blank:]' '\n' | grep '^/' | xargs -I % sh -c 'cp % /deps;'

FROM ubuntu:20.04 as package

COPY --from=builder /deps /deps
COPY --from=builder /lzsa/lzsa /lzsa/lzsa
ENV LD_LIBRARY_PATH=/deps
