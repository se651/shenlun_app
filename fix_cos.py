"""修复 COS：清除所有文件的 Content-Disposition 元数据"""
from qcloud_cos import CosConfig, CosS3Client

BUCKET = 'shenlun-app-1325305316'
REGION = 'ap-guangzhou'
SECRET_ID = 'YOUR_SECRET_ID'
SECRET_KEY = 'YOUR_SECRET_KEY'

config = CosConfig(Region=REGION, SecretId=SECRET_ID, SecretKey=SECRET_KEY)
client = CosS3Client(config)

# 拷贝每个文件到自身,清除元数据
resp = client.list_objects(Bucket=BUCKET)
objects = resp.get('Contents', [])

for i, obj in enumerate(objects):
    key = obj['Key']
    # copy 到自己,覆盖元数据
    copy_source = f'{BUCKET}.cos.{REGION}.myqcloud.com/{key}'
    client.copy_object(
        Bucket=BUCKET,
        Key=key,
        CopySource={'Bucket': BUCKET, 'Key': key, 'Region': REGION},
        CopyStatus='Replaced',
    )
    if (i+1) % 10 == 0:
        print(f'  修复 {i+1}/{len(objects)}...')

print(f'完成！{len(objects)} 个文件已修复')
print(f'访问: https://{BUCKET}.cos-website.{REGION}.myqcloud.com')
