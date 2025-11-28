# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FluidAudio is a comprehensive Swift framework for local, low-latency audio processing on Apple platforms. It provides state-of-the-art speaker diarization, automatic speech recognition (ASR), and voice activity detection (VAD) through open-source models converted to Core ML. The system processes audio to identify "who spoke when" by segmenting audio and clustering speaker embeddings, with industry-competitive performance (17.7% DER).

**⚠️ IMPORTANT: This is a Fork**

This repository is a fork of the original FluidAudio project (`github.com/FluidInference/FluidAudio`), specifically customized for **ManiApp** with single-model TTS mode.

**Fork Details:**
- **Repository**: `github.com/Tombo89S/FluidAudio`
- **Branch**: `fix/ios-filehandle-crash`
- **Purpose**: Enable single-model Kokoro TTS using ONLY `kokoro_24_10s.mlmodelc` (~310MB) instead of all variants (~620MB)
- **Status**: Phase 13J COMPLETE - Single-model mode fully working in production
- **Backwards Compatibility**: All modifications preserve compatibility for other projects using this fork

## Fork-Specific Modifications (Phase 13J - Single-Model TTS)

### What Changed

This fork implements **single-model mode** for Kokoro TTS, allowing applications to download and use only one variant instead of all three. This reduces initial download size by ~50% (from 620MB to 310MB).

### Key Implementation Details

**Four-iteration fix journey (commits):**
1. **Fix v1 (f215e13)**: Made `DownloadUtils.downloadRepo()` respect explicit `modelNames` parameter
2. **Fix v2 (832d38d)**: Prevented `tokenLength()` from auto-loading models
3. **Fix v3 (1f25250)**: Prevented `loadModelsIfNeeded()` from auto-downloading when `variants=nil`
4. **Fix v4 (3039342)**: **FINAL** - Query `modelCache` directly instead of guessing variant from capacity

**Root cause solved in Fix v4:**
- `kokoro_24_10s.mlmodelc` has an input shape of **242 tokens** (not 150 as expected)
- Previous code guessed variant using hardcoded thresholds: `if capacity > 150` → `.fifteenSecond`
- This caused incorrect variant selection even though only `.tenSecond` was loaded
- **Solution**: Query `modelCache.getLoadedVariants()` directly instead of inferring from capacity

### Modified Files in Fork

1. **Sources/FluidAudio/ModelNames.swift**
   - Added `.tenSecond` case to `TTS.Variant` enum
   - Maps to `kokoro_24_10s.mlmodelc`
   - Max duration: 10 seconds

2. **Sources/FluidAudio/TextToSpeech/Kokoro/Pipeline/Preprocess/KokoroModelCache.swift**
   - Added `getLoadedVariants()` method - Query which models are loaded without triggering downloads
   - Modified `loadModelsIfNeeded()` to distinguish explicit vs implicit requests
   - Modified `tokenLength()` to prevent auto-loading missing models

3. **Sources/FluidAudio/TextToSpeech/Kokoro/Pipeline/Synthesize/KokoroSynthesizer.swift**
   - Modified `selectVariant()` to query cache instead of guessing from capacity (Fix v4)
   - Made `selectVariant()` async and propagated through call chain
   - Enhanced `capacities()` with single-model detection
   - Added logging for debugging variant selection

4. **Sources/FluidAudio/TextToSpeech/DownloadUtils.swift**
   - Added `modelNames` parameter to `downloadRepo()`
   - Respects explicit model specification instead of downloading all variants

### Usage Pattern (ManiApp)

```swift
// Download ONLY the 10-second variant (~310MB)
let models = try await TtsModels.download(variants: [.tenSecond])
try await ttsManager.initialize(models: models)

// System automatically detects single-model mode
// All chunks use kokoro_24_10s.mlmodelc
// No additional downloads triggered
```

### Verification Logs (Success Indicators)

