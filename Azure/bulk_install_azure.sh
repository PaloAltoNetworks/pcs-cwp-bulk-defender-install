#!/usr/bin/bash
#Extract environment variables
[[ -z "${COMPUTE_API_ENDPOINT}" ]] && COMPUTE_API_ENDPOINT="${COMPUTE_API_ENDPOINT}" 
[[ -z "${PRISMA_USERNAME}" ]] && PRISMA_USERNAME="${PRISMA_USERNAME}"
[[ -z "${PRISMA_PASSWORD}" ]] && PRISMA_PASSWORD="${PRISMA_PASSWORD}"
[[ -z "${AZURE_TENANT_ID}" ]] && AZURE_TENANT_ID="${AZURE_TENANT_ID}"
[[ -z "${AZURE_APP_ID}" ]] && AZURE_APP_ID="${AZURE_APP_ID}"
[[ -z "${AZURE_APP_KEY}" ]] && AZURE_APP_KEY="${AZURE_APP_KEY}"
[[ -z "${EXCLUDED_SUBSCRIPTIONS}" ]] && EXCLUDED_SUBSCRIPTIONS="${EXCLUDED_SUBSCRIPTIONS}"
[[ -z "${SKIP_TAG}" ]] && SKIP_TAG="${SKIP_TAG}"

#Generate Console TOKEN
CONSOLE_TOKEN=$(curl -s -k ${COMPUTE_API_ENDPOINT}/api/v1/authenticate -X POST -H "Content-Type: application/json" -d '{
  "username":"'"$PRISMA_USERNAME"'",
  "password":"'"$PRISMA_PASSWORD"'"
  }'  | grep -Po '"'"token"'"\s*:\s*"\K([^"]*)')

#Download DaemonSeti Defender
echo "Downloading Prisma Cloud Defender"
curl -s -k -O ${COMPUTE_API_ENDPOINT}/api/v1/defenders/daemonset.yaml -H 'Content-Type: application/json' -H "Authorization: Bearer $CONSOLE_TOKEN" -d @defenderConfig.json

#Login to azure with Service Principal and getting the Subscriptions it has access to
echo "Logging in into Azure"
subscriptions=( $(az login --service-principal -u ${AZURE_APP_ID} -p ${AZURE_APP_KEY} --tenant ${AZURE_TENANT_ID} | jq -r ".[] | .id") )
IFS=',' read -r -a excluded_subscriptions <<< "$EXCLUDED_SUBSCRIPTIONS"

#Verify if cluster has the defender installed in the subscriptions
for subscription in "${subscriptions[@]}"
do
    #Skipping subscriptions in the excluded list
    if [[ ${excluded_subscriptions[@]} =~ $subscription ]]
    then
        echo "Skipping Subscription ID $subscription"
        continue
    fi
    
    az account set --subscription $subscription
    echo "Reading AKS Clusters. Subscription ID: $subscription"
    az aks list --only-show-errors | jq -c '.[]' | while read cluster
    do
        cluster_name=$(echo $cluster | jq -r '.name')
        resource_group=$(echo $cluster | jq -r '.resourceGroup')
        tag=$(echo $cluster | jq -r --arg skip "$SKIP_TAG" '.tags[$skip]')

        if [ $tag == "no" ]
        then
            echo "Skipping cluster: ${cluster_name}. Tag '$SKIP_TAG' is set to 'no'."
        else
            echo "Accessing to cluster: ${cluster_name}"
            response=$(az aks command invoke --resource-group ${resource_group} --name ${cluster_name}  --command "kubectl get ds twistlock-defender-ds -n twistlock" -o json | jq -r '.exitCode')
            if [ $response -ne 0 ] 
            then
                echo "Cluster ${cluster_name} doesn't have the defender installed. Installing defender"
                az aks command invoke --resource-group ${resource_group} --name ${cluster_name}  --command "kubectl create ns twistlock"
                az aks command invoke --resource-group ${resource_group} --name ${cluster_name} --command "kubectl apply -f daemonset.yaml" -f daemonset.yaml
            else
                echo "Cluster ${cluster_name} already has the defender installed. Nothing to be done"
            fi
        fi
    done
done
echo "Done"