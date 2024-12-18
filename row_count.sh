#!/bin/env bash
########### row_count.sh #############
# 对比源库/目标库并对比 count(*) 数量
#######################################

# 定义构建SQL查询的函数
build_sql_query() {
    local sql="SELECT CONCAT('\`', table_schema, '\`.\`', table_name, '\`') FROM INFORMATION_SCHEMA.TABLES WHERE table_schema IN ("
    for db in "${DATABASES[@]}"; do
        sql+="'$db',"
    done
    sql=${sql%,}  # 移除最后一个逗号
    sql+=");"
    echo $sql
}

# 定义比较库表名的函数
compare_tables() {
    local source_tables="$1"
    local target_tables="$2"
    local source_missing=()
    local target_missing=()

    # 比较目标端缺少的表
    while IFS= read -r table; do
        if ! grep -q "$table" <<< "$target_tables"; then
            target_missing+=("$table")
        fi
    done <<< "$source_tables"

    # 比较源端缺少的表
    while IFS= read -r table; do
        if ! grep -q "$table" <<< "$source_tables"; then
            source_missing+=("$table")
        fi
    done <<< "$target_tables"

    # 输出比较结果
    echo -e "${SourceHOST}:${SourcePORT} 缺失的表\t\t\t${TargetHOST}:${TargetPORT} 缺失的表"
    local max_len=$((${#target_missing[@]} > ${#source_missing[@]} ? ${#target_missing[@]} : ${#source_missing[@]}))

    for ((i=0; i<$max_len; i++)); do
        printf "%-40s\t%-40s\n" "${target_missing[i]:-}" "${source_missing[i]:-}"
    done

    echo ""
    echo "${SourceHOST}:${SourcePORT} 缺少表的数量: ${#target_missing[@]}"
    echo "${TargetHOST}:${TargetPORT} 缺少表的数量: ${#source_missing[@]}"
    echo ""
    echo "---------------------------------------------------------------------------------------------------"
}

# 定义获取公共表的函数
get_common_tables() {
    local source_tables="$1"
    local target_tables="$2"
    local common_tables=()

    while IFS= read -r table; do
        if grep -q "$table" <<< "$target_tables"; then
            common_tables+=("$table")
        fi
    done <<< "$source_tables"

    echo "${common_tables[@]}"
}

# 定义比较表行数的函数
compare_row_counts() {
    local table_list="$1"
    local source_user="$2"
    local source_password="$3"
    local source_host="$4"
    local source_port="$5"
    local target_user="$6"
    local target_password="$7"
    local target_host="$8"
    local target_port="$9"
    local max_processes=10  # 设置最大并发进程数
    local fifo_file="/tmp/fifo.$RANDOM"

    # 创建管道文件
    mkfifo "$fifo_file"
    exec 6<>"$fifo_file"
    rm "$fifo_file"

    # 初始化进程池
    for ((i = 0; i < max_processes; i++)); do
        echo "" >&6
    done

    local RED='\033[0;31m'
    local NC='\033[0m'  # No Color

    for table in $table_list; do
        # 从管道中读取一个令牌，限制进程数
        read -u 6
        {
            local start_time=$(date +%s)
            local source_count=$(mysql -u"$source_user" -p"$source_password" -h"$source_host" -P"$source_port" -ANB -e "SELECT COUNT(*) FROM $table" 2>/dev/null)
            local target_count=$(mysql -u"$target_user" -p"$target_password" -h"$target_host" -P"$target_port" -ANB -e "SELECT COUNT(*) FROM $table" 2>/dev/null)
            local end_time=$(date +%s)
            local elapsed_time=$((end_time - start_time))

            if [[ "$source_count" -ne "$target_count" ]]; then
                echo -e "${RED}表 $table 行数不一致：${SourceHOST}:${SourcePORT} 行数为 $source_count 行，${TargetHOST}:${TargetPORT} 行数为 $target_count 行${NC} - 比对时间：${elapsed_time} 秒"
            fi

            # 任务完成后释放令牌
            echo "" >&6
        } &
    done

    # 等待所有后台任务完成
    wait

    # 关闭管道
    exec 6>&-
}

# 定义检查数据库是否存在的函数
check_database_exists() {
    local db_name="$1"
    local user="$2"
    local password="$3"
    local host="$4"
    local port="$5"
    local missing_dbs="$6"

    local result=$(mysql -u"$user" -p"$password" -h"$host" -P"$port" -AN -e "SELECT CASE WHEN EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '$db_name') THEN 'exists' ELSE 'not exists' END AS result;" 2>/dev/null)

    if [[ "$result" == "not exists" ]]; then
        missing_dbs+=("$host:$port:$db_name")
    fi

    echo "${missing_dbs[@]}"
}

# 源端
SourceUSER="root"
SourcePASSWORD="123456"
SourceHOST="127.0.0.1"
SourcePORT="3306"
# 目标端
TargetUSER="root"
TargetPASSWORD="123456"
TargetHOST="127.0.0.1"
TargetPORT="3307"

# 定义数据库数组
DATABASES=('ddl' 'test')

# 检查数据库是否存在并记录缺失的数据库
missing_dbs=()
for db in "${DATABASES[@]}"; do
    missing_dbs=($(check_database_exists "$db" "$SourceUSER" "$SourcePASSWORD" "$SourceHOST" "$SourcePORT" "${missing_dbs[@]}"))
    missing_dbs=($(check_database_exists "$db" "$TargetUSER" "$TargetPASSWORD" "$TargetHOST" "$TargetPORT" "${missing_dbs[@]}"))
done

# 输出缺失的数据库并退出脚本
if [ ${#missing_dbs[@]} -gt 0 ]; then
    echo "以下数据库不存在，退出脚本："
    for db in "${missing_dbs[@]}"; do
        echo "$db"
    done
    exit 1
fi

# 调用函数并获取SQL查询
sql=$(build_sql_query)

# 获取源端和目标端的表名
Sdtname=$(mysql -u$SourceUSER -p$SourcePASSWORD -h$SourceHOST -P$SourcePORT -ANB -e "$sql" 2>/dev/null)
Tdtname=$(mysql -u$TargetUSER -p$TargetPASSWORD -h$TargetHOST -P$TargetPORT -ANB -e "$sql" 2>/dev/null)

# 比较库表名
compare_tables "$Tdtname" "$Sdtname" 

# 获取公共表
common_tables=$(get_common_tables "$Sdtname" "$Tdtname")

# 比较公共表行数
echo "比较公共表的行数..."
compare_row_counts "$common_tables" "$SourceUSER" "$SourcePASSWORD" "$SourceHOST" "$SourcePORT" "$TargetUSER" "$TargetPASSWORD" "$TargetHOST" "$TargetPORT"
echo ""
echo "---------------------------------------------------------------------------------------------------"
