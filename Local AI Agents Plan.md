# Local AI Agents Plan — M3 MacBook Pro + Proxmox

As of Nov 8, 2026

> **Decided 2026-11-27** (the design is [L5h in guests/README.md](guests/README.md#l5h-local-ai-ai01); where this
> plan differs, L5h wins):
>
> - `ai01` is a **VM** with the GPU passed through, not an LXC with the host's NVIDIA driver: the host stays
>   driver-free (as for the P2000), so kernel updates can't break the GPU. Read the Proxmox setup guide below with
>   that in mind.
> - The GPU is the **RTX 5060 Ti 16 GB** (already owned), not the 3070: twice the VRAM at the same memory bandwidth.
> - Open WebUI and n8n run on `docker01` behind Authentik; remote access is **Teleport**, not Tailscale.
> - Open questions answered: the GPU power board, its cables and the fan kit are installed; RAM is 4 of 6 channels per
>   CPU (8 × 32 GB); models go on `nvme` until the `data` pool exists, then `data/models`.

## The plan in one screen

Run the Proxmox box as an always-on "utility" AI server for background agents, use the MacBook for the bigger interactive model, and keep Claude for hard multi-step coding and reasoning. Both machines run Ollama, so every tool talks to them the same way.

- **Proxmox server pve01 (2x Xeon Gold 5118, 48 threads, 251 GB RAM, RTX 3070 8 GB):** an LXC with the 3070 passed through. Ollama serves small models fully on the GPU; llama.cpp serves big MoE models whose "experts" sit in system RAM. Models: Gemma 4 12B/E4B on the GPU, Qwen3.6-35B-A3B and gpt-oss-120b in GPU+RAM mode. Job: summaries, triage, RAG, transcription, 24/7 agents, and a bigger model than the Mac can hold.
- **M3 MacBook Pro (24–36 GB):** Ollama or LM Studio on Apple's MLX engine. Best model: Qwen3.6-35B-A3B (36 GB) or Gemma 4 26B-A4B (tight on 24 GB). Job: interactive local coding agent, longer chats, vision on screenshots and photos, when the laptop is awake and plugged in.
- **Claude:** multi-file repo work, anything security-sensitive to get right, long agentic sessions, final review of what local agents produce.

What to expect: local models handle roughly the "intern" tier of work very well and cost nothing per token. They will not replace Claude for autonomous coding in large repos. Expect about 35–40 tokens/sec on the Mac, 25+ on small models fully on the 3070, and roughly 10–20 on 35B–120B MoE models in GPU+RAM mode on the server. The one purchase worth making is a used RTX 3090 (24 GB).

Open questions: whether the T640 already has Dell's GPU power board and external fans, how the 256 GB of RAM is spread across memory channels, where models will be stored (the root disk has ~167 GB free), and whether the Mac is 24 GB or 36 GB.

## Hardware and model picks

The number that matters is memory the GPU can use: VRAM on the NVIDIA card, unified memory on the Mac. A model that spills out of it onto the CPU gets several times slower. Sizes below are 4-bit quantized weights; leave 2–4 GB extra for context.

| Machine | Pick | Memory used | Measured or reported speed | Good for |
| --- | --- | --- | --- | --- |
| Mac, 36 GB | **Qwen3.6-35B-A3B** (MoE, 3B active), MLX 4-bit | ~20–21 GB peak | ~37–39 tok/s output, ~500–550 tok/s prompt reading on an M3 Pro 36 GB ([oMLX benchmark](https://omlx.ai/benchmarks/rnvweq15)) | Coding agent, tool calls, vision |
| Mac, 36 GB | Gemma 4 26B-A4B (MoE, ~4B active) | ~16–18 GB | similar class to Qwen MoE | Chat, writing, JSON output, images |
| Mac, 24 GB | Gemma 4 E4B, or Qwen3.6-35B-A3B at 3-bit | ~5–6 GB / ~15 GB | fast / usable | Lighter agents; the 35B is tight |
| pve01 | See the server table below | — | — | — |
| Either | Parakeet TDT 0.6B v3 or Whisper large-v3-turbo | ~1–3 GB | far faster than real time | Transcription |

Why these models: Qwen3.6 (Apr 2026) and Gemma 4 are the current open-weight families built for local use, both Apache 2.0, both multimodal. [Qwen3.6-35B-A3B](https://oracore.dev/news/qwen36-35b-a3b-open-source-agentic-coding-en) targets agentic coding and only activates 3B parameters per token, which is why it runs fast on a laptop. [Gemma 4](https://unsloth.ai/docs/models/gemma-4) comes in E2B, E4B, 12B, 26B-A4B and 31B; the E-models also take audio input.

Mac notes: macOS lets the GPU use only part of unified memory by default (roughly two thirds on smaller configs), so a 24 GB Mac has about 16 GB for models. Dense models like Qwen3.6-27B or Gemma 4 31B fit on 36 GB but run several times slower than the MoE picks, so skip them for agents.

### pve01: what your server can run

The 251 GB of RAM is the real asset, not the GPU. MoE models read only a few billion "active" parameters per token, so llama.cpp can keep attention layers on the GPU and push the experts into system RAM (`--n-cpu-moe`). That lets this box run models far larger than any card you own. Speeds below are estimates from similar hardware; measure yours with `llama-bench`.

| Model | Where it lives | Memory | Expected output speed | Use |
| --- | --- | --- | --- | --- |
| Gemma 4 12B or E4B, Q4 | All on the 3070 | ~6–8 GB VRAM | 25+ tok/s class | Always-on small agent, vision |
| Qwen3.6-35B-A3B, Q4 | 3070 + RAM | ~8 GB VRAM + ~15 GB RAM | ~15–25 tok/s (estimate) | Same model as the Mac, available 24/7 |
| gpt-oss-120b (5.1B active) | 3070 + RAM | ~8 GB VRAM + ~60 GB RAM | ~10–15 tok/s; a dual Xeon E5-2680 v4 did ~10.5 tok/s CPU-only ([benchmark](https://youtubesummary.com/summary/mUZQlG-I5fA)) | Strongest reasoning you can host |
| Qwen3.5-122B-A10B, Q4 | 3070 + RAM | ~8 GB VRAM + ~70 GB RAM | ~5–8 tok/s (estimate) | Slow, higher-quality batch jobs |

The catch is prompt reading. With experts in RAM, a 20K-token agent prompt can take minutes on the 3070, so use the 120B-class models for n8n and batch jobs, not as the backend for interactive Claude Code. CPU-only, that same E5-2680 v4 system read prompts at only ~90 tok/s.

Memory channels matter more than capacity. Each Gold 5118 has six DDR4-2400 channels, and 256 GB cannot spread evenly over 12 channels. Run `dmidecode -t memory` to see which slots are filled; if only 4 channels per socket are populated, CPU offload runs noticeably slower than it could.

### Which GPU to use, and which to buy

Use the RTX 3070 now. If you buy one card, make it a used RTX 3090.

| Card | VRAM | Cost | Verdict |
| --- | --- | --- | --- |
| RTX 3070 (have) | 8 GB, Ampere | $0 | **Use this.** Current drivers and CUDA 13, tensor cores for fast prompt reading. A good GPU half for GPU+RAM MoE models. |
| GTX 1080 Ti (have) | 11 GB, Pascal | $0 | Backup only. More VRAM, but NVIDIA's [580 driver branch is the last](https://www.tweaktown.com/news/106148/game-ready-driver-support-for-the-iconic-geforce-gtx-1080-ti-to-end-soon/index.html) to support it and CUDA 13 dropped Pascal. Ollama still [ships a CUDA 12 runner](https://localaimaster.com/blog/pascal-gpus-after-cuda-13) for it, but it is a dead end. |
| Quadro P2000 (have) | 5 GB, Pascal | $0 | Skip, or use it only for Whisper and embeddings. |
| **RTX 3090 (buy)** | 24 GB, Ampere | ~$650–900 used ([SpecPicks](https://specpicks.com/reviews/used-rtx-3090-local-llm-2026-buy-service-benchmark), [HomelabPicks](https://homelabpicks-com.pages.dev/gpu-ai/best-gpu-local-llms)) | Best value per dollar. Fits Qwen3.6-35B-A3B and Gemma 4 26B entirely on the GPU, reads prompts far faster, and holds more experts for 120B-class models. A used 3090 ran dense Qwen3 32B at [38.9 tok/s](https://computingforgeeks.com/rtx-3090-vs-5090-for-local-ai/). |
| RTX 3060 12 GB | 12 GB | ~$250 used | Skip: only 4 GB more than the 3070. |
| RTX 5060 Ti 16 GB | 16 GB | ~$500 new | Skip: warranty, but 16 GB still can't hold the 35B MoE with agent context. |

Avoid Pascal datacenter cards like the Tesla P40 even though their 24 GB is cheap: they hit the same end of driver support as the 1080 Ti.

### Fitting a GPU in the PowerEdge T640

The T640 is one of the better servers for this: Dell rates it for up to four full-length, double-wide GPUs at up to 300 W each, and it needs two CPUs and identical GPUs for multi-GPU setups ([Dell community, citing the T640 manual](https://dell.com/community/en/conversations/poweredge-hardware-general/dell-poweredge-t-series-with-nvidia-tesla-p100/669cee91b539c16d2f9f186b)). The catches are power cabling and airflow, not space.

| Item | What you need | Notes |
| --- | --- | --- |
| GPU power | Power interposer board (PIB, Dell part X7C1K) + GPU cable [DRXPD](https://expresscomputersystems.com/products/drxpd) (8-pin EPS to 6-pin + 6+2-pin PCIe) | The T640 has no spare PCIe power leads without the PIB. Skip if the server was ordered GPU-ready. Check before buying anything: open the side and look for the PIB behind the PSUs. |
| Cooling | Dell's GPU cooling kit: two external fans on the expansion-slot side | The [T640 manual](https://www.manualowl.com/m/Dell/PowerEdge-T640/Manual/593064?page=125) requires both external fans for GPU configs. |
| Orientation | Dell says GPUs are supported in rack configuration, where the air shroud sits differently ([Dell community](https://www.dell.com/community/en/conversations/poweredge-hardware-general/t640-gpu/647f945ff4ccf8a8de6a7377)) | Homelabbers do run cards in tower mode; watch GPU temps closely if you do. |
| PSUs | Two PSUs sized for GPU load | Check wattage in iDRAC. A 3090 plus two 105 W CPUs wants the larger PSU options. |
| Card shape | 2-slot, blower-style, rear exhaust | Open-air 3-slot gaming 3090s dump heat into the chassis and crowd neighboring slots. Look for the Gigabyte or ASUS 3090 "Turbo" blower cards or Dell's OEM 3090. They often cost more than open-air 3090s. |

The 3090 draws ~350 W, above Dell's 300 W-per-slot rating. Cap it with `nvidia-smi -pl 300` (make it persistent with a systemd unit). LLM text generation is mostly memory-bound, so the speed loss is small.

What works today without buying parts: the Quadro P2000 runs on slot power alone (75 W). The 3070 and 1080 Ti both need the PIB and cable. If the PIB is missing, a ~$15–30 used cable and the PIB are the first purchase, before any GPU.

## Architecture: how it fits with Claude

Everything points at an Ollama (or llama.cpp) endpoint. Ollama speaks both the OpenAI and the Anthropic Messages API, so Claude Code, OpenCode, n8n and Open WebUI can all switch between Claude and local by changing a base URL.

| Layer | Runs on | Components |
| --- | --- | --- |
| Model servers | Proxmox LXC (`ai01`), MacBook | Ollama on each (`http://ai01:11434`, `http://localhost:11434`); llama-server on `ai01:8080` for big MoE models |
| Interfaces | Proxmox LXCs | Open WebUI (chat + document Q&A for the family/team), n8n (scheduled and triggered agents) |
| Agents | Mac terminal / VS Code | Claude Code with a `claude-local` alias, OpenCode as a second agent |
| Remote access | Both | Tailscale; never port-forward Ollama, its API has no login |

Routing rule of thumb:

| Job | Send it to | Why |
| --- | --- | --- |
| Summarize, tag, classify, extract fields, draft replies | Proxmox, small model | High volume, low difficulty, runs unattended |
| Q&A over NAS docs, manuals, notes | Proxmox, Open WebUI RAG | Data stays home |
| Transcribe audio/video | Proxmox or Mac, Parakeet/Whisper | Fast and free |
| Write a script, explain or tidy one file, PowerShell | Mac, Qwen3.6-35B-A3B | Good enough, zero tokens |
| Read photos, receipts, screenshots, product labels | Mac (Qwen/Gemma) or server (Gemma E4B) | Both are vision models |
| Overnight batch jobs needing a smarter model | Proxmox, gpt-oss-120b via llama.cpp | Slow but strong, and nobody is waiting |
| Multi-file changes, debugging across a repo, long autonomous runs | Claude | Local models lose the thread on long, tool-heavy tasks |
| Anything where a wrong answer is costly (security config, prod changes) | Claude, or local draft then Claude review | Quality gap matters most here |

If you use this for Podium work, check that company code and data are allowed on personal hardware before pointing agents at work repos.

## Setup guide: Proxmox server

Use an LXC container with the GPU shared in, not a VM. An LXC adds almost no overhead and several containers can use the card; VM passthrough needs IOMMU and dedicates the GPU to one VM. Plan on one evening.

1. **Check the hardware.** On the host, run `lspci | grep -i nvidia` to confirm the card, and `dmidecode -t memory` to see how RAM is populated. The root disk has ~167 GB free and models take 5–60 GB each, so plan a separate disk or ZFS dataset for `/models`.
2. **Install the NVIDIA driver on the host.** Install headers (`apt install proxmox-headers-$(uname -r)`), blacklist `nouveau`, then install NVIDIA's `.run` driver with `--dkms` so it survives kernel updates. Confirm with `nvidia-smi`.
3. **Create the container.** Debian 12/13 or Ubuntu 24.04 template, unprivileged, hostname `ai01`. Give it 16 GB RAM for Ollama alone, or 128 GB and all 48 threads if it will also run llama.cpp with big MoE models. Mount `/models` into it. Turn on `nesting=1` if you will run Docker inside it.
4. **Pass the GPU in.** Container → Resources → Add → Device Passthrough, and add `/dev/nvidia0`, `/dev/nvidiactl`, `/dev/nvidia-uvm` and `/dev/nvidia-uvm-tools`. Older guides do the same with `lxc.cgroup2.devices.allow: c 195:* rwm` plus mount entries in `/etc/pve/lxc/<id>.conf`.
5. **Install the matching driver inside the container.** Run the exact same `.run` version with `--no-kernel-module`. Host and container versions must match, or `nvidia-smi` fails inside. Confirm `nvidia-smi` shows the card in the container.
6. **Install Ollama.** `curl -fsSL https://ollama.com/install.sh | sh`. Then `systemctl edit ollama` and add:

   ```ini
   [Service]
   Environment="OLLAMA_HOST=0.0.0.0:11434"
   Environment="OLLAMA_CONTEXT_LENGTH=16384"
   Environment="OLLAMA_KEEP_ALIVE=30m"
   Environment="OLLAMA_MODELS=/models/ollama"
   ```

   Restart it, then pull a first model, e.g. `ollama pull gemma4:12b` (check exact tags at ollama.com/library). Run `ollama ps` while it answers; it should say 100% GPU.
7. **Add Open WebUI.** In a second LXC (or Docker in this one): `docker run -d -p 3000:8080 -e OLLAMA_BASE_URL=http://ai01:11434 -v open-webui:/app/backend/data --name open-webui --restart always ghcr.io/open-webui/open-webui:main`. The first account you create is the admin.
8. **Lock down access.** Install Tailscale in the containers, keep ports 11434 and 8080 off the internet, and firewall them to your LAN and tailnet. Add the containers to your existing NAS backup jobs.
9. **Add n8n** in its own LXC when you are ready for automations (see "Wiring up agents").

Gotcha: a host kernel or driver update can break the container's GPU until you reinstall the matching driver inside it. Pin the driver or re-run step 5 after updates. Your host shows a non-production repository enabled and kernel 7.0; NVIDIA's driver can lag the newest kernels, so pin a kernel that builds cleanly (`proxmox-boot-tool kernel pin`).

### Running big MoE models with llama.cpp

Ollama's automatic GPU/CPU split is much slower for big MoE models; one test got 9.8 tok/s from Ollama and 22 tok/s from tuned llama.cpp on gpt-oss-120b ([Zenn](https://zenn.dev/kota_iizuka/articles/d5dbb66008305a)). Run `llama-server` beside Ollama in the same container:

1. **Build llama.cpp with CUDA:** `cmake -B build -DGGML_CUDA=ON && cmake --build build -j`. Download GGUFs from Hugging Face into `/models` (e.g. `ggml-org/gpt-oss-120b-GGUF`, `unsloth/Qwen3.6-35B-A3B-GGUF`).
2. **Start it with experts in RAM:**

   ```bash
   llama-server -m /models/gpt-oss-120b-mxfp4-00001-of-00003.gguf \
     -ngl 99 --n-cpu-moe 30 -c 32768 -fa on --jinja \
     -t 12 --host 0.0.0.0 --port 8080
   ```

   Lower `--n-cpu-moe` step by step until `nvidia-smi` shows the 3070 nearly full; each step moves more experts onto the GPU.
3. **Handle the two sockets.** Memory on the other socket is slower to reach. Benchmark `numactl --cpunodebind=0 --membind=0` with `-t 12` against `--numa distribute` with `-t 24` and keep the faster one.
4. **Point clients at it.** `http://ai01:8080/v1` is OpenAI-compatible for n8n and Open WebUI. Run it as a systemd service so it starts with the container.

## Setup guide: MacBook Pro

Use a runtime built on Apple's MLX engine; it runs MoE models like Qwen3.6-35B-A3B about twice as fast as the older llama.cpp/Metal path. Plan on 30 minutes.

1. **Confirm the chip and memory.** Apple menu → About This Mac. 36 GB means M3 Pro or Max (the 35B-A3B pick); 24 GB means base M3 (stick to Gemma 4 E4B or 26B-A4B and close other apps).
2. **Install Ollama** from ollama.com (version 0.19 or later). Ollama 0.19 [moved to MLX on Apple Silicon](https://registry.ollama.ai/blog/mlx) in preview in March 2026; at launch the MLX path needed 32 GB+ of memory and only some models used it, so check `ollama serve` output for an MLX line.
3. **Or install LM Studio** as the fallback. It has a GUI, picks MLX builds directly and serves an OpenAI- and Anthropic-compatible API on `localhost:1234`. Use whichever is faster on your Mac.
4. **Pull the model.** `ollama pull qwen3.6:35b-a3b` (confirm the tag on ollama.com/library), or in LM Studio search `mlx-community/Qwen3.6-35B-A3B-4bit`.
5. **Raise the context for agents.** Agent tools need 32K+ tokens of context. Set `OLLAMA_CONTEXT_LENGTH=32768` for the Ollama app, or set context length on the model in LM Studio. Larger context uses more memory, so watch Activity Monitor's memory pressure.
6. **Optional: let the GPU use more memory.** `sudo sysctl iogpu.wired_limit_mb=28672` on a 36 GB Mac lets models use ~28 GB until reboot. Leave at least 6–8 GB for macOS.

Laptop realities: the Mac stops serving when it sleeps or the lid closes, runs hot and loud under sustained load, and drains the battery quickly. Treat it as an interactive workstation; put anything that must run overnight on the server.

## Wiring up agents

**Claude Code on a local model.** Ollama 0.14+ exposes the [Anthropic Messages API](https://registry.ollama.ai/blog/claude), so Claude Code runs against it with environment variables. Add an alias so normal `claude` stays on your subscription:

```bash
alias claude-local='ANTHROPIC_BASE_URL=http://localhost:11434 \
  ANTHROPIC_AUTH_TOKEN=ollama ANTHROPIC_API_KEY="" \
  ANTHROPIC_DEFAULT_OPUS_MODEL=qwen3.6:35b-a3b \
  ANTHROPIC_DEFAULT_SONNET_MODEL=qwen3.6:35b-a3b \
  ANTHROPIC_DEFAULT_HAIKU_MODEL=qwen3.6:35b-a3b \
  claude --model qwen3.6:35b-a3b'
```

Point the base URL at `http://ai01:11434` to use the server instead; `ollama launch claude` does the same setup in one command. Hosted features such as web search do not work in this mode ([setup notes](https://www.developersdigest.tech/setup/ollama/claude-code)).

**OpenCode** is the open-source alternative agent; add Ollama as a provider and you get a second agent that never touches your Claude quota. Useful for running a local agent in parallel with a Claude session.

**n8n for background agents.** Run n8n in its own LXC and use its Ollama or OpenAI-compatible model node pointed at `http://ai01:11434` (small models) or `http://ai01:8080/v1` (big MoE models). Starter workflows worth building:

- Draft resale listings (title, description, condition) from product photos dropped in a NAS folder, using a vision model.
- Summarize and tag new email or form submissions for the market booth business each morning.
- Clean up audiobook metadata: read filenames and folder names, propose author/title/series, write a rename plan for your PowerShell script to apply.
- Nightly digest of NAS backup and Proxmox logs: flag errors only.

**Private docs (RAG).** In Open WebUI, create a Knowledge collection, upload PDFs, manuals and notes, and pull a small embedding model in Ollama (e.g. `nomic-embed-text`). Chats can then cite your files without anything leaving the house.

**Vision.** Qwen3.6 and Gemma 4 read images natively: attach a screenshot or photo in Open WebUI, or send images through the API in n8n. Gemma 4 E2B/E4B also accept audio.

**Transcription.** On the Mac, `uvx parakeet-mlx file.m4a` runs NVIDIA's Parakeet model on MLX. On the server, use faster-whisper or Open WebUI's built-in speech-to-text. [Parakeet TDT 0.6B v3](https://openwhispr.com/blog/parakeet-vs-whisper-vs-nemotron) edges out Whisper large-v3 on English accuracy and is much faster; use Whisper for languages beyond English and European ones.

## Workload expectations

Expect local agents to take over the repetitive, well-defined work and leave the hard reasoning to Claude. Quality on your hardware sits well below Claude for long autonomous coding; the open-weight models that rival frontier coding scores (GLM-5, Kimi K2.5, MiniMax M2.5) are [hundreds of billions of parameters](https://www.tembo.io/blog/best-local-llm-for-coding) and need multi-GPU servers.

| Workload | Local fit | Best machine | What it feels like |
| --- | --- | --- | --- |
| Summaries, tagging, extraction, classification | Excellent | Server | Reliable with a clear prompt and a JSON schema |
| Chat and Q&A over your docs | Good | Server or Mac | Fine for lookup; weaker at synthesis across many files |
| Transcription | Excellent | Either | An hour of audio in minutes |
| Vision: photos, receipts, screenshots | Good | Mac, or server with Gemma E4B | Reads text and objects well; double-check numbers |
| One-file scripts, PowerShell, explaining code | Good | Mac (35B-A3B) | Usually right first or second try |
| Batch reasoning jobs (120B-class) | Good | Server, llama.cpp | Slow but capable; fine when nobody is waiting |
| Multi-file agentic coding | Fair to poor | Mac | Loses track on long tool loops; keep tasks small or use Claude |
| Small 8–9B models as coders | Poor | — | Fine for autocomplete, not for autonomous edits ([source](https://aiaggregator-com.pages.dev/local-coding/)) |

Speed in practice:

- **Output:** ~37–39 tokens/sec on the Mac means a 500-word answer in about 20 seconds, or roughly 130K output tokens an hour flat out.
- **First response in agents is the slow part.** Agent tools send a large system prompt plus files, often 10K–30K tokens. At ~500 tokens/sec of prompt reading on the Mac, that is 20–60 seconds before the first word; on the server in GPU+RAM mode it can be minutes. Later turns are faster because the prompt stays cached.
- **Concurrency:** one model per machine, shared. Running 2 requests at once gives about 1.6x total throughput and 4 gives about 2.2x on an M3 Pro, so each agent slows down ([oMLX batching](https://omlx.ai/benchmarks/5xm409jk)). Plan on 2 agents per machine.
- **Context:** keep agent context at 16K–32K on the 3070 and 32K–64K on the 36 GB Mac. Bigger context costs memory and speed.

What breaks most often: a model that silently falls back to CPU (check `ollama ps`), context set too small so the agent forgets instructions, and tool calls with malformed JSON from smaller models. The fixes are model fit, a larger context setting, and a bigger model.

## Rollout checklist and upgrade path

Start with the Mac tonight because it needs no infrastructure, then build the server, then add agents one at a time.

### Week 1: models running

- [ ] T640: check for the power interposer board, GPU cable and external GPU fans; check PSU wattage in iDRAC; run `dmidecode -t memory`; note the Mac's chip and memory
- [ ] Install the 3070 (or the P2000 if the power board is missing) and confirm it in `nvidia-smi`
- [ ] Mac: install Ollama or LM Studio, pull Qwen3.6-35B-A3B (or Gemma 4 on 24 GB), confirm ~35+ tok/s
- [ ] Proxmox: host driver, `ai01` LXC with the 3070, `/models` storage, Ollama, first model at 100% GPU
- [ ] Open WebUI connected to both Ollama endpoints; Tailscale on everything

### Week 2: agents and big models

- [ ] `claude-local` alias working against the Mac and against `ai01`
- [ ] llama.cpp on `ai01` running gpt-oss-120b or Qwen3.6-35B-A3B with `--n-cpu-moe`; record `llama-bench` numbers
- [ ] Try OpenCode on a small repo or your PowerShell scripts
- [ ] One Open WebUI Knowledge collection with real documents
- [ ] n8n LXC with one scheduled workflow (log digest or listing drafts)

### Weeks 3–4: decide

- [ ] Keep a short log of tasks sent local vs Claude, and which local results you had to redo
- [ ] Move the jobs local handles well into n8n; leave the rest on Claude
- [ ] Decide on the RTX 3090 based on how often the 3070 was the bottleneck

### Upgrade path, in order of value

1. **A used RTX 3090 24 GB (~$650–900)** as the server's main card: a 2-slot blower model for the T640, power-capped to 300 W. It runs Qwen3.6-35B-A3B fully on the GPU and makes the server a real backend for interactive agents. Keep the 3070 for a second container (small model, Whisper) if the chassis has a second slot and power.
2. **Fill all six memory channels per socket** if `dmidecode` shows gaps. Bandwidth, not capacity, sets GPU+RAM MoE speed, and you already have plenty of capacity.
3. **A second 24 GB card** later, to keep more of a 120B-class model on the GPU.
4. **A Mac with 64 GB+** (Mac mini or Studio as an always-on box) for bigger models with long context. The MacBook's memory cannot be upgraded.

## Sources

Speeds are community benchmarks and vendor or reviewer figures; your numbers will vary with quantization, context and runtime version. Model tags should be confirmed on ollama.com/library.

- [oMLX: Qwen3.6-35B-A3B on M3 Pro 36 GB](https://omlx.ai/benchmarks/rnvweq15) and [batching results](https://omlx.ai/benchmarks/5xm409jk)
- [Ollama: MLX on Apple Silicon (preview)](https://registry.ollama.ai/blog/mlx)
- [Ollama: Claude Code with Anthropic API compatibility](https://registry.ollama.ai/blog/claude)
- [Developers Digest: Ollama + Claude Code setup and caveats](https://www.developersdigest.tech/setup/ollama/claude-code)
- [Unsloth: Gemma 4, how to run locally](https://unsloth.ai/docs/models/gemma-4)
- [Google: Gemma 4 sizes and memory](https://ai.google.dev/gemma/docs/core)
- [OraCore: Qwen3.6-35B-A3B release](https://oracore.dev/news/qwen36-35b-a3b-open-source-agentic-coding-en)
- [SpecPicks: Qwen3.6-35B-A3B vs Gemma 4 26B-A4B on RTX 3060 12 GB](https://specpicks.com/reviews/qwen36-35b-a3b-vs-gemma4-26b-rtx-3060-12gb-2026)
- [SpecPicks: used RTX 3090 for local LLMs in 2026](https://specpicks.com/reviews/used-rtx-3090-local-llm-2026-buy-service-benchmark)
- [HomelabPicks: best GPU for local LLMs](https://homelabpicks-com.pages.dev/gpu-ai/best-gpu-local-llms)
- [ComputingForGeeks: RTX 3090 vs 5090 for local AI](https://computingforgeeks.com/rtx-3090-vs-5090-for-local-ai/)
- [BestLLMfor: best LLM for 12 GB VRAM](https://bestllmfor.com/best/vram-12gb/)
- [PromptQuorum: budget GPUs for local LLMs](https://www.promptquorum.com/local-llms/best-budget-gpus-local-llm)
- [LocalAI Master: GTX 1080 Ti and Tesla P40 after CUDA 13](https://localaimaster.com/blog/pascal-gpus-after-cuda-13)
- [TweakTown: 580 driver branch is the last for GTX 10 series](https://www.tweaktown.com/news/106148/game-ready-driver-support-for-the-iconic-geforce-gtx-1080-ti-to-end-soon/index.html)
- [Zenn: gpt-oss-120b with llama.cpp --n-cpu-moe vs Ollama](https://zenn.dev/kota_iizuka/articles/d5dbb66008305a)
- [Video summary: dual Xeon E5-2680 v4 CPU-only MoE benchmarks](https://youtubesummary.com/summary/mUZQlG-I5fA)
- [AI Aggregator: local coding by hardware tier](https://aiaggregator-com.pages.dev/local-coding/)
- [Tembo: best local LLM for coding](https://www.tembo.io/blog/best-local-llm-for-coding)
- [OpenWhispr: Parakeet vs Whisper vs Nemotron](https://openwhispr.com/blog/parakeet-vs-whisper-vs-nemotron)
- [DevHandbook: Ollama on Proxmox LXC](https://devhandbook-io.pages.dev/blog/ollama-proxmox-lxc)
- [Proxmox forum: NVIDIA LXC passthrough guide](https://forum.proxmox.com/posts/854368/)
- [Dell community: T640 GPU limits (4x double-wide, 300 W)](https://dell.com/community/en/conversations/poweredge-hardware-general/dell-poweredge-t-series-with-nvidia-tesla-p100/669cee91b539c16d2f9f186b)
- [Dell community: T640 GPUs and rack configuration](https://www.dell.com/community/en/conversations/poweredge-hardware-general/t640-gpu/647f945ff4ccf8a8de6a7377)
- [Dell community: T640 GPU kit and power interposer board](https://www.dell.com/community/Rack-Servers/GPU-installation-PowerEdge-T640-GPU-Kit/td-p/7279480)
- [T640 Installation and Service Manual: GPU guidelines](https://www.manualowl.com/m/Dell/PowerEdge-T640/Manual/593064?page=125)
- [DRXPD T630/T640 GPU power cable](https://expresscomputersystems.com/products/drxpd)
