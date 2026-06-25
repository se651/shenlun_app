"""上传 Flutter Web 产物到腾讯云 COS（自动设 MIME + 公有读）"""
import os, mimetypes
from qcloud_cos import CosConfig, CosS3Client

BUCKET = 'shenlun-app-1325305316'
REGION = 'ap-guangzhou'
SECRET_ID = 'YOUR_SECRET_ID'
SECRET_KEY = 'YOUR_SECRET_KEY'

WEB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'build', 'web')

config = CosConfig(Region=REGION, SecretId=SECRET_ID, SecretKey=SECRET_KEY)
client = CosS3Client(config)

# 先清空桶内旧文件
print('清空旧文件...')
while True:
    resp = client.list_objects(Bucket=BUCKET)
    if 'Contents' not in resp:
        break
    objs = [{'Key': o['Key']} for o in resp['Contents']]
    client.delete_objects(Bucket=BUCKET, Delete={'Object': objs})
    print(f'  删除 {len(objs)} 个文件...')
    if not resp.get('IsTruncated'):
        break

# 上传所有文件，自动设 Content-Type
print('上传新文件...')
count = 0
for root, dirs, files in os.walk(WEB_DIR):
    for fname in files:
        local = os.path.join(root, fname)
        # 跳过 shenlun.db
        if 'shenlun.db' in local:
            continue
        key = os.path.relpath(local, WEB_DIR).replace('\\', '/')
        mime, _ = mimetypes.guess_type(fname)
        if mime is None:
            mime = 'application/octet-stream'
        
        with open(local, 'rb') as f:
            # 不传 ContentDisposition，避免 COS 网站端点强制覆盖
            client.put_object(
                Bucket=BUCKET,
                Body=f,
                Key=key,
                ContentType=mime,
            )
        count += 1
        if count % 10 == 0:
            print(f'  已上传 {count} 个文件...')

print(f'完成！共 {count} 个文件')
print(f'访问: https://{BUCKET}.cos-website.{REGION}.myqcloud.com')
