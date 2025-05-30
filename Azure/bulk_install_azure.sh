#!/usr/bin/bash
# Environment variables:
: '
    COMPUTE_API_ENDPOINT*: Prisma Cloud Compute Console URL. 
    PRISMA_USERNAME*: Access Key or Username used to access Prisma Cloud. Must have the Defender Management Read & Write permissions.
    PRISMA_PASSWORD*: Secret Key or Username used to access Prisma Cloud.
    AZURE_TENANT_ID: Tenant ID to be used. Required only if the script is used using a Service Principal.
    AZURE_APP_ID: Client ID or Application ID of the Service Principal.
    AZURE_APP_KEY: Client Secret of the Service Principal.
    UPGRADE: Install the latest version of the defender.
    REGIONS**: Regions where the defender is going to be deployed.
    INCLUDED_SUBSCRIPTIONS**: Subscriptions to include when script is executed. If empty will scan all the Subscriptions within the tenant.
    EXCLUDED_SUBSCRIPTIONS**: Subscriptions to exclude when script is executed.
    INCLUDE_TAG: Clusters to be included if they have certain tag.
    EXCLUDE_TAG: Clusters to be excluded if they have certain tag.

    * means required
    ** list of values separated by comma. ex. value1,value2
'
# Load Environment variables if exists .env file
if [ -e ".env" ]; then
  source .env
fi

# Generate Console TOKEN
CONSOLE_TOKEN=$(curl -s -k ${COMPUTE_API_ENDPOINT}/api/v1/authenticate -X POST -H "Content-Type: application/json" -d '{
  "username":"'"$PRISMA_USERNAME"'",
  "password":"'"$PRISMA_PASSWORD"'"
  }'  | grep -Po '"'"token"'"\s*:\s*"\K([^"]*)')

# Download DaemonSet Defender
echo "Downloading Prisma Cloud Defender"
curl -s -k -O ${COMPUTE_API_ENDPOINT}/api/v1/defenders/daemonset.yaml -H 'Content-Type: application/json' -H "Authorization: Bearer $CONSOLE_TOKEN" -d @defenderConfig.json

# Add required extensions
az extension add -n aks-preview --allow-preview true --only-show-errors

# Obtaining existing subscriptions
if [ -z $AZURE_APP_ID ] && [ -z $AZURE_APP_KEY ] && [ -z $AZURE_TENANT_ID ]
then
    echo "Obtaining existing subscriptions"
    subscriptions=( $(az account subscription list --only-show-errors | jq -r ".[] | .subscriptionId") )
else
    echo "Logging in into Azure using Service Principal"
    subscriptions=( $(az login --service-principal -u ${AZURE_APP_ID} -p ${AZURE_APP_KEY} --tenant ${AZURE_TENANT_ID} | jq -r ".[] | .id") )
fi

if [ -n "$INCLUDED_SUBSCRIPTIONS" ]
then
    echo "Using only subscriptions listed in environment variable INCLUDED_SUBSCRIPTIONS"
    IFS=',' read -r -a subscriptions <<< "$INCLUDED_SUBSCRIPTIONS"
fi

#Turn REGIONS variable into a list
[[ -z "${REGIONS}" ]] && regions=() || IFS=',' read -r -a regions <<< "$REGIONS"

# Verify if cluster has the defender installed in the subscriptions
for subscription in "${subscriptions[@]}"
do
    # Skipping subscriptions in the excluded list
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
        region=$(echo $cluster | jq -r '.location')

        # Check whether the region is supported
        if [[ ! ${regions[@]} =~ $region ]] && [ -n "$regions" ]
        then
            echo "Skipping Instance $instance_name for not being in the following regions: $regions. Current region: $region"
            continue
        fi

        #Excluding clusters by tag
        if [ -n "$EXCLUDE_TAG" ]
        then
            exclude_tag_value=$(echo $vm_instance | jq -r --arg skip "$EXCLUDE_TAG" '.tags[$skip]')
            if [ "$exclude_tag_value" != null ]
            then
                echo "Excluding instance $instance_name due to it has the tag: $EXCLUDE_TAG. Value: $exclude_tag_value"
                continue
            fi
        fi

        #EIncluding clusters by tag
        if [ -n "$INCLUDE_TAG" ]
        then
            include_tag_value=$(echo $vm_instance | jq -r --arg add "$INCLUDE_TAG" '.tags[$add]')
            if [ "$include_tag_value" != null ]
            then
                echo "Including instance $instance_name due to it has the tag: $INCLUDE_TAG. Value: $include_tag_value"
            else
                echo "Excluding instance $instance_name due to it does not have the tag: $INCLUDE_TAG"
                continue
            fi
        fi

        echo "Accessing to cluster: ${cluster_name}. Region ${region}"

        # Verify if the UPGRADE enviroment variable exists
        if [[ -n $UPGRADE ]]
        then
            install_defender=1
        else
            install_defender=$(az aks command invoke --resource-group ${resource_group} --name ${cluster_name}  --command "kubectl get ds twistlock-defender-ds -n twistlock" -o json | jq -r '.exitCode')
        fi

        if [ $install_defender -ne 0 ] 
        then
            if [[ -n $UPGRADE ]]
            then
                echo "Installing the latest version on cluster ${cluster_name}"
            else
                echo "Cluster ${cluster_name} doesn't have the defender installed. Installing defender"    
            fi
            
            # Create namespace and install the defender
            az aks command invoke --resource-group ${resource_group} --name ${cluster_name}  --command "kubectl create ns twistlock" --only-show-errors
            az aks command invoke --resource-group ${resource_group} --name ${cluster_name} --command "kubectl apply -f daemonset.yaml" -f daemonset.yaml --only-show-errors
        else
            echo "Cluster ${cluster_name} already has the defender installed. Nothing to be done"
        fi
        fi
    done
done
echo "Done"