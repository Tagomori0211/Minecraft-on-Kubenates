NAMESPACE="minecraft"
ssh k3s-worker "sudo kubectl run bds-backup-temp --image=alpine --restart=Never -n ${NAMESPACE} --overrides='{\"spec\": {\"volumes\": [{\"name\": \"data\", \"persistentVolumeClaim\": {\"claimName\": \"pvc-bedrock\"}}], \"containers\": [{\"name\": \"bds-backup-temp\", \"image\": \"alpine\", \"command\": [\"sleep\", \"3600\"], \"volumeMounts\": [{\"name\": \"data\", \"mountPath\": \"/data\"}]}]}}'"
ssh k3s-worker "sudo kubectl wait --for=condition=Ready pod/bds-backup-temp -n ${NAMESPACE} --timeout=60s"
ssh k3s-worker "sudo kubectl delete pod bds-backup-temp -n ${NAMESPACE}"
