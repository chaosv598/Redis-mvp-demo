## 改了什么

- patch name: <name, 例 0005-my-fix>
- 上游版本: <v, 例 redis-7.0.15>
- 类型: <new patch / update metadata / docs / tools>

## 验证

- [ ] `bash tools/verify.sh` 通过(本地)
- [ ] 修改了 `versions/<v>/version.yaml` 的 `patches[]` 数组(新增/修改条目)
- [ ] patch 字段填齐(name / title / owner / type / status / note / dependence)

## 影响

- 影响的版本: <v>
- 是否触发上游 PR: <yes / no>
- 上游 PR 链接(如有): <URL>
