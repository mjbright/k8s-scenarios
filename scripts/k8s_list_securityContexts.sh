# From: https://medium.com/@pjbgf/kubectl-list-security-context-settings-for-all-pods-containers-within-a-cluster-93349681ef5d

#kubectl get pods -A -o go-template --template='
kubectl get pods $* -o go-template --template='

{{range .items}}
{{"pod: "}}{{.metadata.name}} {{if .spec.securityContext}} PodSecurityContext: {{"runAsGroup: "}}{{.spec.securityContext.runAsGroup}} {{"runAsNonRoot: "}}{{.spec.securityContext.runAsNonRoot}} {{"runAsUser: "}}{{.spec.securityContext.runAsUser}} {{if .spec.securityContext.seLinuxOptions}} {{"seLinuxOptions: "}}{{.spec.securityContext.seLinuxOptions}}{{end}} {{else}}PodSecurity Context is not set {{end}}
{{range .spec.containers}}{{"- "}}{{.name}} {{"["}}{{.image}}{{"]"}} {{if .securityContext}} {{"\n    allowPrivilegeEscalation: "}}{{.securityContext.allowPrivilegeEscalation}} {{if .securityContext.capabilities}} {{"capabilities: "}}{{.securityContext.capabilities}} {{end}} {{"privileged: "}}{{.securityContext.privileged}} {{if .securityContext.procMount}} {{"procMount: "}}{{.securityContext.procMount}} {{end}} {{"readOnlyRootFilesystem: "}}{{.securityContext.readOnlyRootFilesystem}} {{"runAsGroup: "}}{{.securityContext.runAsGroup}} {{"runAsNonRoot: "}}{{.securityContext.runAsNonRoot}} {{"runAsUser: "}}{{.securityContext.runAsUser}} {{if .securityContext.seLinuxOptions}} {{"seLinuxOptions: "}}{{.securityContext.seLinuxOptions}} {{end}} {{if .securityContext.windowsOptions}} {{"windowsOptions: "}}{{.securityContext.windowsOptions}}{{end}} {{else}}SecurityContext is not set {{end}}
{{end}}{{end}}'

