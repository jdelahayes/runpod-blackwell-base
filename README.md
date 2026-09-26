# runpod-blackwell-base

Image de base minimale pour RunPod, optimisée pour les GPU Blackwell (RTX PRO 6000, RTX 50xx).
Ne contient que Python + PyTorch + SageAttention. Aucun modèle, aucun ComfyUI : c'est le
socle réutilisable pour n'importe quelle appli (ComfyUI, un serveur d'inférence maison, etc.).

## Versions (vérifiées septembre 2026)

| Composant | Version | Pourquoi |
|---|---|---|
| CUDA (build only) | 13.0.2 | Première ligne CUDA avec support natif sm_120 (Blackwell) et wheels ~33% plus légères que 12.8 |
| PyTorch | 2.14.0 (cu130) | Dernière stable, combo validé avec ComfyUI v0.37.2 |
| Python | 3.13 | Version recommandée par ComfyUI actuellement |
| SageAttention | main (thu-ml) | Attention quantifiée FP8/INT8, ~2x plus rapide sur Blackwell, requise/recommandée pour MiniMax H3 |
| OS final | Ubuntu 24.04 nu (pas nvidia/cuda) | Voir "Pourquoi c'est léger" ci-dessous |

## Pourquoi c'est léger

Le stage final ne part **pas** de `nvidia/cuda`. Les wheels PyTorch `cu130` embarquent déjà
tout le runtime CUDA nécessaire (cuBLAS, cuDNN, NCCL, cuSPARSE...) sous forme de dépendances
pip (`nvidia-*-cu13`). Le driver NVIDIA est fourni par l'hôte RunPod via le
nvidia-container-toolkit — il ne fait jamais partie de l'image. Empiler `nvidia/cuda:*-runtime`
+ pip torch ferait donc doublonner plusieurs Go de bibliothèques CUDA pour rien.

`nvidia/cuda:13.0.2-cudnn-devel` n'est utilisé que dans le **stage de build** (il faut `nvcc`
pour compiler SageAttention), puis jeté au multi-stage.

Autres leviers de taille :
- `TORCH_CUDA_ARCH_LIST=12.0` : on ne compile que pour sm_120 (RTX PRO 6000 / RTX 50xx), pas de
  code mort pour les architectures qu'on ne sert jamais sur ce type de pod.
- Nettoyage systématique des caches pip/apt et des dossiers `tests/` dans le venv avant de le
  copier dans le stage final.

## Build

```bash
./build.sh
```

Variables surchargeables : `IMAGE_NAME`, `IMAGE_TAG`, `REGISTRY`.

## Push

```bash
export REGISTRY=ghcr.io/<ton-user>
docker login ghcr.io
./push.sh
```

## Faire évoluer les versions

Tout est paramétré en `ARG` en haut du `Dockerfile` (`PYTHON_VERSION`, `CUDA_DEVEL_IMAGE`,
`TORCH_VERSION`, `TORCH_CUDA_ARCH_LIST`). Pour bumper PyTorch : vérifier la disponibilité de
la wheel sur https://download.pytorch.org/whl/cu130 avant de changer `TORCH_VERSION`.
