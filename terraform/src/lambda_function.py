import json
import urllib.parse
import boto3
import os
from datetime import datetime

s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    finish_bucket = os.environ['FINISH_BUCKET']
    table_name = os.environ['DYNAMODB_TABLE']
    table = dynamodb.Table(table_name)
    
    for record in event['Records']:
        source_bucket = record['s3']['bucket']['name']
        key = urllib.parse.unquote_plus(record['s3']['object']['key'], encoding='utf-8')
        
        try:
            copy_source = {'Bucket': source_bucket, 'Key': key}
            s3.copy_object(CopySource=copy_source, Bucket=finish_bucket, Key=key)
            
            table.put_item(
                Item={
                    'filename': key,
                    'processed_at': str(datetime.now()),
                    'source_bucket': source_bucket,
                    'destination_bucket': finish_bucket,
                    'status': 'Copied Successfully'
                }
            )
            print(f"Successfully processed {key}")
            
        except Exception as e:
            print(f"Error processing {key}: {str(e)}")
            raise e
            
    return {
        'statusCode': 200,
        'body': json.dumps('File processed and logged successfully')
    }