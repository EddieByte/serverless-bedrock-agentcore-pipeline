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
        model_id = os.environ.get('BEDROCK_MODEL_ID', 'us.amazon.nova-pro-v1:0')

        logger.info(
            f"Processing object '{object_key}' from bucket '{source_bucket}'. "
            f"Target output: '{output_bucket}'."
        )

        # 1. Fetch object snippet from S3
        response = s3_client.get_object(Bucket=source_bucket, Key=object_key)
        file_content_sample = response['Body'].read(2048).decode('utf-8', errors='ignore')

        # 2. Construct analysis prompt
        prompt = (
            f"You are an expert data analyst. Analyze the following uploaded dataset "
            f"sample from file '{object_key}':\n\n"
            f"{file_content_sample}\n\n"
            f"Provide:\n"
            f"1. Data schema overview and summary statistics.\n"
            f"2. Key business anomalies, trends, or insights.\n"
            f"3. Recommended data transformations or visualization plots."
        )

        # 3. Invoke Amazon Nova via the Converse API (works across all Nova models)
        converse_response = bedrock_runtime.converse(
            modelId=model_id,
            messages=[
                {
                    "role": "user",
                    "content": [{"text": prompt}]
                }
            ],
            inferenceConfig={
                "maxTokens": 2048,
                "temperature": 0.3
            }
        )

        analysis_result = converse_response["output"]["message"]["content"][0]["text"]

        # 4. Save report to S3 output bucket
        output_key = f"reports/analysis_{os.path.basename(object_key)}.md"
        s3_client.put_object(
            Bucket=output_bucket,
            Key=output_key,
            Body=analysis_result.encode('utf-8'),
            ContentType='text/markdown'
        )

        logger.info(
            f"Analysis complete. Report successfully saved to "
            f"s3://{output_bucket}/{output_key}"
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
