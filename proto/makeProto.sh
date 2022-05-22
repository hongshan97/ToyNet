echo 生成$1的pb文件
protoc --descriptor_set_out $1.pb $1.proto