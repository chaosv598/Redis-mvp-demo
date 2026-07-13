# Redis Network Optimization Features

## Project Brand Name

Kunpeng BoostKit Redis

## Change Notification

- [2026-03-05] Reconstructed `README`.
- [2025-03-30] Released the user guide and release notes for the Redis network asynchronization feature.
- [2025-02-28] Supported the network asynchronous optimization capability of Redis 7.0.15.

## Project Introduction

This repository provides content related to Redis network asynchronization. The core capability is the Kunpeng Redis Asynchronous I/O (KRAIO) solution and its patches.

Asynchronous batch processing of Redis network I/O operations can reduce system calls and context switching, thus improving throughput. Currently, this repository provides the adaptation patches and documents for Redis 6.0.20 and 7.0.15.

## Directory Structure

```text
.
├── README.md
├── LICENSE.txt
├── redis-6.0.20-adapt-iouring.patch
├── redis-7.0.15-adapt-iouring.patch
├── redis-7.0.15-adapt-dtoe.patch
└── docs
    ├── LICENSE
    ├── en
    │   ├── redis_network_async_optimization_feature_guide.md
    │   ├── redis_network_async_optimization_release_notes.md
    │   ├── redis_sockmap_optimization_feature_guide.md
    │   └── redis_sockmap_optimization_release_notes.md
```

## Feature Overview

### Redis 6.0.20 Network Asynchronization

- Feature guide: `docs/en/redis_network_async_optimization_feature_guide.md`
- Adaptation patch: `redis-6.0.20-adapt-iouring.patch`

### Redis 7.0.15 Network Asynchronization

- Feature guide: `docs/en/redis_network_async_optimization_feature_guide.md`
- Adaptation patch: `redis-7.0.15-adapt-iouring.patch`
- Additional patch: `redis-7.0.15-adapt-dtoe.patch`

### Redis Sockmap Optimization

- Feature guide: `docs/en/redis_sockmap_optimization_feature_guide.md`
- Release notes: `docs/en/redis_sockmap_optimization_release_notes.md`

## Release Notes

The release notes include the software version mapping, feature changes, and issue description. For details, see:

- `docs/en/redis_network_async_optimization_release_notes.md`

## Quick Start

The following uses Redis 7.0.15 as an example.

```bash
# (1) Prepare kraio and install the library file.
cd kraio
make -j4
cp ./libkraio.so /usr/lib64
cp ./include/kraio.h /usr/include

# (2) Apply the patch and compile Redis.
cd /path/to/redis-7.0.15
cp /path/to/Redis/redis-7.0.15-adapt-iouring.patch .
patch -p1 < redis-7.0.15-adapt-iouring.patch
make distclean
make -j
```

For details about the environment preparation, configuration, and verification, see:

- `docs/en/redis_network_async_optimization_feature_guide.md`

## Related Documents

| Document| Description|
|--|--|
| `docs/en/redis_network_async_optimization_feature_guide.md` | Feature description, environment deployment, and verification process|
| `docs/en/redis_network_async_optimization_release_notes.md` | Version mapping and change description|
| `docs/en/redis_sockmap_optimization_feature_guide.md` | Sockmap optimization feature description|
| `docs/en/redis_sockmap_optimization_release_notes.md` | Sockmap optimization version description|

## Compatibility Information

| Component| Version|
|--|--|
| OS | openEuler 22.03 LTS SP4 |
| Redis | 6.0.20 / 7.0.15 |
| Kernel (example)| kernel-5.10.0-275.0.0.178.oe2203sp4.aarch64.rpm |

## Constraints and Precautions

- This repository provides only patches and documents related to Redis network asynchronization, and does not provide the complete Redis source code.
- Ensure that the system environment and kernel version meet the requirements specified in the documents.
- The actual performance result is closely related to the hardware specifications, network topology, and stress test methods. Ensure that the environment is aligned with the suggestions in the documents.

## Contribution Statement

You are welcome to submit issues or pull requests (PRs) to provide your feedback and suggestions. Before submitting code, ensure that:

- The changes are related to Redis network asynchronization.
- The document version is consistent with the patch version.
- Reproducible verification description is provided for key changes.

## Disclaimer

- The content of this repository is used for open-source technology communication and optimization practice reference.
- Users need to evaluate the adaptability and risks in their production environments.
- The version changes in the upstream Redis community may affect the availability of the patches in this repository.

## License

- Repository code license: See `LICENSE.txt`.
- Repository document license: See `docs/LICENSE`.
- The documents of this project are licensed under CC-BY 4.0. For details, see LICENSE.
