import json
import os
import urllib.parse
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3_client = boto3.client('s3')
bedrock_runtime = boto3.client('bedrock-runtime')


def lambda_handler(event, context):
    try:
        logger.info("Received event: %s", json.dumps(event))

        # Parse S3 event notification metadata
        record = event['Records'][0]['s3']
        source_bucket = record['bucket']['name']
        object_key = urllib.parse.unquote_plus(record['object']['key'], encoding='utf-8')

        output_bucket = os.environ.get('OUTPUT_BUCKET')
        model_id = os.environ.get('BEDROCK_MODEL_ID', 'anthropic.claude-3-5-sonnet-20240620-v1:0')

        logger.info(
            f"Processing object '{object_key}' from bucket '{source_bucket}'. "
            f"Target output: '{output_bucket}'."
        )

        # 1. Fetch object snippet or data metadata from S3
        response = s3_client.get_object(Bucket=source_bucket, Key=object_key)
        file_content_sample = response['Body'].read(2048).decode('utf-8', errors='ignore')

        # 2. Construct Bedrock prompt for analysis
        prompt = f"""
Human: You are an expert data analyst AI agent. Analyze the following uploaded dataset sample from file '{object_key}':

{file_content_sample}

Provide:
1. Data schema overview and summary statistics.
2. Key business anomalies, trends, or insights.
3. Recommended data transformations or visualization plots.

A:
"""

        # 3. Invoke Amazon Bedrock model
        payload = {
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 2048,
            "messages": [{"role": "user", "content": prompt}]
        }

        bedrock_response = bedrock_runtime.invoke_model(
            modelId=model_id,
            contentType="application/json",
            accept="application/json",
            body=json.dumps(payload)
        )

        response_body = json.loads(bedrock_response.get('body').read())
        analysis_result = response_body['content'][0]['text']

        # 4. Save structured report to S3 Output Bucket
        output_key = f"reports/analysis_{os.path.basename(object_key)}.md"
        s3_client.put_object(
            Bucket=output_bucket,
            Key=output_key,
            Body=analysis_result.encode('utf-8'),
            ContentType='text/markdown'
        )

        logger.info(
            f"Analysis complete. Report successfully saved to s3://{output_bucket}/{output_key}"
        )

        return {
            'statusCode': 200,
            'body': json.dumps({
                'status': 'SUCCESS',
                'report_location': f"s3://{output_bucket}/{output_key}"
            })
        }

    except Exception as e:
        logger.error(
            f"Error processing pipeline for key "
            f"{object_key if 'object_key' in locals() else 'unknown'}: {str(e)}",
            exc_info=True
        )
        raise e
