#! /bin/sh

RESOURCE_GROUP="demo-me-p-aad-deploy"
APPSERVICE_NAME="aad-deployed-app"
APP_NAME="userlist-client"
APP_ID_URI="api://apps.jpd.ms/userlist/client"
RRA='[{"resourceAppId":"00000003-0000-0000-c000-000000000000", "resourceAccess":[{"id":"e1fe6dd8-ba31-4d61-89e7-88639da4683d","type":"Scope"},{"id":"a154be20-db9c-4678-8ab7-66f6cc099a59","type":"Scope"}]}]'

az ad app show --id $APP_ID_URI --query "appId" -o tsv --only-show-errors > /dev/null
if [ $? = 0 ]
    then APP_ID=$(az ad app show --id $APP_ID_URI --query "appId" -o tsv);
    else APP_ID=$(az ad app create --display-name $APP_NAME --identifier-uris $APP_ID_URI --required-resource-accesses "$RRA" -o tsv --query "appId");
fi

# find/create service principal, for consent
az ad sp show --id $APP_ID > /dev/null
if [ $? = 0 ]
    then APP_SP_ID=$(az ad sp show --id $APP_ID --query "objectId" -o tsv);
    else APP_SP_ID=$(az ad sp create --id $APP_ID -o tsv --query "objectId");
fi
echo "app id:" $APP_ID
echo "app sp id:" $APP_SP_ID

# get graph sp id
GRAPH_SP_ID=$(az ad sp show --id "https://graph.microsoft.com/" -o tsv --query "objectId")

# add admin consent
GRAPH_CONSENT='{"clientId":"'$APP_SP_ID'","consentType":"AllPrincipals","principalId":null,"resourceId":"'$GRAPH_SP_ID'","scope":"User.Read User.Read.All"}'

# check for existing consent
CONSENT_ID=$(az rest --uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants?\$filter=clientId eq '$APP_SP_ID'" --resource "https://graph.microsoft.com/" --query "value")
if [ "$CONSENT_ID" = "[]" ] 
    then az rest --uri "https://graph.microsoft.com/v1.0/oauth2permissiongrants" --resource "https://graph.microsoft.com/" --method post --body "$GRAPH_CONSENT" --query "id"
fi

# add client secret
APP_OBJECT_ID=$(az ad app show --id "api://apps.jpd.ms/userlist/client" --query "objectId" -o tsv)
APP_SECRET=$(az rest --url "https://graph.microsoft.com/v1.0/applications/"$APP_OBJECT_ID"/addPassword" --resource "https://graph.microsoft.com/" --method post --body "{'passwordCredential':{'displayName':'automated-secret'}}" --query "secretText" -o tsv)
echo $APP_SECRET

# update azure app service configuration
az webapp config appsettings set -g $RESOURCE_GROUP -n $APPSERVICE_NAME --settings AzureAD__ClientId=$APP_ID
az webapp config appsettings set -g $RESOURCE_GROUP -n $APPSERVICE_NAME --settings AzureAD__ClientSecret=$APP_SECRET

# az ad app delete --id $APP_ID_URI