# Patch 状态仪表盘

> 自动生成,源:`tools/sync-manifest.py`
> 最近同步:`2026-07-15T12:01:19+08:00`
> 总计:**5 个 patch**

## 状态码说明

| status | 含义 |
|---|---|
| `pending` | 暂未提交上游 |
| `submitted` | 已提交上游 PR,等待审核 |
| `accepted` | 已合入 upstream |
| `rejected` | 上游拒绝合入 |
| `whitelisted` | 永久携带,不再追求上游合入 |

## 状态分布

- **pending**: 1
- **submitted**: 3
- **whitelisted**: 1

## 全量 patch 列表

| patch.name | status | 跨版本 | whitelist_reason |
|---|---|---|---|
| `0001-hw-kunpeng-adapt-iouring-on-6.0.15-6.0.20` | pending | redis-6.0.20 | - |
| `0001-hw-kunpeng-adapt-iouring` | submitted | redis-7.0.15 | - |
| `0002-perf-kunpeng-adapt-dtoe` | whitelisted | redis-7.0.15 | Kunpeng-specific DMA-to-engine HW feature; no u... |
| `0003-perf-jemalloc-arm64-pointer-tag-and-gc` | submitted | redis-7.0.15 | - |
| `0004-perf-rdb-fallback-aof` | submitted | redis-7.0.15 | - |

## 季度评审

- 下一个评审日:**2026-09-15**
- 评审范围:所有 `status: whitelisted` 的 patch
- 工具:`python3 tools/whitelist-audit.py`