```
[INFO] Single-model mode detected: using 10s for all synthesis
[INFO] selectVariant() called: tokenCount=183, short=242, long=242
[INFO] Single-model mode: using loaded variant 10s
[INFO] Chunk 1 using Kokoro 10s model
[INFO] Chunk 2 using Kokoro 10s model
✅ AudioEncoder: Successfully encoded to M4A
```

### Storage Savings

| Configuration | Download Size | Models Included |
|--------------|---------------|-----------------|
| **All variants** (upstream) | ~620 MB | kokoro_21_5s, kokoro_24_10s, kokoro_21_15s |
| **Single variant** (this fork) | ~310 MB | kokoro_24_10s only |
| **Savings** | **~310 MB (50%)** | |

### When to Use Single-Model vs Multi-Model

**Use Single-Model Mode:**
- ✅ Mobile apps with storage constraints
- ✅ Short-to-medium content generation (most text fits in 10s chunks)
- ✅ Faster initial setup desired

**Use Multi-Model Mode:**
- ❌ Very long content (>10s per chunk without splitting)
- ❌ Desktop apps where storage isn't constrained
- ❌ Need optimal quality for varying text lengths

### Debugging Single-Model Issues

If you see unwanted model downloads:

1. **Check Initialization**
   ```swift
   // ✅ Correct
   let models = try await TtsModels.download(variants: [.tenSecond])

   // ❌ Wrong - downloads all
   let models = try await TtsModels.download()
   ```

2. **Check Logs for Capacity Values**
   ```
   [INFO] selectVariant() called: tokenCount=X, short=Y, long=Z
   ```
   - If `short == long` → single-model mode ✅
   - If `short != long` → multi-model mode detected ❌

3. **Check Variant Selection**
   - Should see "10s" consistently throughout ✅
   - If you see "15s" or "5s" → selectVariant() issue ❌

### Related Documentation

- **Implementation Plan**: `ManiDocs/claude-kokoro-24-10s-implementation.md`
- **Single-Model Spec**: `ManiDocs/phase-13j-single-model-implementation.md`
- **TTS Model Spec**: `ManiDocs/maniapp_tts_model_and_download_spec_latest.md`

## Critical Development Rules

### ⚠️ NEVER USE "unchecked Sendable"

- **DO NOT** use `@unchecked Sendable` under any circumstances
- Always properly implement thread-safe code with proper synchronization
- Use actors, `@MainActor`, or proper locking mechanisms instead
- If you encounter Sendable conformance issues, fix them properly rather than bypassing with `@unchecked`

### ⚠️ NEVER CREATE DUMMY MODELS OR SYNTHETIC DATA

- **DO NOT** create dummy, mock, or fake models for testing or development
- **DO NOT** generate synthetic audio data for testing
- **DO NOT** use random/fake models as placeholders
- **DO NOT** create "demonstration" or "simulated" models that don't contain real weights
- Always use the actual models required by the code
- If model authentication is required, inform the user rather than creating dummy versions
- Mock models produce meaningless results and waste development time
- Placeholder models with random weights will destroy performance (e.g., 17.8% → 77.1% DER)

### ⚠️ MODEL OPERATIONS - CONSULT BEFORE IMPLEMENTING

- When asked to merge, convert, or modify models:
  - If it seems impossible or I have significant objections, CONSULT YOU FIRST
  - Explain the concerns and let you decide whether to proceed
  - If you say proceed, then DO IT IMMEDIATELY without further objections
- **DO NOT** create demonstration or placeholder models without permission
- **DO NOT** implement alternatives without asking
- Only after your approval: Implementation, then explanation of results

### Code Style and Formatting

- **Swift Format**: This project uses swift-format for consistent code style
- **Configuration**: See `.swift-format` for style rules
- **Auto-formatting**: PRs are automatically checked for formatting compliance
- **Local formatting**: Run `swift format --in-place --recursive --configuration .swift-format Sources/ Tests/`

