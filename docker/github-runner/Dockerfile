# Custom GitHub Actions Runner with Helm and kubectl pre-installed
# Based on summerwind/actions-runner-dind for Docker-in-Docker support

FROM summerwind/actions-runner-dind:latest

USER root

# Install Helm
RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash && \
    helm version

# kubectl should already be installed in the base image, but verify
RUN kubectl version --client || \
    (curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
     install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && \
     rm kubectl)

# Verify installations
RUN helm version && kubectl version --client

USER runner
