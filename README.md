# Setscry

A native macOS app that tells you what is actually inside a folder of images — duplicates, near-duplicates, corrupt files, label imbalance, and train/test leakage — entirely on-device.

Drop a folder in. Setscry reads every file once, then breaks the findings into focused views instead of one overwhelming table. Nothing is uploaded, and nothing is deleted without you confirming it.

## What it finds

| View | What it means |
| --- | --- |
| **Overview** | A few individually meaningful numbers — not one invented "quality score" |
| **Exact duplicates** | Byte-identical files, grouped, with the space you would reclaim |
| **Near duplicates** | The same picture resized, re-compressed or lightly edited |
| **Unreadable** | Empty, truncated and corrupt files that would fail during training |
| **Labels** | Class balance read from folder names, with an imbalance ratio |
| **Split leakage** | One image appearing in more than one split, which quietly inflates reported accuracy |

And, once a local CLIP model is downloaded:

| View | What it means |
| --- | --- |
| **Search** | Find images by describing them, not by filename |
| **Clusters** | Groups of images that look alike, which is how overrepresented subjects show up |
| **Label check** | Images that sit closer to another label's images than to their own |

Exact duplicates and corruption are deterministic facts. Everything else is presented as a suggestion to confirm, and removal always goes to the Trash so it can be undone. The sidebar keeps the two kinds of finding apart.

Every image is clickable wherever it appears: click for a full-size look with its
metadata and the findings it takes part in, or right-click for Quick Look, Reveal
in Finder, Copy Path and — once the model is loaded — "Find Similar Images",
which ranks the whole folder against that one picture without another model run.
The Overview's numbers are buttons that jump to the section they describe.

## Running it

Requires macOS 15 or later and Swift 6.

```sh
swift run -c release Setscry                            # opens the drop zone
swift run -c release Setscry --folder ~/datasets/cats   # opens a folder straight away
swift test                                             # 46 tests, no network, no checked-in fixtures
```

`⌘O` opens a folder, the File menu keeps a Recent list, and `⌘1`–`⌘9` jump
between sections.

Use `-c release` for real folders. Debug builds run the model about six times slower, because MLX's C++ is compiled unoptimised along with everything else.

### Enabling the model-backed views

MLX needs its Metal kernels compiled into `mlx.metallib`, and it will not start
without them — not even on the CPU. Since Xcode 26 the Metal compiler is no
longer bundled, and `swift build` never invokes it anyway, so a command-line
build has no kernels.

Either option works; the script is smaller and needs no Xcode components:

```sh
# Option A — fetch Apple's prebuilt kernels (~50 MB), pinned to the exact
# MLX version mlx-swift vendors.
swift build -c release
./Scripts/fetch-mlx-metallib.sh

# Option B — install the Metal compiler itself (~700 MB) and build in Xcode,
# which then compiles the kernels for you.
xcodebuild -downloadComponent MetalToolchain
```

Without this the app still works completely — the deterministic views are
unaffected, and the model-backed ones explain what is missing instead of
crashing. `swift test` also passes either way; the model tests skip themselves.

The CLIP weights (~600 MB) are downloaded on first use, only after you ask for
them, and cached under `~/Library/Application Support/Setscry/Models`.

## How it works

```
folder → scan (metadata, SHA-256, decode check, perceptual hash, colour signature)
       → analysis (duplicate grouping, leakage, health)
       → optional: CLIP embeddings → search, clusters, label checks
       → SwiftUI views
```

Four targets, with the dependency arrow pointing one way:

- **`SetscryCore`** — all the deterministic analysis. No AppKit, no SwiftUI, no ML. Value types only, so every finding is testable without a screen or a model.
- **`SetscryML`** — the model seam, and dependency-free on purpose. `EmbeddingProvider` is the whole interface; clustering, label checks and vector search are written against `Embedding`, so they never learn which model produced it. `FeaturePrintEmbedder` uses the feature print built into macOS and needs no download.
- **`SetscryMLX`** — a CLIP dual encoder on MLX, conforming to `TextEmbeddingProvider`. The only target that knows MLX exists. Swapping in a different checkpoint is a `CLIPModelSource` away; swapping in a different architecture means one new conformance.
- **`Setscry`** — the SwiftUI app. `AppModel` owns the deterministic half and `SemanticModel` the model-backed half, so the app runs fully with the second one switched off.

### Duplicate detection

Two signals, because either alone is wrong:

- A **64-bit dHash** compares brightness structure, so it survives resizing and re-encoding. It is also colourblind, which means on its own it treats every recolouring of one design as the same image.
- A **4×4 colour signature** catches exactly that case.

Two images are treated as the same picture only when they agree on both. Measured against real files, genuine resized copies score a colour distance of 0 while recoloured variants of one design score 20–89, so the threshold of 12 sits in open space.

Byte-identical files satisfy both conditions automatically, so exact copies always cluster.

### Leakage

Leakage runs over every usable record rather than one representative per duplicate family. Collapsing duplicates first would hide the single most important case — an identical file copied into both `train` and `test`. Findings are grouped per image rather than per pair, so a file copied three times across two splits is reported once, as one leaked image.

Labels and splits come from folder names (`root/train/tabby/001.jpg`), and anything that does not fit that shape is reported as unlabeled rather than guessed at.

### The CLIP port

`SetscryMLX` implements CLIP's text and vision towers directly against MLX rather
than pulling in a model runtime. Both are small, and writing them out keeps the
parts that are easy to get quietly wrong visible:

- Modules use the checkpoint's own parameter names (`q_proj`, `pre_layrnorm`
  typo included), so weights load by name with no remapping table to drift.
  Loading verifies with `.all`, which fails loudly on a missing, unused or
  mis-shaped parameter instead of producing plausible nonsense.
- The activation is read from `config.json`: OpenAI's checkpoints use
  `quick_gelu`, LAION's use `gelu`, and the wrong one degrades every result
  without any error.
- Inference runs in float16. That needs a causal mask whose masked value is
  finite in the type — the usual `-1e9` is already infinity in half precision,
  which makes the *unmasked* entries `0 × infinity`, and every text embedding
  comes back `NaN` while images keep working.
- Images are decoded straight to the size the model needs, with the limit
  derived from the aspect ratio so wide images are not upscaled back.

The default checkpoint is LAION's ViT-B/32 (`laion/CLIP-ViT-B-32-laion2B-s34B-b79K`).

## Performance notes

Scanning hashes and decodes files concurrently but bounded, so a folder of 100,000 images does not open 100,000 file handles. Corruption checking and perceptual hashing share one thumbnail decode rather than decoding twice.

Embedding runs at roughly **150 images/sec** in a release build on an M-series Mac (900×700 JPEGs, batches of 16) — about eleven minutes for 100,000 images. Decoding happens concurrently across cores while the model runs, which matters most on large photographs: on 36-megapixel HEICs, decoding costs more than the forward pass does.

Similarity comparison is pairwise, which is fine into the tens of thousands of images. Past that, a metric-tree index over the hashes is the next step. Vector search is exact brute force for the same reason.