#### Style Guidelines
- **Line length**: 120 characters
- **Indentation**: 4 spaces
- **Import order**: `import CoreML`, `import Foundation`, `import OSLog` (OrderedImports rule)
- **Naming conventions**:
  - lowerCamelCase for variables/functions
  - UpperCamelCase for types
- **Error handling**: Use proper Swift error handling, no force unwrapping in production
- **Documentation**: Triple-slash comments (`///`) for public APIs
- **Thread safety**: Use actors, `@MainActor`, or proper locking - never `@unchecked Sendable`
- **Control flow**: Prefer flattened if statements with early returns/continues over nested if statements. Use guard statements and inverted conditions to exit early. Nested if statements should be absolutely avoided to improve readability and reduce cognitive complexity.

## Current Performance Status

- **Achieved**: 17.7% DER
- **Target**: < 30% DER
- **Competitive with**: State-of-the-art research (Powerset BCE: 18.5%)

### Optimal Configuration

```swift
DiarizerConfig(
    clusteringThreshold: 0.7,     // Optimal value: 17.7% DER
    minDurationOn: 1.0,           // Minimum speaker segment duration
    minDurationOff: 0.5,          // Minimum silence between speakers
    minActivityThreshold: 10.0,   // Minimum activity threshold
    debugMode: false
)
```

## Key Features

### 1. Speaker Diarization (Dual Pipeline Architecture)

**Streaming/Online Diarization** (`DiarizerManager`):
- Real-time speaker tracking with consistent IDs across chunks
- AHC (Agglomerative Hierarchical Clustering)
- Use case: Real-time transcription with speaker labels
- Performance: Fast, suitable for live processing

**Offline Diarization** (`OfflineDiarizerManager`):
- Batch processing with VBx clustering and PLDA transformation
- Enhanced accuracy through advanced clustering
- Use case: Post-processing complete recordings for best quality
- Performance: 18-20% DER on AMI-SDM with threshold 0.6
- Models: Powerset segmentation + WeSpeaker embeddings + VBx clustering

### 2. Auto-Recovery Mechanism
- Automatic detection and recovery from CoreML compilation failures
- Re-downloads corrupted models from Hugging Face
- Up to 3 retry attempts with comprehensive logging

### 3. Text-to-Speech (TTS) - Beta

**⚠️ Fork-Specific: Single-Model Mode**
- **Default Model**: `kokoro_24_10s.mlmodelc` (~310MB) - 10-second context window
- **Download Size**: ~310 MB (vs ~620 MB for all variants in upstream)
- **Status**: Beta - American English only, additional languages planned
- **Performance**: ~25x RTF on M4 Pro, ~2s warm-up after initial 15s compilation
- **Memory**: ~3.37 GB peak (MLX baseline), lower with CoreML
- **Output**: 24 kHz mono WAV format
- **G2P**: Dictionary-first, eSpeak NG fallback for OOV words

**Requirements (macOS):**
- eSpeak NG must be installed and discoverable via pkg-config
- Install: `brew install espeak-ng`
- Build with explicit paths if needed: `swift build -Xcc -I/opt/homebrew/include -Xlinker -L/opt/homebrew/lib`

**Key CLI Commands:**
```bash
# Basic synthesis with auto-download
swift run fluidaudio tts "Hello from FluidAudio." --auto-download --output out.wav

# Benchmark TTS performance
swift run fluidaudio tts --benchmark
```

**arm64-only Note**: Current TTS tooling ships arm64-only dependencies (ESpeakNG.xcframework)

## Essential Development Commands

### Core Commands
```bash
# Build
swift build                             # Debug build
swift build -c release                 # Release build (recommended for benchmarks)

# Test
swift test                             # Run all tests
swift test --parallel                  # Parallel test execution
swift test --filter CITests           # Run CI-specific tests only
swift test --filter AsrManagerTests   # Run specific test class

# Package management
swift package update                   # Update dependencies
swift package resolve                 # Resolve dependencies
swift package clean                   # Clean build cache
```

