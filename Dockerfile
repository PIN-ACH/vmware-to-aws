# ─────────────────────────────────────────────────────────────────────────────
# Portable control node for the VMware-to-AWS re-platform engine.
# Pins the entire toolchain so the pipeline behaves identically on any machine
# (laptop, CI runner, teammate's box). The only host prerequisite is Docker.
#
#   build:  docker build -t vmware2aws .
#   run:    docker run --rm -it --env-file .env -v "$PWD":/work vmware2aws
# ─────────────────────────────────────────────────────────────────────────────
FROM python:3.12-slim

# --- Pinned tool versions (bump deliberately, never float) -------------------
ENV TERRAFORM_VERSION=1.9.8 \
    GOVC_VERSION=0.37.3 \
    AWSCLI_VERSION=2.15.30 \
    DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl unzip ca-certificates openssh-client gnupg git jq \
    && rm -rf /var/lib/apt/lists/*

# --- Terraform ---------------------------------------------------------------
RUN curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" -o /tmp/tf.zip \
    && unzip /tmp/tf.zip -d /usr/local/bin \
    && rm /tmp/tf.zip \
    && terraform version

# --- govc (VMware CLI used by discovery) -------------------------------------
RUN curl -fsSL "https://github.com/vmware/govmomi/releases/download/v${GOVC_VERSION}/govc_Linux_x86_64.tar.gz" -o /tmp/govc.tgz \
    && tar -xzf /tmp/govc.tgz -C /usr/local/bin govc \
    && rm /tmp/govc.tgz \
    && govc version

# --- AWS CLI v2 --------------------------------------------------------------
# Correct URL scheme is "awscli-exe-..." (not "aws-cli-exe-..."). Try the pinned
# version first; fall back to latest so a bad pin can never break the build.
RUN set -eux; \
    url="https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${AWSCLI_VERSION}.zip"; \
    if ! curl -fsSL "$url" -o /tmp/awscli.zip; then \
        echo "pinned AWS CLI ${AWSCLI_VERSION} not found, falling back to latest"; \
        curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscli.zip; \
    fi; \
    unzip -q /tmp/awscli.zip -d /tmp; \
    /tmp/aws/install; \
    rm -rf /tmp/aws /tmp/awscli.zip; \
    aws --version

# --- Python deps (engine + ansible) ------------------------------------------
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

WORKDIR /work
# Default to an interactive shell; the Makefile targets are the real entrypoints.
CMD ["/bin/bash"]
