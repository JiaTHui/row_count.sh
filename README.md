# row_count.sh
Compare the number of source and target database tables and count(*) to compare the number

## **Function**

1. Compare the missing database and table names of the source and target databases
2. Compare count(*).
3. Concurrent comparisons, using the max_processes variable of the compare_row_counts function (default 10, which is the optimal setting and does not require configuration; you can lower it but it is not recommended to increase it)
4. You can use check sum if you want to change it, but I am too lazy to change it here

## Modify the script

139~151
```sql
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
```

## run


```sql
sh row_count.sh
```
run picture:
![row_count](https://github.com/JiaTHui/row_count.sh/blob/main/row_count.png)
