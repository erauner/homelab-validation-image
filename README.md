# Homelab Validation Image

Pre-built container image bundling all CI validation tools for homelab pipelines.

## Why This Image?

Instead of downloading tools at runtime in every CI job, this image pre-packages everything needed for GitOps validation. This provides:

- **Faster builds**: No tool downloads during CI runs
- **Reproducibility**: Pinned tool versions across all jobs
- **Reliability**: No failures from transient download issues

## Tools Included

| Tool | Purpose |
|------|---------|
| `kustomize` | Kubernetes manifest rendering |
| `helm` | Helm chart templating |
| `kubeconform` | K8s manifest schema validation |
| `kyverno` | Policy testing and validation |
| `promtool` | Prometheus alerting rule testing |
| `yq` | YAML processing |
| `sops` | Secret decryption |
| `ksops` | Kustomize SOPS plugin |
| `kubectl` | Kubernetes API access |
| `shadow` | GitOps structure validation |
| `go-junit-report` | JUnit XML test output |
| `go` | Go language toolchain |
| `node/npm` | Node.js for package publishing |
| `python3/pip/twine` | Python for package publishing |

## Usage

### In Jenkins Pod Template

```yaml
containers:
- name: golang
  image: docker.nexus.erauner.dev/homelab/validation:latest
  imagePullPolicy: Always
  command: ['sleep', '3600']
```

### Local Testing

```bash
docker pull docker.nexus.erauner.dev/homelab/validation:latest
docker run -it docker.nexus.erauner.dev/homelab/validation:latest bash

# Inside container, all tools available:
kustomize version
kyverno version
shadow --help
```

## Tool Versions

Tool versions are pinned in the Dockerfile as build args. To update a tool version:

1. Edit `Dockerfile` and update the corresponding `ARG`
2. Commit and push to `main`
3. Jenkins will automatically build and push a new image

## Shadow Binary

The `shadow` tool is pulled from the [homelab-shadow](https://github.com/erauner/homelab-shadow) repository via Athens proxy (`https://athens.erauner.dev`). This eliminates the need to copy source code into the image.

To use a specific shadow version, set the `SHADOW_VERSION` build arg:

```bash
docker build --build-arg SHADOW_VERSION=v0.2.0 -t validation:test .
```

## CI/CD

This repo uses Jenkins for CI:
- **On push to main**: Builds and pushes container image, creates pre-release tag (vX.Y.Z-rc.N)
- **Image registry**: `docker.nexus.erauner.dev/homelab/validation`

## License

MIT
