FROM mcr.microsoft.com/powershell:7.4-ubuntu-22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-venv \
    ffmpeg \
    git \
    ca-certificates \
 && ln -sf /usr/bin/python3 /usr/local/bin/python \
 && ln -sf /usr/bin/pip3 /usr/local/bin/pip \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/bootstrap
COPY requirements.txt /opt/bootstrap/requirements.txt

RUN python -m pip install --upgrade pip && \
    pip install -r /opt/bootstrap/requirements.txt

WORKDIR /repo

CMD ["pwsh", "-NoLogo", "-NoProfile"]
