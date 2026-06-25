"""批量设置 COS 文件公有读权限"""
from qcloud_cos import CosConfig, CosS3Client

BUCKET = 'shenlun-app-1325305316'
REGION = 'ap-guangzhou'

config = CosConfig(Region=REGION,
    SecretId='YOUR_SECRET_ID',
    SecretKey='YOUR_SECRET_KEY')
client = CosS3Client(config)

# 设置桶公有读
client.put_bucket_acl(Bucket=BUCKET, ACL='public-read')

# 逐个设置文件公有读
resp = client.list_objects(Bucket=BUCKET)
objects = resp.get('Contents', [])
for i, obj in enumerate(objects):
    key = obj['Key']
    client.put_object_acl(Bucket=BUCKET, Key=key, ACL='public-read')
    if (i+1) % 10 == 0:
        print(f'  设置 {i+1}/{len(objects)}...')

print(f'完成！{len(objects)} 个文件已设为公有读')
