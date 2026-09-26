# syntax=docker/dockerfile:1.7
#
# runpod-blackwell-base
# Image de base minimale : Python + PyTorch (CUDA 13.0 / Blackwell sm_120) + SageAttention.
#
# Choix clé pour la légèreté : le stage final PART D'UBUNTU NU, pas de nvidia/cuda.
# Les wheels PyTorch cu130 embarquent déjà tout le runtime CUDA dont elles ont besoin
# (nvidia-cublas-cu13, nvidia-cudnn-cu13, nvidia-nccl-cu13, ...). Le driver NVIDIA, lui,
# est fourni par l'hôte RunPod (nvidia-container-toolkit) : il ne fait jamais partie de
# l'image. Partir de nvidia/cuda:*-runtime en plus de pip torch ferait doublonner ~3-4 Go
# de bibliothèques CUDA pour rien. On ne touche à une image nvidia/cuda "devel" (avec nvcc)
# que dans le stage de build, pour compiler SageAttention, puis on la jette.
ARG PYTHON_VERSION=3.13
ARG CUDA_DEVEL_IMAGE=nvidia/cuda:13.0.2-cudnn-devel-ubuntu24.04
ARG TORCH_VERSION=2.14.0
# RTX PRO 6000 Blackwell = compute capability 12.0 (sm_120), comme les RTX 50 series.
# On ne compile QUE pour cette architecture : build plus rapide, wheel plus petite,
# pas de code mort pour sm_70/80/90 qu'on ne sert jamais sur RunPod pour cette carte.
ARG TORCH_CUDA_ARCH_LIST=12.0

########################################
# Stage 1 : builder (a besoin de nvcc)
########################################
FROM ${CUDA_DEVEL_IMAGE} AS builder
ARG PYTHON_VERSION
ARG TORCH_VERSION
ARG TORCH_CUDA_ARCH_LIST

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TORCH_CUDA_ARCH_LIST=${TORCH_CUDA_ARCH_LIST}

# Python 3.13 via deadsnakes (Ubuntu 24.04 ne fournit que 3.12 par défaut).
RUN apt-get update && apt-get install -y --no-install-recommends \
      software-properties-common curl ca-certificates git build-essential ninja-build \
    && add-apt-repository -y ppa:deadsnakes/ppa \
    && apt-get update && apt-get install -y --no-install-recommends \
      python${PYTHON_VERSION} python${PYTHON_VERSION}-venv python${PYTHON_VERSION}-dev \
    && rm -rf /var/lib/apt/lists/*

RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:${PATH}"

RUN uv venv /opt/venv --python python${PYTHON_VERSION} --seed
ENV PATH="/opt/venv/bin:${PATH}" VIRTUAL_ENV=/opt/venv

# PyTorch stable, wheels CUDA 13.0 (natif Blackwell, ~33% plus légères que cu128).
RUN uv pip install --no-cache-dir \
      torch==${TORCH_VERSION} torchvision torchaudio \
      --index-url https://download.pytorch.org/whl/cu130

# SageAttention : attention quantifiée FP8/INT8, gain ~2x sur Blackwell, recommandée
# par ComfyUI pour MiniMax H3. Compilée uniquement pour sm_120 (TORCH_CUDA_ARCH_LIST).
#
# Le setup.py de thu-ml/SageAttention (branche main) code en dur "-std=c++17", incompatible
# avec les headers PyTorch >= 2.14 qui exigent C++20 (cf. issue upstream #400 : pas encore
# fusionné au moment d'écrire ce Dockerfile). On clone et on patche ce seul flag avant build,
# plutôt que d'attendre le fix amont. À retirer si/quand thu-ml/SageAttention le corrige.
#
# MAX_JOBS=1 : les noyaux CUTLASS de SageAttention sont lourds à compiler (nvcc peut monter
# à plusieurs Go de RAM par unité de compilation). En parallèle (ninja utilise nproc par
# défaut, soit 4 sur les runners GitHub standard), ça dépasse la RAM disponible et le process
# est tué en silence (aucune erreur explicite dans les logs, juste une disparition du build).
# Compile plus lentement mais de façon fiable.
RUN uv pip install --no-cache-dir packaging wheel setuptools \
    && git clone --depth 1 https://github.com/thu-ml/SageAttention.git /tmp/sageattention \
    && sed -i 's/-std=c++17/-std=c++20/g' /tmp/sageattention/setup.py \
    && MAX_JOBS=1 uv pip install --no-cache-dir --no-build-isolation /tmp/sageattention \
    && rm -rf /tmp/sageattention

# Nettoyage : caches, tests, binaires de debug — pur gain de taille, aucun impact runtime.
RUN find /opt/venv -type d -name "__pycache__" -prune -exec rm -rf {} + \
 && find /opt/venv -type d \( -name "tests" -o -name "test" \) -prune -exec rm -rf {} + \
 && find /opt/venv -type f -name "*.pyc" -delete \
 && rm -rf /root/.cache /root/.cargo

########################################
# Stage 2 : image finale (ubuntu nu)
########################################
FROM ubuntu:24.04 AS final
ARG PYTHON_VERSION
LABEL org.opencontainers.image.title="runpod-blackwell-base" \
      org.opencontainers.image.description="CUDA 13.0 / PyTorch 2.14 (cu130) optimise pour RTX 6000 PRO (Blackwell, sm_120)"

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PATH="/opt/venv/bin:${PATH}" \
    VIRTUAL_ENV=/opt/venv \
    HF_HUB_ENABLE_HF_TRANSFER=1

# Même mineure Python que le builder (le venv référence l'interpréteur système),
# + le strict nécessaire pour SSH (standard RunPod) et les libs graphiques (opencv, etc.).
RUN apt-get update && apt-get install -y --no-install-recommends \
      software-properties-common curl ca-certificates git openssh-server \
      libgl1 libglib2.0-0 \
    && add-apt-repository -y ppa:deadsnakes/ppa \
    && apt-get update && apt-get install -y --no-install-recommends \
      python${PYTHON_VERSION} python${PYTHON_VERSION}-venv \
    && apt-get purge -y software-properties-common \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/*

COPY --from=builder /opt/venv /opt/venv

# Sanity check au build : echoue tot si le venv est casse, plutot qu'au demarrage du pod.
RUN python -c "import torch; assert torch.__version__.startswith('${TORCH_VERSION}'.split('+')[0]); print('torch', torch.__version__, 'cuda available (attendu False sans GPU au build):', torch.cuda.is_available())"

WORKDIR /workspace
CMD ["/bin/bash"]
