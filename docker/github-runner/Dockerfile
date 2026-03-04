# Custom GitHub Actions Runner with Helm, kubectl, and Rust pre-installed
# Based on summerwind/actions-runner-dind for Docker-in-Docker support

FROM summerwind/actions-runner-dind:latest

USER root

# Install Helm
# Security: Download the script first, verify it's executable, then run it
# This avoids curl|bash which could execute partial/corrupted downloads
# The official Helm install script handles GPG verification internally
RUN curl -fsSL -o /tmp/get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && \
    chmod 700 /tmp/get_helm.sh && \
    /tmp/get_helm.sh && \
    rm /tmp/get_helm.sh && \
    helm version

# kubectl should already be installed in the base image, but verify
RUN kubectl version --client || \
    (curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
     install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && \
     rm kubectl)

# Build tools and GitHub CLI
RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends build-essential gcc-aarch64-linux-gnu libc6-dev-arm64-cross && \
    (type -p wget >/dev/null || apt-get install -y -qq wget) && \
    mkdir -p -m 755 /etc/apt/keyrings && \
    wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update -qq && \
    apt-get install -y -qq gh && \
    rm -rf /var/lib/apt/lists/*

# Node.js LTS for web linting and builds
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - && \
    apt-get install -y -qq nodejs && \
    rm -rf /var/lib/apt/lists/* && \
    node --version && npm --version

# Install Rust toolchain via rustup
# Install as runner user so the toolchain is available during workflow execution
# -y for non-interactive, --profile default includes rustfmt/clippy
USER runner
ENV RUSTUP_HOME=/home/runner/.rustup \
    CARGO_HOME=/home/runner/.cargo \
    PATH=/home/runner/.cargo/bin:$PATH
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile default && \
    rustup component add clippy rustfmt && \
    rustup target add aarch64-unknown-linux-gnu && \
    cargo install cargo-deny --locked

USER root

# Symlink Rust binaries into /usr/local/bin so they're on PATH regardless of
# how the Actions runner spawns shell steps
RUN for bin in /home/runner/.cargo/bin/*; do \
      ln -sf "$bin" /usr/local/bin/; \
    done

# Verify installations
RUN helm version && kubectl version --client && rustc --version && cargo --version && cargo deny --version && node --version && npm --version

USER runner
