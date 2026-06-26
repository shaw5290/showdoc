# 创建目标导出目录
#mkdir -p ./exported

# 在 git diff 中直接排除 exported 目录
git diff --name-only HEAD -- . ':!./exported' | xargs -I {} cp --parents "{}" "./exported"
