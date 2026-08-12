# Voix Pocket TTS (Kyutai) — CPU, interne, sur mobang-prod.
# 100M-ish params, tourne en temps réel sur CPU (le GPU n'apporte rien — dixit Kyutai).
# Français = french_24l (24 couches, gated HF → HUGGING_FACE_HUB_TOKEN requis + accept terms).
# --quantize (int8/torchao) pour limiter la RAM (VPS un peu juste).
FROM python:3.11-slim

ENV HOME=/cache \
    HF_HOME=/cache/huggingface \
    PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1 \
    OMP_NUM_THREADS=2

RUN apt-get update \
 && apt-get install -y --no-install-recommends libsndfile1 ffmpeg curl \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /cache/huggingface

# torch CPU d'abord (sinon pip tire la build CUDA ~2 Go), puis pocket-tts.
RUN pip install torch==2.5.1 --index-url https://download.pytorch.org/whl/cpu
# Sans l'extra [quantize] (torchao 0.17 exige torch>=2.6). On mesure la RAM d'abord.
RUN pip install "pocket-tts[audio]==2.1.0"

EXPOSE 8000
# host 0.0.0.0 pour être joignable par le cerveau via le réseau docker (jamais exposé en public).
CMD ["pocket-tts","serve","--host","0.0.0.0","--port","8000","--language","french_24l"]
