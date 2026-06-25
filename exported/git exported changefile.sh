# 创建目标导出目录
#mkdir -p ./exported

# 将修改的文件列表通过管道传递给 cp 命令，--parents 参数会保留原始目录结构
git diff --name-only HEAD | xargs -I {} cp --parents "{}" "./exported"