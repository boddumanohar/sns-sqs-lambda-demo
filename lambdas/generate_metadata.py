import boto3
from PIL import Image, ExifTags
from urllib.parse import unquote_plus
import json
import uuid

s3_client = boto3.client('s3')

def get_metatdata(image_path, resized_path):
    metadata = {}
    with Image.open(image_path) as image:
        metadata = { ExifTags.TAGS[k]: v for k, v in image._getexif().items() if k in ExifTags.TAGS }
    return metadata

def lambda_handler(event, context):
  print("event", json.dumps(event, indent=4))
  for record in event['Records']:
      body = record.get('body')
      json_body = {}
      try:
        json_body = json.loads(body)
      except AttributeError:
        print("received a non json body in the event, exiting")
        return

      msg = json_body.get('Message')
      try:
        msg2 = json.loads(msg)
      except AttributeError:
        print("received a non json object in Message, exiting")
        return

      json_body = json.loads(msg)
      detail = json_body.get('detail')
      print('detail')
      print(detail)

      bucket = detail.get('bucket', {}).get('name', {})
      # if the bucket name is not provided
      if not bucket:
        print("bucket name not provided. exiting")
        return

      s3_bucket_key = detail.get('object', {}).get('key', {})
      if not s3_bucket_key:
        print("bucket key not provided. exiting")
        return

      key = unquote_plus(s3_bucket_key)
      tmpkey = key.replace('/', '')
      download_path = '/tmp/{}{}'.format(uuid.uuid4(), tmpkey)
      metadata_file = '/tmp/metadata-{}.json'.format(tmpkey)
      s3_client.download_file(bucket, key, download_path)
      metadata = get_metatdata(download_path, metadata_file)
      metadata_str = str(metadata)
      # write metadata to a file
      with open(metadata_file, "w") as myfile:
          myfile.write(metadata_str)
      s3_client.upload_file(metadata_file, '{}-resized'.format(bucket), f'metadata-{tmpkey}.json')
