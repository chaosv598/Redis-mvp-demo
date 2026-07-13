## 改了什么

- patch id: <id, 例 redis-7.0.15-0004>
- 上游版本: <v>
- 类型: <new patch / rebase / retire / docs / tools>

## 验证

- [ ] `bash tools/verify.sh` 通过
- [ ] metadata 6 字段填齐(id, title, owner, upstream_base, applies_to, upstream_plan)
- [ ] 改动后 `bash tools/lifecycle.sh list` 显示正确

## 影响

- 影响的版本: <v>
- 是否触发上游 PR: <yes / no>
