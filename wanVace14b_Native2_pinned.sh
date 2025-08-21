#!/usr/bin/env bash
set -euo pipefail

############################################
# Config – choisis la série PyTorch
#   "2.4"  -> torchvision 0.19.1 (par défaut, stable)
#   "2.5"  -> torchvision 0.20.1 (si tu as besoin de sam-2>=1.0)
############################################
PYTORCH_SERIES="${PYTORCH_SERIES:-2.4}"

DEFAULT_WORKFLOW=""  # optionnel

APT_PACKAGES=(
  # Ajoute ici si nécessaire (ffmpeg est déjà présent sur Ai-Dock)
)

# Paquets Python additionnels (hors torch/vision/audio)
EXTRA_PIP_PACKAGES=(
  # "opencv-python-headless==4.10.0.84"
)

# Tes custom nodes
NODES=(
  "https://github.com/ltdrdata/ComfyUI-Manager"
  "https://github.com/yuvraj108c/ComfyUI-Video-Depth-Anything.git"
  "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite"
  "https://github.com/kijai/ComfyUI-KJNodes"
  "https://github.com/Fannovel16/comfyui_controlnet_aux.git"
  "https://github.com/kijai/ComfyUI-WanVideoWrapper.git"
  "https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git"
  "https://github.com/yvann-ba/ComfyUI_Yvann-Nodes.git"
  "https://github.com/AIWarper/ComfyUI-NormalCrafterWrapper.git"
  "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git"
  "https://github.com/crystian/ComfyUI-Crystools.git"
  "https://github.com/city96/ComfyUI-GGUF.git"
)

############################################
# Helpers Ai-Dock
############################################
provisioning_print_header() {
cat <<'EOF'

##############################################
#          Provisioning container            #
##############################################

EOF
}

provisioning_print_end() {
  printf "\nProvisioning complete: Web UI will start now\n\n"
}

provisioning_has_valid_hf_token() {
  [[ -n "${HF_TOKEN:-}" ]] || return 1
  local url="https://huggingface.co/api/whoami-v2"
  local code
  code=$(curl -o /dev/null -s -w "%{http_code}" -H "Authorization: Bearer $HF_TOKEN" "$url" || true)
  [[ "$code" == "200" ]]
}

provisioning_download() {
  # $1 url, $2 dest dir, $3 dotbytes
  local url="$1" dest="$2" dot="${3:-4M}"
  mkdir -p "$dest"
  local hdr=()
  if [[ "$url" =~ ^https://([^/]+\.)?huggingface\.co/ ]] && provisioning_has_valid_hf_token; then
    hdr=(--header "Authorization: Bearer $HF_TOKEN")
  fi
  wget -qnc --content-disposition --show-progress -e dotbytes="$dot" -P "$dest" "${hdr[@]}" "$url"
}

pip_install() {
  if [[ -z "${MAMBA_BASE:-}" ]]; then
    "$COMFYUI_VENV_PIP" install --no-cache-dir "$@"
  else
    micromamba run -n comfyui pip install --no-cache-dir "$@"
  fi
}

############################################
# Provisioning
############################################
provisioning_start() {
  # Si pas d'environnements, on passera par micromamba
  if [[ ! -d /opt/environments/python ]]; then
    export MAMBA_BASE=true
  fi

  source /opt/ai-dock/etc/environment.sh
  source /opt/ai-dock/bin/venv-set.sh comfyui

  provisioning_print_header

  # 1) APT optionnel
  if ((${#APT_PACKAGES[@]})); then
    sudo $APT_INSTALL "${APT_PACKAGES[@]}"
  fi

  # 2) Epingler torch/vision/audio (CUDA 12.1)
  local INDEX="--index-url https://download.pytorch.org/whl/cu121"
  case "$PYTORCH_SERIES" in
    2.5)
      TORCH_SPEC="torch==2.5.1+cu121 torchvision==0.20.1+cu121 torchaudio==2.5.1+cu121"
      ;;
    *)
      TORCH_SPEC="torch==2.4.1+cu121 torchvision==0.19.1+cu121 torchaudio==2.4.1+cu121"
      ;;
  esac

  # Purge éventuelles versions erronées puis install propre
  pip_install --upgrade pip
  pip_install "setuptools<75"  # évite certains edge cases d’ABI
  $COMFYUI_VENV_PIP uninstall -y torchvision torchaudio >/dev/null 2>&1 || true
  pip_install $INDEX $TORCH_SPEC

  # 3) Paquets Python supplémentaires
  if ((${#EXTRA_PIP_PACKAGES[@]})); then
    pip_install "${EXTRA_PIP_PACKAGES[@]}"
  fi

  # 4) Custom nodes → **/workspace/ComfyUI/custom_nodes/**
  local CN_BASE="/workspace/ComfyUI/custom_nodes"
  mkdir -p "$CN_BASE"
  for repo in "${NODES[@]}"; do
    local dir="${repo##*/}"
    dir="${dir%.git}"
    local path="$CN_BASE/$dir"
    local requirements="$path/requirements.txt"
    if [[ -d "$path" ]]; then
      if [[ "${AUTO_UPDATE,,}" != "false" ]]; then
        echo "Updating node: $repo"
        (cd "$path" && git pull --rebase --autostash || true)
        [[ -f "$requirements" ]] && pip_install -r "$requirements" || true
      fi
    else
      echo "Cloning node: $repo"
      git clone --recursive "$repo" "$path"
      [[ -f "$requirements" ]] && pip_install -r "$requirements" || true
    fi
  done

  # 5) Modèles Wan 2.1
  local MBASE="/workspace/ComfyUI/models"
  mkdir -p "$MBASE"/{text_encoders,vae,diffusion_models,loras}

  provisioning_download \
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors?download=true" \
    "$MBASE/text_encoders"

  provisioning_download \
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors?download=true" \
    "$MBASE/vae"

  provisioning_download \
    "https://huggingface.co/QuantStack/Wan2.1_14B_VACE-GGUF/resolve/main/Wan2.1_14B_VACE-Q5_K_S.gguf?download=true" \
    "$MBASE/diffusion_models"

  provisioning_download \
    "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan21_CausVid_14B_T2V_lora_rank32_v2.safetensors?download=true" \
    "$MBASE/loras"

  # 6) (Optionnel) workflow par défaut
  if [[ -n "${DEFAULT_WORKFLOW:-}" ]]; then
    wf_json=$(curl -fsSL "$DEFAULT_WORKFLOW" || true)
    if [[ -n "$wf_json" ]]; then
      echo "export const defaultGraph = $wf_json;" > /opt/ComfyUI/web/scripts/defaultGraph.js || true
    fi
  fi

  # 7) Sanity check NMS
  python - <<'PY'
import sys
import torchvision, torchvision.ops as ops
ok = hasattr(ops, "nms")
print("torchvision =", torchvision.__version__, "nms =", ok)
assert ok, "torchvision.ops.nms introuvable (build incompatible)"
PY

  provisioning_print_end
}

provisioning_start
