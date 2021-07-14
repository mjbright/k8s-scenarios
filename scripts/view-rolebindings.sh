
# See: https://stackoverflow.com/questions/54602224/how-to-view-the-permissions-roles-associated-with-a-specific-service-account-in

kubectl get rolebindings,clusterrolebindings -A \
    -o custom-columns='KIND:kind,NAMESPACE:metadata.namespace,NAME:metadata.name,SERVICE_ACCOUNTS:subjects[?(@.kind=="ServiceAccount")].name'


