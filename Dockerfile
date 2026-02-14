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
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:install && pnpm ui:build

# Runtime image
FROM node:22-bookworm
ENV NODE_ENV=production

# Install system dependencies needed for OpenClaw skills
# Skills may need build tools, Python, git, and various utilities
RUN apt-get update && \
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
ca-certificates \
git \
curl \
wget \
python3 \
python3-pip \
python3-venv \
make \
g++ \
build-essential \
unzip \
zip \
tar \
xz-utils \
libssl-dev \
libffi-dev \
file \
procps \
&& rm -rf /var/lib/apt/lists/* && \
# Create python symlink for scripts that expect 'python' command
ln -sf /usr/bin/python3 /usr/bin/python && \
# Ensure pip is up to date (--break-system-packages is safe in Docker containers)
python3 -m pip install --no-cache-dir --break-system-packages --upgrade pip setuptools wheel

# Install GitHub CLI (gh) directly - commonly needed for OpenClaw skills
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && \
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list && \
apt-get update && \
apt-get install -y --no-install-recommends gh && \
rm -rf /var/lib/apt/lists/*

# Install Homebrew for Linux (as recommended by OpenClaw for other skills)
# Simple approach: create user, install Homebrew, create basic wrapper
RUN useradd -m -s /bin/bash linuxbrew && \
su - linuxbrew -c 'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' && \
su - linuxbrew -c 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" && brew update' && \
chmod -R go+w /home/linuxbrew/.linuxbrew && \
# Simple wrapper: run as linuxbrew user when called as root
cat > /usr/local/bin/brew << 'EOF'
#!/bin/bash
if [ "$(id -u)" = "0" ]; then
  CMD="eval \$(/home/linuxbrew/.linuxbrew/bin/brew shellenv) && brew"
  for arg in "$@"; do
    CMD="$CMD $(printf '%q' "$arg")"
  done
  exec su -s /bin/bash linuxbrew -c "$CMD"
else
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  exec /home/linuxbrew/.linuxbrew/bin/brew "$@"
fi
EOF
chmod +x /usr/local/bin/brew

# Set up Homebrew environment variables (covers both standard and root installation paths)
ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:/root/.linuxbrew/bin:/root/.linuxbrew/sbin:${PATH}"
ENV HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"
ENV HOMEBREW_CELLAR="/home/linuxbrew/.linuxbrew/Cellar"
ENV HOMEBREW_REPOSITORY="/home/linuxbrew/.linuxbrew/Homebrew"
ENV HOMEBREW_NO_AUTO_UPDATE=1
ENV HOMEBREW_NO_ANALYTICS=1
# Allow Homebrew to work as root (safe in Docker containers)
ENV HOMEBREW_FORCE_BREWED_GIT=1
ENV HOMEBREW_FORCE_BREWED_CURL=1
# Initialize Homebrew cache directory permissions for root usage
ENV HOMEBREW_CACHE="/home/linuxbrew/.linuxbrew/var/homebrew_cache"

RUN corepack enable && corepack prepare pnpm@10.23.0 --activate

WORKDIR /app

# Wrapper deps (your original server.js approach)
COPY package.json ./
RUN npm install --omit=dev && npm cache clean --force

# Copy built openclaw
COPY --from=openclaw-build /openclaw /openclaw

# Provide openclaw executable
RUN printf '%s\n' '#!/usr/bin/env bash' 'exec node /openclaw/dist/entry.js "$@"' > /usr/local/bin/openclaw \
&& chmod +x /usr/local/bin/openclaw

# Copy your wrapper server
COPY src ./src

ENV OPENCLAW_PUBLIC_PORT=8080
ENV PORT=8080
EXPOSE 8080

CMD ["node", "src/server.js"]
