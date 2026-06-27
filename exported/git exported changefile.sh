# 创建目标导出目录
#mkdir -p ./exported

# 在 git diff 中直接排除 exported 目录
git diff --name-only HEAD -- . ':!./exported' | xargs -I {} cp --parents "{}" "./exported"

# 只筛选出在工作区实际存在的文件
#git diff --name-only HEAD -- . ':!./exported' --diff-filter=ACMR | xargs -r -I {} cp --parents "{}" "./exported"
git diff --name-only HEAD -- . ':!./exported' --diff-filter=ACMR | xargs -r -I {} sh -c '[ -f "{}" ] && cp --parents "{}" "./exported"'
