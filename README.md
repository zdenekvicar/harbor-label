# harbor-label
This image is created to manage labels on tags via API call, effectively skipping work with UI which can be very slow in larger repositories.
At this moment, it is tested and working with Harbor v1.6.0

## usage
Image is expecting several environments variables in order to work.

List of mandatory variables is here:

Var Name | Required | Description | Notes 
------------- | ------------- | ------------- |------------- 
IMAGE | **yes** | image name | format: {project}/{repository}:{tag} 
LABEL | **yes** | list of labels (comma separated) | example: label1,label2,label3 
HARBOR_USERNAME | **yes** | Harbor login username | Needs RW rights to wanted project/repo 
HARBOR_PASSWORD | **yes** | Harbor login password | Needs RW rights to wanted project/repo 
REPOSITORY_DOMAIN | **yes** | domain name of Harbor | example: harbor.mycompany.net 

## example usage command
```
docker run -it --rm \
-e IMAGE=test-project/testapp-db:v1 \
-e LABEL=label1,label2,label3 \
-e HARBOR_USERNAME=login \
-e HARBOR_PASSWORD=password \
-e REPOSITORY_DOMAIN="harbor.mycompany.net" \
zdenekvicar/harbor-label:v0.1
```
