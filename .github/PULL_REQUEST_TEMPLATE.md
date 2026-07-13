## 仓

- 项目: redis
- 上游版本: <v>(7.0.15 / 6.0.20)
- patch id: <unique, 例: redis-7.0.15-0004>
- patch type: <hw/perf/build/cve/compat/bugfix/backport/feature/workaround/revert>
- risk_level: <low/medium/high/critical>
- owner: <email>

## 修改背景

为什么?

## 修改内容

改了哪些文件?

## 验证

- [ ] `python tools/doctor.py` 通过
- [ ] `python tools/lint.py boostkit.yaml` 通过
- [ ] `python tools/check-series.py` 通过
- [ ] `bash tools/check-apply.sh` 干净 apply
- [ ] 至少 1 个 OWNERS approver

## 删除条件

何时上游/本仓升 baseline 后可以删?
