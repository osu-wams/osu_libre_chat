## Tools and Configuration Setup

Make sure you have [installed Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) and [are signed in to your Azure account](https://learn.microsoft.com/en-us/cli/azure/authenticate-azure-cli). If you already have Azure CLI installed, run the `az bicep upgrade` command to ensure you're on the latest version of Bicep.

This solution deploys:

- An Azure Storage account with file shares for LibreChat config and MongoDB data.
- An Azure Log Analytics workspace.
- An Azure Container Apps environment.
- Three Azure Container Apps:
  - `mongodb-<suffix>` – MongoDB backing store.
  - `mongoexpress-<suffix>` – Web-based MongoDB admin UI.
  - `librechat-<suffix>` – The LibreChat web application.

The `<suffix>` value is derived from:

```bicep
param appSuffix string = uniqueString(resourceGroup().id)
```

ensuring globally-unique names per resource group.

---

### `librechat.yaml`

The `librechat.yaml` file must be located in the **same directory** as the `main.bicep` script. The Bicep template reads this file at deploy time and injects the Azure OpenAI instance name and key into it before uploading the updated file into the `librechat-config` Azure File share.

To properly configure `librechat.yaml` for this deployment:

- Define an `azureOpenAI` endpoint with a group named `"openai"`.
- Set:
  - `apiKey` to `"openai-key"`
  - `instanceName` to `"openai-instance-name"`

The Bicep template will replace these placeholders with the actual key and instance name from the deployment parameters (`openAiApiKey` and `openAiInstanceName`).

**Example `librechat.yaml`:**

```yaml
endpoints:
  azureOpenAI:
    # Additional azureOpenAI settings can go here if needed
    groups:
      - group: "openai"
        apiKey: "openai-key"           # replaced by main.bicep with openAiApiKey
        instanceName: "openai-instance-name"  # replaced by main.bicep with openAiInstanceName
        forcePrompt: false
        assistants: true
        models:
          model-router:
            deploymentName: model-router
            version: "2025-11-18"
          gpt-5-codex:
            deploymentName: gpt-5-codex
            version: "2025-09-15"
          gpt-5:
            deploymentName: gpt-5
            version: "2025-08-07"
```

> **Important:**
> - The `deploymentName` and `version` values must match deployments that already exist in your Azure OpenAI / Foundry resource (for example, `beavrchat_proto`).
> - The Bicep template does **not** create Azure OpenAI deployments; it only wires LibreChat to an existing instance using the `openAiInstanceName` and `openAiApiKey` parameters.

---

### `models.json`

The `models.json` file is no longer consumed by the Bicep templates. It can be kept as an **optional, documentation-only** artifact to track which model deployments exist in your Azure OpenAI instance. If you keep it, place it in the same directory as `main.bicep`.

**Example `models.json` aligned with the current configuration:**

```json
{
  "models": [
    {
      "deploymentName": "model-router",
      "modelName": "model-router",
      "version": "2025-11-18",
      "capacity": 150
    }
  ]
}
```

You can add entries for `gpt-5-codex` and `gpt-5` to mirror your AOAI deployments, but `main.bicep` will not read this file in its current form.

---

## Bicep Templates Overview

### `main.bicep`

The `main.bicep` template deploys all infrastructure into a single resource group:

- Log Analytics workspace (`log-analytics-${appSuffix}`)
- Storage account (`storage${appSuffix}`) with:
  - File service `default`
  - `librechat-config` share
  - `mongodb` share
- Container Apps managed environment (`managedEnvironment-${appSuffix}`)
- Environment storage mounts:
  - `librechat-config` (Azure File)
  - `mongodb` (Azure File)
- Container Apps:
  - `mongodb-${appSuffix}` using `bitnami/mongodb:latest`, with root credentials:
    - `MONGODB_ROOT_USER=root`
    - `MONGODB_ROOT_PASSWORD=M0ngoP455w0rdXyZ1234567890`
  - `mongoexpress-${appSuffix}` using `mongo-express`, wired to Mongo via:

    ```bicep
    ME_CONFIG_MONGODB_URL = 'mongodb://root:M0ngoP455w0rdXyZ1234567890@mongodb-${appSuffix}:27017'
    ME_CONFIG_MONGODB_ADMINUSERNAME = 'root'
    ME_CONFIG_MONGODB_ADMINPASSWORD = 'M0ngoP455w0rdXyZ1234567890'
    ```

  - `librechat-${appSuffix}` using `librechat/librechat:v0.8.2`, with key environment variables (recommended connection string pattern):

    ```bicep
    { name: 'ENDPOINTS',   value: 'assistants,azureOpenAI' }
    { name: 'CONFIG_PATH', value: '/app/config-env/librechat.yaml' }
    { name: 'MONGO_URI',   value: 'mongodb://root:M0ngoP455w0rdXyZ1234567890@mongodb-${appSuffix}:27017' }
    ```

LibreChat mounts the `librechat-config` Azure File share at `/app/config-env/` and reads its runtime configuration from `CONFIG_PATH` (`/app/config-env/librechat.yaml`).

The template also:

- Reads the local `librechat.yaml` file using `loadTextContent('./librechat.yaml')`.
- Replaces `"openai-key"` and `"openai-instance-name"` with `openAiApiKey` and `openAiInstanceName` respectively.
- Uses a deployment script (`upload-librechat-config-${appSuffix}`) to upload the updated YAML into the `librechat-config` share.

### `rg.bicep`

The `rg.bicep` template is a subscription-scope wrapper that:

- Creates a resource group.
- Invokes `main.bicep` at resource-group scope.

Key parameters:

```bicep
param resourcegroup string
param location string = 'westus2'

@description('Name of the existing Azure OpenAI instance (e.g. beavrchat_proto)')
param openAiInstanceName string

@description('API key for the existing Azure OpenAI instance')
@secure()
param openAiApiKey string
```

It then passes these into `main.bicep`:

```bicep
module resourcesDeployment './main.bicep' = {
  name: 'resourcesDeployment'
  scope: rg
  params: {
    openAiInstanceName: openAiInstanceName
    openAiApiKey: openAiApiKey
  }
}
```

---

## Deployment Instructions

### 1. Get Available Locations

To see available location names:

```bash
az account list-locations
```

Use the `name` property (for example, `eastus2`, `westus2`) when setting the `location` parameter.

---

### 2. Provision a New Resource Group and Deploy

Use `rg.bicep` to create a new resource group and deploy the full stack into it:

```bash
az deployment sub create   --name beavrchat-deploy   --location eastus2   --template-file ./rg.bicep   --parameters     resourcegroup=BeavrChat_proto     location=eastus2     openAiInstanceName=beavrchat_proto     openAiApiKey='<your-beavrchat_proto-API-key>'
```

This will:

- Create the resource group `BeavrChat_proto` in `eastus2`.
- Deploy `main.bicep` into that group, wiring LibreChat to `beavrchat_proto`.

---

### 3. Deploy to an Existing Resource Group

If `BeavrChat_proto` already exists, you can deploy directly with `main.bicep`:

```bash
az deployment group create   --resource-group BeavrChat_proto   --template-file ./main.bicep   --parameters     openAiInstanceName=beavrchat_proto     openAiApiKey='<your-beavrchat_proto-API-key>'
```

This will:

- Create or update the Storage account, file shares, Log Analytics workspace, managed environment, and the three Container Apps.
- Read your local `librechat.yaml`, replace AOAI placeholders, and upload the updated file into the `librechat-config` share.

---

### 4. Post-Deployment Notes

- **LibreChat URL**

  - In the Azure Portal, navigate to:
    - **Resource groups** → `BeavrChat_proto` → Container App `librechat-<suffix>` (for example, `librechat-vlng62iwtqhho`).
  - The public FQDN / URL is available in the Container App’s **Ingress** / **Overview** pane, because `external: true` and HTTP ingress on port 3080 are enabled.

- **MongoDB & Mongo Express**

  - MongoDB (`mongodb-<suffix>`) is configured with a root user `root` and password `M0ngoP455w0rdXyZ1234567890`, and listens on port 27017.
  - Mongo Express (`mongoexpress-<suffix>`) connects to Mongo using those credentials and exposes an HTTP admin UI on port 8081. Its logs warn that:
    - It listens on `0.0.0.0`,
    - It uses default basic auth `admin:pass`, which should be changed for security.

- **Logs**

  - All Container Apps in the `managedEnvironment-<suffix>` environment are configured to send logs to the `log-analytics-<suffix>` workspace (for example, `log-analytics-vlng62iwtqhho` in your current deployment).
  - You can inspect logs via Azure Monitor / Log Analytics in the portal using this workspace.

---



primec startup procedure portal.azure.com
1) Resource Groups - create BeavrChat_proto resource group in US West 2
2) Azure OpenAI > Foundry - create Foundry resource in:
    - BeavrChat_proto resource group
    - eastus2
    - beavrchat-proto resource
    - beavrchat_proto default project
3) ai.azure.com/foundryProject - copy API key to bicep CLI startup string
4) Add Foundry AI models to Foundry resource:
    - model-router
    - GPT 5
    - GPT 5 Codex

