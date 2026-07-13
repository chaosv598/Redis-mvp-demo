# Redis 网络优化特性

## 项目品牌名称

Kunpeng BoostKit Redis

## 变更通知

- [2026.03.05]：重构README。
- [2025.03.30]：新增Redis网络异步优化特性使用指南和版本说明书。

## 项目介绍

本仓库提供 Redis 网络异步优化相关内容，核心能力是 KRAIO（Kunpeng Redis Asynchronous I/O）方案及其配套补丁。

通过将 Redis 网络 I/O 处理异步化、批量化，可减少系统调用与上下文切换，提升吞吐能力。当前仓库主要覆盖 Redis 6.0.20 和 Redis 7.0.15 两个版本的适配补丁与配套文档。

## 目录结构

```text
.
├── README.md
├── LICENSE.txt
├── redis-6.0.20-adapt-iouring.patch
├── redis-7.0.15-adapt-iouring.patch
├── redis-7.0.15-adapt-dtoe.patch
└── docs
    ├── LICENSE
    ├── zh
    │   ├── redis_network_async_optimization_feature_guide.md
    │   ├── redis_network_async_optimization_release_notes.md
    │   ├── redis_sockmap_optimization_feature_guide.md
    │   └── redis_sockmap_optimization_release_notes.md
```

## 特性介绍

### Redis 6.0.20 网络异步优化

- 特性指南：`docs/zh/redis_network_async_optimization_feature_guide.md`
- 适配补丁：`redis-6.0.20-adapt-iouring.patch`

### Redis 7.0.15 网络异步优化

- 特性指南：`docs/zh/redis_network_async_optimization_feature_guide.md`
- 适配补丁：`redis-7.0.15-adapt-iouring.patch`
- 附加补丁：`redis-7.0.15-adapt-dtoe.patch`

### Redis sockmap优化

- 特性指南：`docs/zh/redis_sockmap_optimization_feature_guide.md`
- 版本说明：`docs/zh/redis_sockmap_optimization_release_notes.md`

## 版本说明

版本说明包含软件版本配套、特性变更与问题说明，详见：

- 中文：`docs/zh/redis_network_async_optimization_release_notes.md`

## 快速入门

以下为 Redis 7.0.15 的示例：

```bash
# 1) 准备 kraio 并安装库文件
cd kraio
make -j4
cp ./libkraio.so /usr/lib64
cp ./include/kraio.h /usr/include

# 2) 合入补丁并编译 Redis
cd /path/to/redis-7.0.15
cp /path/to/Redis/redis-7.0.15-adapt-iouring.patch .
patch -p1 < redis-7.0.15-adapt-iouring.patch
make distclean
make -j
```

完整环境准备、配置与验证步骤详见：

- 中文：`docs/zh/redis_network_async_optimization_feature_guide.md`

## 学习文档

| 文档 | 说明 |
|--|--|
| `docs/zh/redis_network_async_optimization_feature_guide.md` | 中文特性说明、环境部署与验证流程 |
| `docs/zh/redis_network_async_optimization_release_notes.md` | 中文版本配套与变更说明 |
| `docs/zh/redis_sockmap_optimization_feature_guide.md` | 中文 Sockmap 优化特性说明 |
| `docs/zh/redis_sockmap_optimization_release_notes.md` | 中文 Sockmap 优化版本说明 |

## 兼容性信息

| 组件 | 版本 |
|--|--|
| OS | openEuler 22.03 LTS SP4 |
| Redis | 6.0.20 / 7.0.15 |
| 内核（示例） | kernel-5.10.0-275.0.0.178.oe2203sp4.aarch64.rpm |

## 工具限制与注意事项

- 本仓库仅提供 Redis 网络异步优化相关补丁和文档，不直接提供完整 Redis 源码。
- 使用时需确保系统环境、内核版本与文档中的要求匹配。
- 实际性能结果与硬件规格、网络拓扑、压测方法强相关，请按文档建议完成环境对齐。

## 贡献声明

欢迎通过 Issue/PR 反馈问题与改进建议。提交代码前，请确保：

- 变更与 Redis 网络异步优化主题相关；
- 文档与补丁版本信息保持一致；
- 关键变更附带可复现的验证说明。

## 免责声明

- 本仓库内容用于开源技术交流与优化实践参考。
- 使用者需自行评估在其生产环境中的适配性与风险。
- 上游 Redis 社区版本变化可能影响本仓库补丁的可用性。

## License

- 仓库代码 License：见 `LICENSE.txt`
- 仓库文档 License：见 `docs/LICENSE`
- 本项目的文档适用CC-BY 4.0许可证，具体请参见LICENSE文件。
