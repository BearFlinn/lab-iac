# Custom GitHub Actions Runner for the grizzly-endeavors org.
# Built automatically by Argo Workflows (see kubernetes/infrastructure/argo-workflows/build-runner-image.yaml).
# Base: ARC v2 runner image (not the old summerwind/actions-runner-dind).

FROM ghcr.io/actions/actions-runner:latest

USER root

# Build tools and GitHub CLI
RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
      build-essential \
      pkg-config \
      libssl-dev \
      openssh-client \
      rsync \
      gcc-aarch64-linux-gnu \
      libc6-dev-arm64-cross && \
    (type -p wget >/dev/null || apt-get install -y -qq wget) && \
    mkdir -p -m 755 /etc/apt/keyrings && \
    wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update -qq && \
    apt-get install -y -qq gh && \
    rm -rf /var/lib/apt/lists/*

# kubectl (not included in ARC v2 base image)
RUN curl -fsSL -o /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    chmod 755 /usr/local/bin/kubectl

# Helm
RUN curl -fsSL -o /tmp/get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && \
    chmod 700 /tmp/get_helm.sh && \
    /tmp/get_helm.sh && \
    rm /tmp/get_helm.sh

# Node.js LTS
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - && \
    apt-get install -y -qq nodejs && \
    rm -rf /var/lib/apt/lists/*

# Rust toolchain — install as runner user so paths match workflow execution
USER runner
ENV RUSTUP_HOME=/home/runner/.rustup \
    CARGO_HOME=/home/runner/.cargo \
    PATH=/home/runner/.cargo/bin:$PATH
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile default && \
    rustup component add clippy rustfmt && \
    rustup target add aarch64-unknown-linux-gnu && \
    cargo install cargo-deny --locked

# Symlink Rust binaries into /usr/local/bin so they're on PATH regardless of
# how the runner spawns shell steps
USER root
RUN for bin in /home/runner/.cargo/bin/*; do \
      ln -sf "$bin" /usr/local/bin/; \
    done

# Verify all tools are accessible
RUN helm version && \
    kubectl version --client && \
    rustc --version && \
    cargo --version && \
    cargo deny --version && \
    node --version && \
    npm --version && \
    gh --version

USER runner
