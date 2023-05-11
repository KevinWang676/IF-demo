# Download LFS content while building in order to make this step cacheable
# #===== LFS =====
# FROM alpine/git:2.36.2 AS lfs
# WORKDIR /app
# COPY --link .lfs.hf.co .
# RUN --mount=type=secret,id=SPACE_REPOSITORY,mode=0444,required=true \
#     git init \
#  && git remote add origin $(cat /run/secrets/SPACE_REPOSITORY) \
#  && git add --all \
#  && git config user.email "name@mail.com" \
#  && git config user.name "Name" \
#  && git commit -m "lfs" \
#  && git lfs pull \
#  && rm -rf .git .gitattributes
# #===============

FROM nvidia/cuda:11.8.0-runtime-ubuntu18.04
# BEGIN Static part
ENV DEBIAN_FRONTEND=noninteractive \
	TZ=Europe/Paris

RUN apt-get update && apt-get install -y \
        git \
        make build-essential libssl-dev zlib1g-dev \
        libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm \
        libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev git-lfs  \
    	ffmpeg libsm6 libxext6 cmake libgl1-mesa-glx \
		&& rm -rf /var/lib/apt/lists/* \
    	&& git lfs install

# User
RUN useradd -m -u 1000 user
USER user
ENV HOME=/home/user \
	PATH=/home/user/.local/bin:$PATH
WORKDIR /home/user/app

# Pyenv
RUN curl https://pyenv.run | bash
ENV PATH=$HOME/.pyenv/shims:$HOME/.pyenv/bin:$PATH

ARG PIP_VERSION=22.3.1
ARG PYTHON_VERSION=3.10
# Python
RUN pyenv install $PYTHON_VERSION && \
    pyenv global $PYTHON_VERSION && \
    pyenv rehash && \
    pip install --no-cache-dir --upgrade pip==${PIP_VERSION} setuptools wheel && \
    pip install --no-cache-dir \
        datasets \
        "huggingface-hub>=0.12.1" "protobuf<4" "click<8.1"

#^ Waiting for https://github.com/huggingface/huggingface_hub/pull/1345/files to be merge

USER root
# User Debian packages
## Security warning : Potential user code executed as root (build time)
RUN --mount=target=/root/packages.txt,source=packages.txt \
	apt-get update && \
    xargs -r -a /root/packages.txt apt-get install -y \
    && rm -rf /var/lib/apt/lists/*
    
USER user

# Pre requirements (e.g. upgrading pip)
RUN --mount=target=pre-requirements.txt,source=pre-requirements.txt \
	pip install --no-cache-dir -r pre-requirements.txt

# Python packages
RUN pip install --pre torch --index-url https://download.pytorch.org/whl/nightly/cu117
RUN --mount=target=requirements.txt,source=requirements.txt \
	pip install --no-cache-dir -r requirements.txt

ARG SDK=gradio \
	SDK_VERSION=3.27.0
RUN pip install --no-cache-dir \
        ${SDK}==${SDK_VERSION}

# App
# COPY --link --chown=1000 --from=lfs /app /home/user/app
COPY --link --chown=1000 ./ /home/user/app
ENV PYTHONPATH=$HOME/app \
	PYTHONUNBUFFERED=1 \
	GRADIO_ALLOW_FLAGGING=never \
	GRADIO_NUM_PORTS=1 \
	GRADIO_SERVER_NAME=0.0.0.0 \
	GRADIO_THEME=huggingface \
	SYSTEM=spaces

CMD ["python", "app.py"]
