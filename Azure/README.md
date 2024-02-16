# Script to install Prisma Cloud Defender in Azure Tenant
This script is meant for installling the Prisma Cloud Defender in all AKS Clusters, no matter if they are private or public, within an Azure Tenant. 

## Prerequisites
### Terminal
This script is meant to work in **bash** shell. So in this case this can run on a Linux machine or on Windows WSL.

### Packages
The Packages that should be installed are the following:
* [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux?pivots=apt)
* [JSON Processor](https://jqlang.github.io/jq/download/)

### Prisma Cloud Service Account
For using this script you need to create a Service Account within Prisma Cloud. This Service Account should at least have **View** and **Update** to the **Defenders Management** Permission. 

### Azure Service Principal
You need to create a Service Principal within Azure to be able to execute any action the Azure Tenant. You can use the file **DefenderInstallServicePrincipal.tf.json** to create such Service Principal with the minimum required permissions. To use it follow these steps:

1. Login to Azure
2. Open Cloud Shell in Bash mode
3. Upload the **DefenderInstallServicePrincipal.tf.json** file
4. Update the **TENANT_ID** contained in the file. This shall be found in the variables section:
```json
    ...
  "variable": {
    "tenant_id": {
      "default": "${TENANT_ID}",
      "type": "string"
    },
    ...
```
5. Apply the file by using the following commands:
```bash
    terraform init
    terraform apply --auto-approve
```

The outputs will be the following:
1. **b_application_id**: Azure Application ID. Needed for Log In into Azure using Service Principal
2. **c_application_key**: Azure Application Key. Needed for Log In into Azure using Service Principal
3. **a_active_directory_id**: Tenant ID.
4. **e_service_principal_object_id**: Azure Service Principal Object ID. Might be used for K8S Azure Network Policy.
5. **d_application_key_expiration**: Azure Application Key expiration end date.
6. **f_consent_link**: Link to access to Azure Application on Azure UI.

## Script
### Environment Veriables
The environment variables for this script are listed in the **.env** file. These are the following:

* **COMPUTE_API_ENDPOINT**: Prisma Cloud Compute Console API Endpoint 
* **PRISMA_USERNAME**: Access Key of the Prisma Cloud Service Account
* **PRISMA_PASSWORD**: Secret Key of the Prisma Cloud Service Account
* **AZURE_TENANT_ID**: Azure Tenant ID
* **AZURE_APP_ID**: Azure Application ID of the Service Principal
* **AZURE_APP_KEY**: Azure Application Key of the Service Principal
* **EXCLUDED_SUBSCRIPTIONS** (optional): Subscriptions to exclude for installing the Defender 
* **SKIP_TAG** (optional): Azure Tag to filter which cluster will be skipped from Defender Installation. It's value on Azure must be set to **no** for this cluster to be filtered.

### Defender Configuration
The Defender Configuration file is in the root directory of this repo and is named as **dockerConfig.json**. This is the Request JSON body. For more information follow the [Prisma Cloud API documentation](https://pan.dev/compute/api/post-defenders-daemonset-yaml/) 

### Azure AKS Command Invoke
The script uses the command **az aks command invoke** to be able to install the Prisma Cloud Defender in the AKS clusters. This command creates a Kubernetes Pod which runs on the namespace **aks-command**. This Pod will have the label **createdBy** whose value will be equal to the **Azure Service Principal Object ID**, which can be obtained from the output **e_service_principal_object_id** if applied the **DefenderInstallServicePrincipal.tf.json** file. So if any Kubernetes Network Policy is needed, you can create a rule that matches the label **createdBy** and its corresponding value.

For more information follow this links:
* [Access a private Azure Kubernetes Service (AKS) cluster](https://learn.microsoft.com/en-us/azure/aks/access-private-cluster?tabs=azure-cli)
* [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)


### Usage
The Usage process is simple. The steps are the following:

1. Update the **.env** file and **dockerConfig.json** to match your environment and needs.
2. Set environment variables by executing the following command:
```bash
    source .env
``` 
3. Set the install script as executable:
```bash
    chmod +x bulk_install_azure.sh
```
4. Execute the script:
```bash
    ./bulk_install_azure.sh
```