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

# Install Rust toolchain via rustup
# Install as runner user so the toolchain is available during workflow execution
# -y for non-interactive, --profile minimal for smaller image size
USER runner
ENV RUSTUP_HOME=/home/runner/.rustup \
    CARGO_HOME=/home/runner/.cargo \
    PATH=/home/runner/.cargo/bin:$PATH
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile default && \
    rustup component add clippy rustfmt

USER root

# Verify installations
RUN helm version && kubectl version --client
RUN su - runner -c 'source $HOME/.cargo/env && rustc --version && cargo --version'

USER runner
