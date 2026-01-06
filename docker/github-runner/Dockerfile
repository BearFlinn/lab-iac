# Custom GitHub Actions Runner with Helm and kubectl pre-installed
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

# Verify installations
RUN helm version && kubectl version --client

USER runner