### Code Quality
```bash
# Format code (requires Swift 6+ for development)
swift format --in-place --recursive --configuration .swift-format Sources/ Tests/

# Check formatting without modifying
swift format lint --recursive --configuration .swift-format Sources/ Tests/

# Verify formatting compliance (CI-style check)
swift format --configuration .swift-format Sources/ Tests/
```

### CLI Commands

#### Benchmarking
```bash
# Diarization benchmarks
swift run fluidaudio diarization-benchmark --auto-download
swift run fluidaudio diarization-benchmark --single-file ES2004a --threshold 0.7 --output results.json

# Offline diarization (VBx pipeline)
swift run fluidaudio diarization-benchmark --mode offline --dataset ami-sdm --threshold 0.6

# ASR benchmarks
swift run fluidaudio asr-benchmark --subset test-clean --max-files 100
swift run fluidaudio asr-benchmark --subset test-other --output asr_results.json

# FLEURS multilingual benchmark
swift run fluidaudio fleurs-benchmark --languages en_us,fr_fr --samples 10

# VAD benchmark
swift run fluidaudio vad-benchmark --num-files 40 --threshold 0.5

# TTS benchmark
swift run fluidaudio tts --benchmark
```

#### Audio Processing
```bash
# Transcription
swift run fluidaudio transcribe audio.wav
swift run fluidaudio transcribe audio.wav --low-latency

# Multi-stream processing
swift run fluidaudio multi-stream audio1.wav audio2.wav

# Diarization processing (streaming)
swift run fluidaudio process meeting.wav --output results.json --threshold 0.6

# Diarization processing (offline/VBx)
swift run fluidaudio process meeting.wav --mode offline --threshold 0.6 --debug

# Text-to-speech
swift run fluidaudio tts "Hello world" --output out.wav
swift run fluidaudio tts "Your text" --auto-download --output speech.wav
```

#### Dataset Management
```bash
# Download evaluation datasets
swift run fluidaudio download --dataset ami-sdm
swift run fluidaudio download --dataset librispeech-test-clean
swift run fluidaudio download --dataset librispeech-test-other
```

## Parameter Tuning Guide

### DiarizerConfig Parameters

1. **clusteringThreshold** (0.0-1.0)
   - Sweet spot: 0.7-0.8
   - Impact: Speaker separation accuracy
   - 0.7 = 17.7% DER (optimal)

2. **minDurationOn** (seconds)
   - Default: 1.0
   - Filters short speech segments

3. **minDurationOff** (seconds)
   - Default: 0.5
   - Minimum gap between speakers

4. **minActivityThreshold** (frames)
   - Default: 10.0
   - Affects missed speech detection

## High-Level Architecture

### Project Structure
```
FluidAudio/
├── Sources/
│   ├── FluidAudio/           # Main library
│   │   ├── ASR/             # Automatic Speech Recognition
│   │   ├── Diarizer/        # Speaker diarization system
│   │   ├── VAD/             # Voice Activity Detection
│   │   ├── TextToSpeech/    # Kokoro TTS (fork-specific single-model mode)
│   │   └── Shared/          # Common utilities (audio conversion, memory optimization)
│   ├── FastClusterWrapper/  # C++ clustering library wrapper
│   └── FluidAudioCLI/       # Command-line interface (macOS only)
├── Tests/                   # Comprehensive test suite
├── ManiDocs/               # Fork-specific documentation (ManiApp integration)
└── Datasets/               # Evaluation datasets (AMI corpus)
```

### Core Components

#### 1. ASR (Automatic Speech Recognition)
- **AsrManager**: Main class for speech-to-text processing
- **TDT (Token Duration Transducer)**: Advanced decoding architecture with Token Duration tracking
- **Architecture**: Stateless processing with automatic decoder state reset after each transcription
- **Chunking Strategy**: Fixed-size chunks (~14.96s) with 2.0s overlap, stateless decoding per chunk
- **Token Merging**: Sophisticated algorithm using contiguous pair matching, LCS, or midpoint splitting
- **Models**: Parakeet TDT v3 (0.6b) supporting 25 European languages
- **Performance**: ~209.8x RTF on M4 Pro, 55.7% WER improvement with stateless approach

