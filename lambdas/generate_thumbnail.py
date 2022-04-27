import boto3
# import os
# import sys
import uuid
from urllib.parse import unquote_plus
from PIL import Image
import json
# import PIL.Image

s3_client = boto3.client('s3')

def resize_image(image_path, resized_path):
  print("resizing image")
  with Image.open(image_path) as image:
      image.thumbnail(tuple(x / 2 for x in image.size))
      image.save(resized_path)

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

      print('json_body')
      print(json_body)
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
      upload_path = '/tmp/resized-{}'.format(tmpkey)
      s3_client.download_file(bucket, key, download_path)
      resize_image(download_path, upload_path)
      print("uploading file")
      s3_client.upload_file(upload_path, '{}-resized'.format(bucket), f'resized-{tmpkey}')
