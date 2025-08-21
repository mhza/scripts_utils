#!/bin/bash
set -e

# Activate ComfyUI venv
source /opt/ai-dock/etc/environment.sh || true
source /opt/ai-dock/bin/venv-set.sh comfyui

# Pin stack
cat >/workspace/pip-constraints.txt <<'EOF'
torch==2.4.1+cu121
torchvision==0.19.1+cu121
torchaudio==2.4.1+cu121
xformers==0.0.28.post1
triton==3.0.0
diffusers==0.35.1
EOF
echo 'PIP_CONSTRAINT=/workspace/pip-constraints.txt' | sudo tee -a /etc/environment >/dev/null
export PIP_CONSTRAINT=/workspace/pip-constraints.txt

# Install pinned torch stack
pip uninstall -y torch torchvision torchaudio xformers triton >/dev/null 2>&1 || true
pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cu121 \
  torch==2.4.1+cu121 torchvision==0.19.1+cu121 torchaudio==2.4.1+cu121
pip install --no-cache-dir xformers==0.0.28.post1 triton==3.0.0 diffusers==0.35.1 gguf segment-anything

# Stable tmp dir
mkdir -p /workspace/tmp && chmod 1777 /workspace/tmp
echo 'export TMPDIR=/workspace/tmp' | sudo tee -a /opt/ai-dock/etc/environment.sh >/dev/null
echo 'export TMP=/workspace/tmp'   | sudo tee -a /opt/ai-dock/etc/environment.sh >/dev/null
echo 'export TEMP=/workspace/tmp'  | sudo tee -a /opt/ai-dock/etc/environment.sh >/dev/null
export TMPDIR=/workspace/tmp TMP=/workspace/tmp TEMP=/workspace/tmp

# Custom nodes
mkdir -p /workspace/ComfyUI/custom_nodes
cd /workspace/ComfyUI/custom_nodes

git clone https://github.com/ltdrdata/ComfyUI-Manager                       || true
git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite           || true
git clone https://github.com/kijai/ComfyUI-KJNodes                           || true
git clone https://github.com/Fannovel16/comfyui_controlnet_aux               || true
git clone https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git     || true
git clone https://github.com/kijai/ComfyUI-WanVideoWrapper.git               || true
git clone https://github.com/yvann-ba/ComfyUI_Yvann-Nodes.git                || true
git clone https://github.com/AIWarper/ComfyUI-NormalCrafterWrapper.git       || true
git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git                || true
git clone https://github.com/crystian/ComfyUI-Crystools.git                  || true
git clone https://github.com/city96/ComfyUI-GGUF.git                         || true
git clone https://github.com/chengzeyi/Comfy-WaveSpeed.git                   || true
git clone https://github.com/pythongosssss/ComfyUI-Advanced-ControlNet.git   || true
git clone https://github.com/cubiq/ComfyUI_essentials.git                    || true
git clone https://github.com/rgthree/rgthree-comfy.git                       || true
git clone https://github.com/WASasquatch/was-node-suite-comfyui.git          || true
git clone https://github.com/yuvraj108c/ComfyUI-Video-Depth-Anything.git     || true
git clone https://github.com/city96/ComfyUI_IPAdapter_plus.git               || true

# Install node requirements if present
for d in /workspace/ComfyUI/custom_nodes/*; do
  [ -f "$d/requirements.txt" ] && pip install --no-cache-dir -r "$d/requirements.txt" || true
done

# Compatibility node: "Repeat Image To Count"
cat >/workspace/ComfyUI/custom_nodes/compat_repeat_image_to_count.py <<'PY'
import numpy as np
class RepeatImageToCount:
    @classmethod
    def INPUT_TYPES(cls):
        return {"required":{"image":("IMAGE",),"count":("INT",{"default":1,"min":1,"max":8192})}}
    RETURN_TYPES=("IMAGE",)
    FUNCTION="repeat"
    CATEGORY="Compat/Yvann"
    def repeat(self,image,count:int):
        if isinstance(image,list): base = image[0] if len(image) else np.zeros((8,8,3),dtype=np.float32)
        else: base = image
        out=[base]*int(max(1,count))
        return (out,)
NODE_CLASS_MAPPINGS={"Repeat Image To Count":RepeatImageToCount}
NODE_DISPLAY_NAME_MAPPINGS={"Repeat Image To Count":"Repeat Image To Count (Compat)"}
PY

# Models
mkdir -p /workspace/ComfyUI/models/{text_encoders,vae,diffusion_models,loras,animatediff_models,clip_vision,ipadapter}

# Wan text encoder + VAE
wget -qnc -O /workspace/ComfyUI/models/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors \
  "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors?download=true"
wget -qnc -O /workspace/ComfyUI/models/vae/wan_2.1_vae.safetensors \
  "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors?download=true"

# Wan GGUF (Q8_0 and Q5)
wget -qnc -O /workspace/ComfyUI/models/diffusion_models/Wan2.1_14B_VACE-Q8_0.gguf \
  "https://huggingface.co/QuantStack/Wan2.1_14B_VACE-GGUF/resolve/main/Wan2.1_14B_VACE-Q8_0.gguf?download=true"
wget -qnc -O /workspace/ComfyUI/models/diffusion_models/Wan2.1_14B_VACE-Q5_K_S.gguf \
  "https://huggingface.co/QuantStack/Wan2.1_14B_VACE-GGUF/resolve/main/Wan2.1_14B_VACE-Q5_K_S.gguf?download=true"

# Wan LoRA
wget -qnc -O /workspace/ComfyUI/models/loras/Wan21_CausVid_14B_T2V_lora_rank32_v2.safetensors \
  "https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan21_CausVid_14B_T2V_lora_rank32_v2.safetensors?download=true"

# AnimateDiff temporal layers (Hotshot-XL)
wget -qnc -O /workspace/ComfyUI/models/animatediff_models/hsxl_temporal_layers.f16.safetensors \
  "https://huggingface.co/hotshotco/Hotshot-XL/resolve/main/hsxl_temporal_layers.f16.safetensors?download=true"

# Optional IP-Adapter XL VIT-H and CLIP-ViT-H-14
wget -qnc -O /workspace/ComfyUI/models/ipadapter/ip-adapter-plus_sdxl_vit-h.safetensors \
  "https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl/ip-adapter-plus_sdxl_vit-h.safetensors?download=true"
wget -qnc -O /workspace/ComfyUI/models/clip_vision/CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors \
  "https://huggingface.co/Comfy-Org/clip-vit-large-patch14-336-laion2B-s32B-b79K/resolve/main/CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors?download=true"

# Restart ComfyUI so nodes/models are picked up
(supervisorctl restart comfyui 2>/dev/null) || true