#### 2. Diarization System

**Streaming/Online (`DiarizerManager`):**
- Main orchestrator for real-time speaker separation
- SegmentationProcessor: Voice activity detection and segmentation
- EmbeddingExtractor: Speaker embedding generation for clustering
- SpeakerManager: Consistent speaker ID tracking across chunks
- Performance: Fast, suitable for live processing

**Offline/Batch (`OfflineDiarizerManager`):**
- VBx clustering with PLDA transformation
- Powerset segmentation for enhanced accuracy
- Performance: 18-20% DER on AMI-SDM (competitive with research)

#### 3. Voice Activity Detection
- **VadManager**: Voice activity detection with Silero CoreML models (Beta)
- **Streaming Support**: Real-time VAD with state management
- **Segmentation**: High-level speech segment extraction API

#### 4. Text-to-Speech (Beta - Fork-Specific)
- **TtSManager**: Main synthesis orchestrator using Kokoro CoreML model
- **KokoroSynthesizer**: Core synthesis engine with voice embedding management
- **KokoroModelCache**: Model caching with single-model mode support
- **LexiconAssetManager**: Dictionary-first G2P with eSpeak NG fallback
- **Single-Model Mode**: Download only `kokoro_24_10s.mlmodelc` (~310MB)
- **Voice Embeddings**: Cached in `~/.cache/fluidaudio/Models/kokoro`

#### 5. Shared Infrastructure
- **ANEMemoryOptimizer**: Apple Neural Engine memory management
- **AudioConverter**: Universal audio format conversion to 16kHz mono Float32
- **ModelDownloader**: Automatic model retrieval from HuggingFace with recovery
- **Zero-Copy Processing**: Efficient model chaining without data duplication

### Key Manager Classes

| Manager | Purpose | Availability | Platform |
|---------|---------|--------------|----------|
| `AsrManager` | Batch transcription (Parakeet TDT) | Stable | macOS 14+, iOS 17+ |
| `StreamingAsrManager` | Real-time transcription | Beta | macOS 14+, iOS 17+ |
| `DiarizerManager` | Streaming speaker diarization | Stable | macOS 14+, iOS 17+ |
| `OfflineDiarizerManager` | Batch speaker diarization (VBx) | Stable | macOS 14+, iOS 17+ |
| `VadManager` | Voice activity detection (Silero) | Beta | macOS 14+, iOS 17+ |
| `TtSManager` | Text-to-speech (Kokoro) | Beta (en-US only) | macOS 14+ (CLI macOS-only) |
| `SpeakerManager` | Speaker tracking and embedding clustering | Internal | macOS 14+, iOS 17+ |

### Processing Pipeline
1. **Audio Input** → AudioConverter (16kHz mono Float32)
2. **VAD Processing** → Voice activity segments
3. **Diarization** → Speaker embeddings + clustering
4. **ASR Processing** → Speech-to-text transcription
5. **TTS Processing** → Text-to-speech audio generation
6. **Output** → Timestamped speaker-attributed transcripts / Generated audio

### Threading and Concurrency
- **Actor-based Architecture**: Thread-safe processing without `@unchecked Sendable`
- **Stateless Decoding**: Each chunk transcribed independently with fresh decoder state
- **Automatic State Reset**: Decoder state reset after each `transcribe()` call for independent processing
- **Memory Management**: Automatic cleanup and ANE optimization
- **Batch Processing**: Optimized for sequential transcription of multiple files without state carryover

### Model Management
- **Automatic Downloads**: Models fetched from HuggingFace on first use
- **Auto-Recovery**: Corrupt model detection and re-download
- **CoreML Compilation**: Optimized for Apple Neural Engine
- **Caching**: Local model storage with validation
- **Single-Model TTS** (fork-specific): Download only required Kokoro variant

