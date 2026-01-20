# Multi-stage Dockerfile for homelab validation tools
# Bundles all CI validation tools to eliminate runtime downloads
# Image pushed to: docker.nexus.erauner.dev/homelab/validation
#
# Tools included:
#   - kustomize, helm, kubeconform (manifest validation)
#   - kyverno (policy validation)
#   - promtool, yq (alerting rules)
#   - sops, ksops (secret decryption)
#   - shadow (GitOps structure validation) - pulled from Athens
#   - go-junit-report (test output)
#   - node, npm (TypeScript/npm package publishing)
#   - python3, pip, twine (Python package publishing)

# =============================================================================
# Build stage - install Go tools from Athens proxy
# =============================================================================
FROM golang:1.25-alpine AS builder

WORKDIR /build

# Install build dependencies
RUN apk add --no-cache git

# Configure Athens proxy for private modules
ENV GOPROXY=https://athens.erauner.dev,direct
ENV GONOSUMDB=github.com/erauner/*

# Install shadow from Athens proxy
# This pulls the latest release version via Go module proxy
ARG SHADOW_VERSION=latest
RUN GOBIN=/tools go install github.com/erauner/homelab-shadow/cmd/shadow@${SHADOW_VERSION}

# Install go-junit-report
RUN GOBIN=/tools go install github.com/jstemmer/go-junit-report/v2@latest

# =============================================================================
# Runtime stage - install all validation tools
# =============================================================================
FROM golang:1.25-alpine

# Tool versions - pinned for reproducibility
# Keep in sync with Jenkinsfile environment variables
ARG KUSTOMIZE_VERSION=v5.4.3
ARG HELM_VERSION=v3.16.3
ARG KUBECONFORM_VERSION=v0.6.7
ARG KYVERNO_VERSION=v1.16.2
ARG PROMETHEUS_VERSION=v2.48.0
ARG YQ_VERSION=v4.40.5
ARG SOPS_VERSION=v3.8.1
ARG KSOPS_VERSION=4.4.0
ARG KUBECTL_VERSION=v1.31.3

# Install OS packages (including nodejs/npm for package publishing)
RUN apk add --no-cache \
    bash \
    curl \
    wget \
    git \
    jq \
    tar \
    gzip \
    ca-certificates \
    util-linux \
    nodejs \
    npm \
    python3 \
    py3-pip \
    py3-build \
    py3-wheel

# Set up XDG_CONFIG_HOME for ksops plugin
ENV XDG_CONFIG_HOME=/root/.config

# Install kustomize
RUN wget -qO- "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_VERSION}/kustomize_${KUSTOMIZE_VERSION}_linux_amd64.tar.gz" \
    | tar xz -C /usr/local/bin \
    && chmod +x /usr/local/bin/kustomize \
    && kustomize version

# Install helm
RUN wget -qO- "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" \
    | tar xz --strip-components=1 -C /usr/local/bin linux-amd64/helm \
    && chmod +x /usr/local/bin/helm \
    && helm version --short

# Install kubeconform
RUN wget -qO- "https://github.com/yannh/kubeconform/releases/download/${KUBECONFORM_VERSION}/kubeconform-linux-amd64.tar.gz" \
    | tar xz -C /usr/local/bin \
    && chmod +x /usr/local/bin/kubeconform \
    && kubeconform -v

# Install kyverno CLI
RUN wget -qO- "https://github.com/kyverno/kyverno/releases/download/${KYVERNO_VERSION}/kyverno-cli_${KYVERNO_VERSION}_linux_x86_64.tar.gz" \
    | tar xz -C /usr/local/bin \
    && chmod +x /usr/local/bin/kyverno \
    && kyverno version

# Install promtool (from prometheus release)
RUN PROM_VER="${PROMETHEUS_VERSION#v}" \
    && wget -qO- "https://github.com/prometheus/prometheus/releases/download/${PROMETHEUS_VERSION}/prometheus-${PROM_VER}.linux-amd64.tar.gz" \
    | tar xz --strip-components=1 -C /usr/local/bin "prometheus-${PROM_VER}.linux-amd64/promtool" \
    && chmod +x /usr/local/bin/promtool \
    && promtool --version

# Install yq
RUN wget -qO /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" \
    && chmod +x /usr/local/bin/yq \
    && yq --version

# Install sops
RUN wget -qO /usr/local/bin/sops "https://github.com/getsops/sops/releases/download/${SOPS_VERSION}/sops-${SOPS_VERSION}.linux.amd64" \
    && chmod +x /usr/local/bin/sops \
    && sops --version

# Install ksops as kustomize plugin
RUN mkdir -p ${XDG_CONFIG_HOME}/kustomize/plugin/viaduct.ai/v1/ksops \
    && wget -qO- "https://github.com/viaduct-ai/kustomize-sops/releases/download/v${KSOPS_VERSION}/ksops_${KSOPS_VERSION}_Linux_x86_64.tar.gz" \
    | tar xz -C ${XDG_CONFIG_HOME}/kustomize/plugin/viaduct.ai/v1/ksops \
    && chmod +x ${XDG_CONFIG_HOME}/kustomize/plugin/viaduct.ai/v1/ksops/ksops \
    && ln -sf ${XDG_CONFIG_HOME}/kustomize/plugin/viaduct.ai/v1/ksops/ksops /usr/local/bin/ksops

# Install kubectl
RUN wget -qO /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && chmod +x /usr/local/bin/kubectl \
    && kubectl version --client

# Copy shadow binary from builder (installed via Athens)
COPY --from=builder /tools/shadow /usr/local/bin/shadow

# Copy go-junit-report from builder
COPY --from=builder /tools/go-junit-report /usr/local/bin/go-junit-report

# Set working directory
WORKDIR /workspace

# Install twine for PyPI publishing
RUN pip3 install --break-system-packages twine

# Verify all tools are available
RUN echo "=== Validation Image Tool Versions ===" \
    && echo "kustomize: $(kustomize version)" \
    && echo "helm: $(helm version --short)" \
    && echo "kubeconform: $(kubeconform -v)" \
    && echo "kyverno: $(kyverno version 2>&1 | head -1)" \
    && echo "promtool: $(promtool --version 2>&1 | head -1)" \
    && echo "yq: $(yq --version)" \
    && echo "sops: $(sops --version)" \
    && echo "kubectl: $(kubectl version --client --short 2>/dev/null || kubectl version --client)" \
    && echo "shadow: $(shadow version 2>/dev/null || echo 'built')" \
    && echo "go-junit-report: $(go-junit-report -version 2>&1 || echo 'installed')" \
    && echo "go: $(go version)" \
    && echo "node: $(node --version)" \
    && echo "npm: $(npm --version)" \
    && echo "python3: $(python3 --version)" \
    && echo "twine: $(twine --version)"

# Default command shows available tools
CMD ["sh", "-c", "echo 'Homelab Validation Image'; echo 'Available tools: kustomize, helm, kubeconform, kyverno, promtool, yq, sops, ksops, kubectl, shadow, go-junit-report, go, node, npm, python3, twine'"]
