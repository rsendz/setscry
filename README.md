<img src="Assets/icon-512.png" width="128" alt="">

# Setscry

A native macOS app that tells you what is actually inside a folder of images — duplicates, near-duplicates, files that won't open, lopsided folders, and train/test leakage — entirely on-device.

Drop a folder in. Setscry reads every file once, then breaks the findings into focused views instead of one overwhelming table. Nothing is uploaded, and nothing is deleted without you confirming it.

![CI](https://github.com/luisresendez/setscry/actions/workflows/ci.yml/badge.svg)

## What it finds

| View | What it means |
| --- | --- |
| **Overview** | A few individually meaningful numbers — not one invented "quality score" |
| **Exact duplicates** | Byte-identical files, grouped, with the space you would reclaim |
| **Near duplicates** | The same picture resized, re-compressed or lightly edited |
| **Won't open** | Empty, truncated and corrupt files |
| **Folder balance** | How many images are in each subfolder, with an imbalance ratio |
| **Split leakage** | One image appearing in more than one split, which quietly inflates reported accuracy |

And, once the images have been read by a model:

| View | What it means |
| --- | --- |
| **Search** | Find images by describing them, not by filename |
| **Clusters** | Groups of images that look alike, which is how overrepresented subjects show up |
| **Label check** | Images that sit closer to another folder's images than to their own |

Exact duplicates and corruption are deterministic facts. Everything else is presented as a suggestion to confirm, and removal always goes to the Trash so it can be undone. The sidebar keeps the two kinds of finding apart.

Every image is clickable wherever it appears: click for a full-size look with its
metadata and the findings it takes part in, or right-click for Quick Look, Reveal
in Finder, Copy Path and "Find Similar Images", which ranks the whole folder
against that one picture without another model run. The Overview's numbers are
buttons that jump to the section they describe, and `⌘E` exports everything as a
CSV to filter or a self-contained HTML page to send someone.

## Installing it

Download the latest zip from [Releases](../../releases), unzip it, and drag
**Setscry.app** to Applications. Requires macOS 15 or later on Apple silicon.

This is a personal project signed ad-hoc rather than notarized, so macOS
quarantines the download and the first launch needs one extra step: open it,
then allow it under **System Settings ▸ Privacy & Security**. Or, from a
terminal:

```sh
xattr -dr com.apple.quarantine /Applications/Setscry.app
```

Apple silicon only, deliberately: MLX's Metal backend does not support Intel
Macs, so a universal build would ship a half where the model-backed views could
never work.

## Building it

Requires macOS 15 or later and Swift 6.

```sh
swift run -c release Setscry                            # opens the drop zone
swift run -c release Setscry --folder ~/datasets/cats   # opens a folder straight away
swift test                                              # 59 tests, no network, no checked-in fixtures

./Scripts/make-app.sh 1.1                               # build Setscry.app and a zip
```

`⌘O` opens a folder, the File menu keeps a Recent list, and `⌘1`–`⌘9` jump
between sections. `⌘?` explains what everything does.

Use `-c release` for real folders. Debug builds run the model about six times slower, because MLX's C++ is compiled unoptimised along with everything else.

### Reading images with a model

The model-backed views work out of the box: by default Setscry uses the image
feature print built into macOS, which needs no download and nothing to set up.

CLIP is offered as an upgrade, because it is what makes searching by description
possible. It downloads about 606 MB on first use, only after you ask for it, and
is cached under `~/Library/Application Support/Setscry/Models`. Either model's
vectors are cached, so reopening a folder is close to instant — see below.

CLIP runs on MLX, which needs its Metal kernels compiled into `mlx.metallib` and
will not start without them, not even on the CPU. Since Xcode 26 the Metal
compiler is no longer bundled, and `swift build` never invokes it anyway, so a
command-line build has no kernels. `Scripts/make-app.sh` handles this for the
packaged app; for a source build, either option works:

```sh
# Option A — fetch Apple's prebuilt kernels (~50 MB), pinned to the exact
# MLX version mlx-swift vendors.
swift build -c release
./Scripts/fetch-mlx-metallib.sh

# Option B — install the Metal compiler itself (~700 MB) and build in Xcode,
# which then compiles the kernels for you.
xcodebuild -downloadComponent MetalToolchain
```

Without the kernels the app still works completely: the deterministic views are
unaffected, the built-in model still reads images, and only CLIP explains that it
is unavailable instead of crashing. `swift test` passes either way; the MLX tests
skip themselves.

## How it works

```
folder → scan (metadata, SHA-256, decode check, perceptual hash, colour signature)
       → analysis (duplicate grouping, leakage, health)
       → embeddings (Vision feature print, or CLIP) → search, clusters, label checks
       → SwiftUI views
```

Four targets, with the dependency arrow pointing one way:

- **`SetscryCore`** — all the deterministic analysis. No AppKit, no SwiftUI, no ML. Value types only, so every finding is testable without a screen or a model.
- **`SetscryML`** — the model seam, and dependency-free on purpose. `EmbeddingProvider` is the whole interface; clustering, label checks and vector search are written against `Embedding`, so they never learn which model produced it. `FeaturePrintEmbedder` uses the feature print built into macOS and needs no download.
- **`SetscryMLX`** — a CLIP dual encoder on MLX, conforming to `TextEmbeddingProvider`. The only target that knows MLX exists. Swapping in a different checkpoint is a `CLIPModelSource` away; swapping in a different architecture means one new conformance.
- **`Setscry`** — the SwiftUI app. `AppModel` owns the deterministic half and `SemanticModel` the model-backed half, so the app runs fully with the second one switched off.

### The embedding cache

Reading a large folder with a model is the slowest thing Setscry does, and doing
it again on every reopen was the main thing standing between it and real use. The
vectors are now written to
`~/Library/Application Support/Setscry/Embeddings/<model>.embeddings` as a
128-byte header followed by fixed-size records, so appending is a seek and a
write and reading is arithmetic rather than parsing.

The key is the SHA-256 the scan already computes, which buys more than surviving
a reopen: renaming a file, copying it, or moving it to another folder all land on
the same cached vector, because the key describes the bytes rather than the path.
Records are appended after every batch of sixteen, so quitting part-way through a
large folder keeps the work done so far. A record left half-written by that quit
is detected on load and the file is truncated back to alignment — without that,
every later append would be misaligned and the cache would return quiet garbage.

Each model gets its own file, so vectors made by different models can never be
compared to each other. **File ▸ Clear Cached Image Readings** says how much
space it is holding and throws it away.

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

Embedding runs at roughly **150 images/sec** in a release build on an M-series Mac (900×700 JPEGs, batches of 16) — about eleven minutes for 100,000 images, once. Decoding happens concurrently across cores while the model runs, which matters most on large photographs: on 36-megapixel HEICs, decoding costs more than the forward pass does.

Similarity comparison is pairwise, which is fine into the tens of thousands of images. Past that, a metric-tree index over the hashes is the next step. Vector search is exact brute force for the same reason.

### On size

- The **download is about 47 MB**, unpacking to a 142 MB app. Almost all of that is `mlx.metallib`, MLX's compiled Metal kernels; the binary itself is 16 MB stripped.
- The **CLIP model is 606 MB**, downloaded only if you choose it, and removable from within the app.
- The **cached vectors** are about 2 KB per image with CLIP, 3 KB with the built-in model, in one file you can delete from the File menu.
- A **source checkout builds to roughly 3 GB** under `.build`, because MLX's C++ is compiled twice (debug and release) and SourceKit keeps a third index tree. None of it ships. `swift package clean` reclaims it.