## Model Registry Configuration

By default, models download from HuggingFace. Override for mirrors/air-gapped environments:

**Programmatic override** (recommended for apps):
```swift
import FluidAudio
ModelRegistry.baseURL = "https://your-mirror.example.com"
let diarizer = DiarizerManager()
```

**Environment variables** (CLI/testing):
```bash
export REGISTRY_URL=https://your-mirror.example.com
# or
export MODEL_REGISTRY_URL=https://models.internal.corp

swift run fluidaudio transcribe audio.wav
```

**Proxy configuration** (corporate firewalls):
```bash
export https_proxy=http://proxy.company.com:8080
swift run fluidaudio transcribe audio.wav
```

## Architecture Notes

- **Stateless ASR**: Each chunk transcribed independently with automatic state reset
- **Chunk-based Processing**: Fixed ~14.96s chunks with 2.0s overlap for merging
- **Token Merging**: Three-tier strategy (contiguous pairs, LCS, midpoint split) handles chunk boundaries
- **Quality Improvement**: Stateless approach eliminates context pollution, yielding 55.7% WER reduction
- **Batch Processing**: Optimized for transcribing multiple files sequentially
- **Online diarization**: Works well with chunk-based processing
- **Offline diarization**: VBx clustering with PLDA for enhanced accuracy
- **Speaker tracking**: Effective across chunks
- **DER calculation**: Fixed with optimal speaker mapping (Hungarian algorithm)
- **Single-Model TTS**: Token capacity detection instead of hardcoded thresholds
- **Cross-platform**: Supports macOS 14.0+, iOS 17.0+ (library), CLI macOS-only

## Development Environment

### Requirements
- **Swift**: 5.10+ (Swift 6+ required for contributors using swift-format)
- **Platforms**: macOS 14.0+, iOS 17.0+
- **Xcode**: Latest stable version for iOS development
- **Hardware**: Apple Silicon recommended for optimal performance
- **TTS (macOS)**: eSpeak NG required for phonemization

### CI/CD Pipeline
The project uses GitHub Actions with the following workflows:
- **swift-format.yml**: Code formatting compliance checks
- **tests.yml**: Cross-platform build and test execution
- **asr-benchmark.yml**: ASR performance validation
- **diarizer-benchmark.yml**: Speaker diarization benchmarks (streaming)
- **offline-pipeline.yml**: Offline VBx pipeline benchmarks
- **vad-benchmark.yml**: Voice activity detection validation
- **tts-test.yml**: TTS synthesis validation

### Code Style Configuration
- **Swift Format**: Enforced via `.swift-format` config
- **Line Length**: 120 characters
- **Indentation**: 4 spaces
- **Formatting Rules**: Automatic via swift-format, CI enforced

## User Preferences

- Never start responses with positive re-affirming text like "You're absolutely right!", "Good change!", "Excellent progress!", or similar
- Get straight to the point with technical facts
- For debugging, use print statements and delete them at the end when instructed
- Never create fallbacks or simplified solutions that don't actually solve the problem
- Always go for the proper solution over the "simplified" solution
- When asked to implement something specific, DO IT FIRST before explaining why it might not be optimal - implementation first, explanation second
- Just do as instructed - don't try to over-do things that aren't asked

## Development Guidelines

1. **Testing**: Always run benchmarks on multiple files for validation
2. **Logging**: Use comprehensive logging for debugging
3. **Error Handling**: Implement graceful degradation
4. **Performance**: Keep RTFx > 1.0x for real-time capability
5. **Thread Safety**: Never use `@unchecked Sendable` - implement proper synchronization
6. **Follow Instructions**: When the user asks to implement something specific, DO IT FIRST before explaining why it might not be optimal. Implementation first, explanation second.
7. **Avoid Deprecated Code**: Do not add support for deprecated models or features unless explicitly requested. Keep the codebase clean by only supporting current versions.
8. **Testing Policy**: ONLY add or run tests when explicitly requested by the user
9. **Git Operations**: NEVER run `git push` unless explicitly requested by the user. Only commit when asked.
10. **Code Formatting**: All code must pass swift-format checks before merge
11. **Fork Awareness**: Remember this is a ManiApp-specific fork with single-model TTS modifications

