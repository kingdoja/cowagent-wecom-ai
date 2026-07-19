# Mirror of the Docker Official Image, pinned by content digest.
FROM docker.m.daocloud.io/library/node:22.22.0-bookworm-slim@sha256:dd9d21971ec4395903fa6143c2b9267d048ae01ca6d3ea96f16cb30df6187d94

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      ca-certificates \
      fontconfig \
      fonts-noto-cjk \
      git \
      jq \
      librsvg2-bin \
      make \
      python3 \
      python3-pil \
      python3-pip \
      ripgrep \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /workspace \
    && chown node:node /workspace

USER node
WORKDIR /workspace
ENV XDG_CACHE_HOME=/tmp/.cache

CMD ["/bin/bash"]
