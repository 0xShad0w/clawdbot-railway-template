FROM node:22-bookworm AS openclaw-build

RUN apt-get update && \
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
git \
ca-certificates \
curl \
python3 \
make \
g++ \
&& rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"
RUN corepack enable

WORKDIR /openclaw

ARG OPENCLAW_GIT_REF=v2026.2.9
RUN git clone --depth 1 --branch "${OPENCLAW_GIT_REF}" https://github.com/openclaw/openclaw.git .

RUN set -eux; \
find ./extensions -name 'package.json' -type f | while read -r f; do \
sed -i -E 's/"openclaw"[[:space:]]*:[[:space:]]*">=[^"]+"/"openclaw": "*"/g' "$f"; \
sed -i -E 's/"openclaw"[[:space:]]*:[[:space:]]*"workspace:[^"]+"/"openclaw": "*"/g' "$f"; \
done

RUN pnpm install --no-frozen-lockfile
RUN pnpm build

FROM node:22-bookworm
ENV NODE_ENV=production
RUN apt-get update && \
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates && \
rm -rf /var/lib/apt/lists/*
RUN corepack enable
WORKDIR /openclaw
COPY --from=openclaw-build /openclaw /openclaw

RUN printf '%s\n' '#!/usr/bin/env bash' 'exec node /openclaw/dist/entry.js "$@"' > /usr/local/bin/openclaw \
&& chmod +x /usr/local/bin/openclaw

EXPOSE 8080
CMD ["openclaw"]