## Testing Strategy

### Test Categories
- **Unit Tests**: Component-level testing for individual classes
- **Integration Tests**: End-to-end workflow validation
- **Performance Tests**: Benchmarking against standard datasets
- **Memory Tests**: ANE memory optimization validation
- **Edge Case Tests**: Boundary condition handling
- **CI Tests**: Smoke tests for continuous integration

### Key Test Classes
- **CITests**: Lightweight tests for CI pipeline
- **AsrManagerTests**: ASR functionality validation
- **DiarizerMemoryTests**: Memory management validation
- **SendableTests**: Thread safety compliance
- **SegmentationProcessorTests**: Audio segmentation accuracy
- **TTSManagerTests**: TTS synthesis validation (requires eSpeak NG)
- **StreamingAsrManagerTests**: Streaming transcription tests

### Running Specific Tests
```bash
# CI-specific tests (lightweight, no model downloads required)
swift test --filter CITests

# ASR component tests
swift test --filter AsrManagerTests

# Memory optimization tests
swift test --filter ANEMemoryOptimizerTests

# TTS tests (requires eSpeak NG)
swift test --filter TTSManagerTests

# Streaming tests
swift test --filter StreamingAsrManagerTests

# Edge case validation
swift test --filter EdgeCaseTests

# Run a single test method
swift test --filter CITests/testDiarizerCreation
```

## Model Sources

- **Diarization (Streaming)**: [pyannote/speaker-diarization-3.1](https://huggingface.co/pyannote/speaker-diarization-3.1)
- **Diarization (Offline)**: Community-1 pipeline (Powerset + WeSpeaker + VBx)
- **VAD CoreML**: [FluidInference/silero-vad-coreml](https://huggingface.co/FluidInference/silero-vad-coreml)
- **ASR Models**: [FluidInference/parakeet-tdt-0.6b-v3-coreml](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml)
- **TTS Model**: [FluidInference/kokoro-82m-coreml](https://huggingface.co/FluidInference/kokoro-82m-coreml) (fork uses `kokoro_24_10s` only)
- **Test Data**: [alexwengg/musan_mini*](https://huggingface.co/datasets/alexwengg) variants

## Fork-Specific Notes for Future Development

### Switching TTS Variants (If Needed)

To change ManiApp from `kokoro_24_10s` to a different variant:

1. Update variant specification in ManiApp integration:
   - `KokoroVoiceManager.swift` - Change `variants: [.tenSecond]` to desired variant
   - `KokoroModel.swift` - Change `variants: [.tenSecond]` to match

2. Update UI copy:
   - `AIVoiceSetupView.swift` - Adjust download size/time estimates:
     - `.fiveSecond`: ~310 MB, 3-4 min
     - `.tenSecond`: ~310 MB, 3-4 min (current)
     - `.fifteenSecond`: ~310 MB, 3-4 min

3. No FluidAudio fork changes needed - the fork treats all variants equally

### Critical Implementation Insights (Phase 13J)

1. **Never guess - always query**: Instead of inferring model variant from capacity thresholds, query the actual loaded models via `modelCache.getLoadedVariants()`

2. **Token capacities vary**: Model input shapes are not fixed at compile time. `kokoro_24_10s` has 242 tokens, not 150.

3. **Explicit vs Implicit requests matter**: Distinguish between user-initiated (`variants: [.tenSecond]`) and system-initiated (`loadModelsIfNeeded(variants: nil)`) model loading

4. **Single-model detection**: `shortCapacity == longCapacity` means one model loaded

5. **Async propagation required**: Making `selectVariant()` async required propagating async/await through the call chain

6. **Debug logging is essential**: The capacity mismatch (242 vs 150) was only discovered through detailed logging
