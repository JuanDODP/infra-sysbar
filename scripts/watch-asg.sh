#!/bin/bash
# Muestra cada 30 s cuántas instancias tiene el Auto Scaling Group y en qué estado están.
# Uso: scripts/watch-asg.sh [nombre-del-asg] [perfil-aws]
ASG="${1:-sysranchito-dev-asg}"
PROFILE="${2:-${AWS_PROFILE:-}}"
P=(); [ -n "$PROFILE" ] && P=(--profile "$PROFILE")
while true; do
  clear
  date '+%H:%M:%S'
  aws "${P[@]}" autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" \
    --query 'AutoScalingGroups[0].{min:MinSize,deseado:DesiredCapacity,max:MaxSize}' --output table
  aws "${P[@]}" autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" \
    --query 'AutoScalingGroups[0].Instances[].[InstanceId,AvailabilityZone,LifecycleState,HealthStatus]' --output table
  echo "Últimas actividades de escalado:"
  aws "${P[@]}" autoscaling describe-scaling-activities --auto-scaling-group-name "$ASG" --max-items 4 \
    --query 'Activities[].[StartTime,StatusCode,Description]' --output text 2>/dev/null | cut -c1-150
  sleep 30
done
