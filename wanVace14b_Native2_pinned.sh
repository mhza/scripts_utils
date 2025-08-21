#!/bin/bash
set -e

APT_PACKAGES=(
)

PIP_PACKAGES=(
)

NODES=(
    "https://github.com/ltdrdata/ComfyUI-Manager"
    "https://github.com/yuvraj108c/ComfyUI-Video-Depth-Anything.git"
    "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git"
    "https://github.com/kijai/ComfyUI-KJNodes.git"
    "https://github.com/Fannovel16/comfyui_controlnet_aux.git"
    "https://github.com/kijai/ComfyUI-WanVideoWrapper.git"
    "https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git"
    "https://github.com/yvann-ba/ComfyUI_Yvann-Nodes.git"
    "https://github.com/AIWarper/ComfyUI-NormalCrafterWrapper.git"
    "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git"
    "https://github.com/crystian/ComfyUI-Crystools.git"
    "https://github.com/city96/ComfyUI-GGUF.git"
)

provisioning_start() {
    source /opt/ai-dock/etc/environment.sh || true
    source /opt/ai-dock/bin/venv-set.sh comfyui

    export COMFY_BASE="/workspace/ComfyUI"
    export CUSTOM_NODES_DIR="$COMFY_BASE/custom_nodes"
    mkdir -p "$CUSTOM_NODES_DIR"

    mkdir -p /workspace/tmp && chmod 1777 /workspace/tmp
    export TMPDIR=/workspace/tmp TMP=/workspace/tmp TEMP=/workspace/tmp
    grep -q "TMPDIR=" /opt/ai-dock/etc/environment.sh 2>/dev/null || {
        echo 'export TMPDIR=/workspace/tmp' | sudo tee -a /opt/ai-dock/etc/environment.sh >/dev/null
        echo 'export TMP=/workspace/tmp'   | sudo tee -a /opt/ai-dock/etc/environment.sh >/dev/null
        echo 'export TEMP=/workspace/tmp'  | sudo tee -a /opt/ai-dock/etc/environment.sh >/dev/null
    }

    cat >/workspace/pip-constraints.txt <<'EOF'
torch==2.4.1+cu121
torchvision==0.19.1+cu121
torchaudio==2.4.1+cu121
xformers==0.0.28.post1
triton==3.0.0
diffusers==0.35.1
gguf==0.9.1
segment-anything==1.0
EOF
    export PIP_CONSTRAINT=/workspace/pip-constraints.txt

    pip uninstall -y torch torchvision torchaudio xformers triton diffusers gguf >/dev/null 2>&1 || true
    pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cu121 \
        torch==2.4.1+cu121 torchvision==0.19.1+cu121 torchaudio==2.4.1+cu121
    pip install --no-cache-dir xformers==0.0.28.post1 triton==3.0.0 diffusers==0.35.1 gguf==0.9.1 segment-anything==1.0

    provisioning_get_apt_packages
    provisioning_get_nodes
    provisioning_get_pip_packages

    cd "$COMFY_BASE/models"

    mkdir -p text_encoders vae diffusion_models loras
    cd text_encoders
    wget -qnc -O umt5_xxl_fp8_e4m3fn_scaled.safetensors \
      "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors?download=true"

    cd ../vae
    wget -qnc -O wan_2.1_vae.safetensors \
      "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors?download=true"

    cd ../diffusion_models
    wget -qnc -O Wan2.1_14B_VACE-Q5_K_S.gguf \
      "https://huggingface.co/QuantStack/Wan2.1_14B_VACE-GGUF/resolve/main/Wan2.1_14B_VACE-Q5_K_S.gguf?download=true"
    wget -qnc -O Wan2.1_14B_VACE-Q8_0.gguf \
      "https://huggingface.co/QuantStack/Wan2.1_14B_VACE-GGUF/resolve/main/Wan2.1_14B_VACE-Q8_0.gguf?download=true"

    cd ../loras
    wget -qnc -O Wan21_CausVid_14B_T2V_lora_rank32_v2.safetensors \
      "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan21_CausVid_14B_T2V_lora_rank32_v2.safetensors?download=true"

    provisioning_print_end
}

pip_install() {
    "$COMFYUI_VENV_PIP" install --no-cache-dir "$@"
}

provisioning_get_apt_packages() {
    if [[ -n ${APT_PACKAGES[*]} ]]; then
        sudo $APT_INSTALL ${APT_PACKAGES[@]}
    fi
}

provisioning_get_pip_packages() {
    if [[ -n ${PIP_PACKAGES[*]} ]]; then
        pip_install ${PIP_PACKAGES[@]}
    fi
}

provisioning_get_nodes() {
    for repo in "${NODES[@]}"; do
        dir="${repo##*/}"
        path="$CUSTOM_NODES_DIR/${dir}"
        requirements="${path}/requirements.txt"
        if [[ -d $path ]]; then
            if [[ ${AUTO_UPDATE,,} != "false" ]]; then
                echo "Updating node: ${repo}"
                ( cd "$path" && git pull --rebase --autostash || true )
                [[ -f $requirements ]] && pip_install -r "$requirements" || true
            fi
        else
            echo "Cloning node: ${repo}"
            git clone --recursive "${repo}" "${path}" || true
            [[ -f $requirements ]] && pip_install -r "$requirements" || true
        fi
    done
}

provisioning_print_end() {
    echo "Provisioning complete."
}

provisioning_start
