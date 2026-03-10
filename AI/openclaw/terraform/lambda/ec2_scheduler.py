"""
AWS Lambda 함수: EC2 인스턴스 자동 시작/중지
AutoStart 태그가 있는 EC2 인스턴스를 대상으로 동작
"""
import json
import boto3
import os
from typing import Dict, List, Any

ec2 = boto3.client('ec2')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda 핸들러 함수

    Args:
        event: EventBridge에서 전달되는 이벤트 (action: 'start' 또는 'stop')
        context: Lambda 컨텍스트

    Returns:
        실행 결과를 포함한 딕셔너리
    """
    action = event.get('action', 'stop')
    region = os.environ.get('AWS_REGION', 'ap-northeast-2')

    print(f"EC2 Scheduler Lambda - Action: {action}, Region: {region}")

    try:
        # AutoStart 태그가 있는 인스턴스 찾기
        instances = find_tagged_instances()

        if not instances:
            print("AutoStart 태그가 있는 인스턴스가 없습니다.")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'No instances found with AutoStart tag',
                    'action': action
                })
            }

        instance_ids = [i['InstanceId'] for i in instances]
        print(f"대상 인스턴스: {instance_ids}")

        # 액션 수행
        if action == 'start':
            result = start_instances(instance_ids)
        elif action == 'stop':
            result = stop_instances(instance_ids)
        else:
            raise ValueError(f"Invalid action: {action}")

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Successfully {action}ed instances',
                'instances': instance_ids,
                'result': result
            })
        }

    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'action': action
            })
        }


def find_tagged_instances() -> List[Dict[str, Any]]:
    """AutoStart 태그가 있는 인스턴스 찾기"""
    response = ec2.describe_instances(
        Filters=[
            {
                'Name': 'tag:AutoStart',
                'Values': ['true']
            }
        ]
    )

    instances = []
    for reservation in response['Reservations']:
        for instance in reservation['Instances']:
            # terminated 상태가 아닌 인스턴스만 포함
            if instance['State']['Name'] != 'terminated':
                instances.append({
                    'InstanceId': instance['InstanceId'],
                    'State': instance['State']['Name'],
                    'Name': get_instance_name(instance)
                })
                print(f"Found: {instance['InstanceId']} ({instance['State']['Name']})")

    return instances


def get_instance_name(instance: Dict[str, Any]) -> str:
    """인스턴스의 Name 태그 가져오기"""
    tags = instance.get('Tags', [])
    for tag in tags:
        if tag['Key'] == 'Name':
            return tag['Value']
    return 'N/A'


def start_instances(instance_ids: List[str]) -> Dict[str, Any]:
    """인스턴스 시작"""
    print(f"Starting instances: {instance_ids}")
    response = ec2.start_instances(InstanceIds=instance_ids)
    return response['StartingInstances']


def stop_instances(instance_ids: List[str]) -> Dict[str, Any]:
    """인스턴스 중지"""
    print(f"Stopping instances: {instance_ids}")
    response = ec2.stop_instances(InstanceIds=instance_ids)
    return response['StoppingInstances']
