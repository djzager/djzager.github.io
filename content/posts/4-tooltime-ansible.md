---
title: "Tool Time: Ansible and Your Kubernetes Toolbox"
description: |
  Deploying and managing applications is easy with Ansible and the k8s module.
tags: ["Ansible", "k8s", "OpenShift", "Kubernetes"]
cover: https://example.com/img/1/image.jpg
date: 2019-03-06T17:23:58Z
draft: true
---

The [`k8s` module](https://docs.ansible.com/ansible/latest/modules/k8s_module.html)
enables users to manage Kubernetes objects in [Ansible](https://www.ansible.com/).
In [Reaching for the Stars with
Ansible Galaxy](https://blog.openshift.com/reaching-for-the-stars-with-ansible-operator/)
I created an Ansible Role, published it to [Ansible
Galaxy](https://galaxy.ansible.com), and leveraged the [Ansible
Operator](https://github.com/operator-framework/operator-sdk) to develop an
application that extended the Kubernetes API. Here, I will show how to use
the `k8s` module and the [`k8s` lookup
plugin](https://docs.ansible.com/ansible/latest/plugins/lookup/k8s.html)
to manage an application in Kubernetes.

# Introduction

Kubernetes objects are predominantly described in YAML files like this one
defining a
[Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/):

```yaml
# application/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  selector:
    matchLabels:
      app: nginx
  replicas: 2
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx
        ports:
- containerPort: 80
```

I add this to the [cluster's _desired state_](https://kubernetes.io/docs/concepts/#overview)
with `kubectl create -f application/deployment.yaml`. [Services](https://kubernetes.io/docs/concepts/services-networking/service/)
allow me to define a policy for communicating with the Deployment:

```yaml
# application/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  labels:
    app: nginx
spec:
  ports:
  - name: web
    port: 80
    protocol: TCP
    targetPort: 80
  selector:
app: nginx
```

Deployments and Services are the basic building blocks for applications in
Kubernetes. Ansible allows me to easily package these object definitions in an
Ansible Role to simplify management of this application in Kubernetes.

**Pre-Requisites**

Software used while developing this post include:

1. `ansible >= 2.6`- See the [installation guide](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) if you do not already have Ansible installed.
1. `openshift >= 0.8` - The installation instructions can be found [here](https://github.com/openshift/openshift-restclient-python#installation).
1. Minikube - Instructions for running Kubernetes locally can be found [here](https://kubernetes.io/docs/setup/minikube/).

**Note**

The source can be found on GitHub at
[djzager/ansible-role-nginx-k8s](https://github.com/djzager/ansible-role-nginx-k8s)
or on Ansible Galaxy at [djzager/nginx_k8s](https://galaxy.ansible.com/djzager/nginx_k8s).

# The File Lookup Plugin

Developing a Role for this application gives maximum reusability. Create the
project using `ansible-galaxy`:

```shell
# In meta/main.yml I will make the role_name nginx-k8s
$ ansible-galaxy init ansible-role-nginx-k8s
```

Set the defaults for the Role in `defaults/main.yml`:

```yaml
# Namespace to install into
namespace: nginx

# To uninstall from the cluster
# state: absent
state: present
```

Place the Deployment and Service YAML files in the `files/`
directory and update `tasks/main.yml`:

```yaml
- name: Make deployment state={{ state }}
  k8s:
    state: "{{ state }}"
    namespace: "{{ namespace }}"
    definition: "{{ lookup('file', 'deployment.yaml') | from_yaml }}"

- name: Make service state={{ state }}
  k8s:
    state: "{{ state }}"
    namespace: "{{ namespace }}"
    definition: "{{ lookup('file', 'service.yaml') | from_yaml }}"
```

To test my Role I create a Playbook outside the Role directory:

```yaml
- hosts: localhost
  roles:
    - name: ansible-role-nginx-k8s
```

The file structure of my Playbook and Role looks like:

```shell
playbook.yml
ansible-role-nginx-k8s/
  defaults/
    main.yml
  files/
    deployment.yml
    service.yml
  meta/
    main.yml
  tasks/
    main.yml
```

Start Minikube, create the Namespace (or target another with
`-e namespace=<existing_namespace>`), and run the playbook:

```shell
$ kubectl create namespace nginx
namespace/nginx created

$ ansible-playbook playbook.yml

PLAY [localhost] **************************************************************

TASK [Gathering Facts] ********************************************************
ok: [localhost]

TASK [ansible-role-nginx-k8s : Make deployment state=present] *****************
changed: [localhost]

TASK [ansible-role-nginx-k8s : Make service state=present] ********************
changed: [localhost]

PLAY RECAP ********************************************************************
localhost                  : ok=3    changed=2    unreachable=0    failed=0

$ kubectl get all -n nginx
NAME                                    READY   STATUS    RESTARTS   AGE
pod/nginx-deployment-7db75b8b78-qrk5j   1/1     Running   0          3m48s
pod/nginx-deployment-7db75b8b78-xf5kx   1/1     Running   0          3m48s

NAME                    TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
service/nginx-service   ClusterIP   10.110.90.72   <none>        80/TCP    3m47s

NAME                               READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/nginx-deployment   2/2     2            2           3m48s

NAME                                          DESIRED   CURRENT   READY   AGE
replicaset.apps/nginx-deployment-7db75b8b78   2         2         2       3m48s
```

With a little effort I packaged the Kubernetes object files defining a simple
Nginx application in a Role that could be published to Ansible Galaxy (like it
is [here](https://galaxy.ansible.com/djzager/nginx_k8s)) and included in more
complex Kubernetes Deployments. Next, I will to take advantage of
[Routes](https://docs.openshift.com/container-platform/3.11/architecture/networking/routes.html)
when my application is deployed in [OpenShift](https://openshift.io/) using the
[`k8s` lookup
plugin](https://docs.ansible.com/ansible/latest/plugins/lookup/k8s.html) to
intelligently react to APIs available in the cluster.

# Conditionals

Now that we have a Role that can manage our application in Kubernetes, we want
to extend it to make use of available APIs in the cluster we are deployed to.
When our application is deployed in an OpenShift cluster, we can write our Role
in such a way that it discovers the available APIs and adjusts accordingly.
First, create the Route definition `files/route.yaml`:

```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: nginx-route
  labels:
    app: nginx
spec:
  port:
    targetPort: web
  to:
    kind: Service
    name: nginx-service
```

The `k8s` lookup plugin supports querying the available API groups in the
cluster with the `cluster_info` parameter. Modify `tasks/main.yml` such that
the first task is the API lookup:

```yaml

- name: Get cluster api_groups
  set_fact:
    api_groups: "{{ lookup('k8s', cluster_info='api_groups')}}"
```

Route objects are in the `route.openshift.io` API group. We can conditionally
manage the Route based on the presence of this API in the
cluster. Add the Route task to `tasks/main.yml`:

```yaml
- name: Make route state={{ state }}
  k8s:
    state: "{{ state }}"
    namespace: "{{ namespace }}"
    definition: "{{ lookup('file', 'route.yaml') | from_yaml }}"
  when: ('route.openshift.io' in api_groups) | bool
```

Re-executing the `playbook.yml` against the cluster, I see the `Make route
state={{ state }}` task is skipped:

```yaml
$ ansible-playbook playbook.yml

PLAY [localhost] ***************************************************************

TASK [Gathering Facts] *********************************************************
ok: [localhost]

TASK [ansible-role-nginx-k8s : Get cluster api_groups] *************************
ok: [localhost]

TASK [ansible-role-nginx-k8s : Make deployment state=present] ******************
changed: [localhost]

TASK [ansible-role-nginx-k8s : Make service state=present] *********************
changed: [localhost]

TASK [ansible-role-nginx-k8s : Make route state=present] ***********************
skipping: [localhost]

PLAY RECAP *********************************************************************
localhost                  : ok=4    changed=2    unreachable=0    failed=0
```

I now have an application that can ask the API server for available
API groups and make use of them if present. Uninstall Nginx
is as easy as `ansible-playbook playbook.yml -e state=absent`. Next, I will use
Jinja2 templating, provided by Ansible, to make the application more
configurable.

**NOTE**

Executing this Role against an OpenShift Cluster I noticed the Nginx Pods stuck
in a `CrashLoopBackOff`. More information can be found [in
this post](https://torstenwalter.de/openshift/nginx/2017/08/04/nginx-on-openshift.html) and
the author provides an image `twalter/openshift-nginx:stable` that resolved this
issue for me.

# Templating with Jinja2

I want to make the name, image, and size of my Nginx deployment configurable to anyone
using my Role. Update `defaults/main.yml`:

```diff
--- a/defaults/main.yml
+++ b/defaults/main.yml
@@ -1,8 +1,19 @@
 ---

+# Name for our application
+name: example-nginx
+
 # Namespace to install into
 namespace: nginx

+# Nginx image
+# Why not from library/nginx?
+# -> https://torstenwalter.de/openshift/nginx/2017/08/04/nginx-on-openshift.html
+image: twalter/openshift-nginx:stable
+
+# Size of the deployment
+size: 2
+
 # To uninstall from the cluster
 # state: absent
 state: present
```

Move the Deployment, Service, and Route specs to `templates/` and template out
the names, labels, the Nginx image used in the Deployment, and the replica count.
The Deployment template after the move:

```yaml
# templates/deployment.yaml.j2
---

apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ name }}
  namespace: {{ namespace }}
spec:
  selector:
    matchLabels:
      app: {{ name }}
  replicas: {{ size }}
  template:
    metadata:
      labels:
        app: {{ name }}
    spec:
      containers:
      - name: nginx
        image: {{ image }}
        ports:
        - containerPort: 8081
```

Update `tasks/main.yml` to use the [template lookup
plugin](https://docs.ansible.com/ansible/latest/plugins/lookup/template.html):

```diff
--- a/tasks/main.yml
+++ b/tasks/main.yml
@@ -7,18 +7,15 @@
 - name: Make deployment state={{ state }}
   k8s:
     state: "{{ state }}"
-    namespace: "{{ namespace }}"
-    definition: "{{ lookup('file', 'deployment.yaml') | from_yaml }}"
+    definition: "{{ lookup('template', 'deployment.yaml.j2') | from_yaml }}"

 - name: Make service state={{ state }}
   k8s:
     state: "{{ state }}"
-    namespace: "{{ namespace }}"
-    definition: "{{ lookup('file', 'service.yaml') | from_yaml }}"
+    definition: "{{ lookup('template', 'service.yaml.j2') | from_yaml }}"

 - name: Make route state={{ state }}
   k8s:
     state: "{{ state }}"
-    namespace: "{{ namespace }}"
-    definition: "{{ lookup('file', 'route.yaml') | from_yaml }}"
+    definition: "{{ lookup('template', 'route.yaml.j2') | from_yaml }}"
```

**NOTE**
All of the changes can be found in [this
commit](https://github.com/djzager/ansible-role-nginx-k8s/commit/ee0b006433615d42dfe6be4cab533af1e88f6ff6).
Run the `playbook.yml` again and verify everything was properly deployed:

```shell
$ kubectl get all -n nginx
NAME                                READY   STATUS    RESTARTS   AGE
pod/example-nginx-f8b965758-9vkxx   1/1     Running   0          5m14s
pod/example-nginx-f8b965758-d74lx   1/1     Running   0          5m14s

NAME                    TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
service/example-nginx   ClusterIP   10.104.138.248   <none>        8081/TCP   5m12s

NAME                            READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/example-nginx   2/2     2            2           5m14s

NAME                                      DESIRED   CURRENT   READY   AGE
replicaset.apps/example-nginx-f8b965758   2         2         2       5m14s
```

At this point I have an application, deployable to Kubernetes and OpenShift, and
have made the name, image, and size of the Nginx app configurable at deployment
time. As an added benefit to this change is that multiple instances of the
application could be deployed in the same Namespace. Next, I will update my
Deployment template to conditionally use OpenShift's
[DeploymentConfig](https://docs.openshift.com/container-platform/3.9/dev_guide/deployments/how_deployments_work.html)
if the API group is available.

# Deployment Configuration

I want a `DeploymentConfig` when my application is deployed in OpenShift.
Update `templates/deployment.yaml.j2`:

```diff
--- a/templates/deployment.yaml.j2
+++ b/templates/deployment.yaml.j2
@@ -1,14 +1,23 @@
 ---

+{% if 'apps.openshift.io' in api_groups %}
+apiVersion: apps.openshift.io/v1
+kind: DeploymentConfig
+{% else %}
 apiVersion: apps/v1
 kind: Deployment
+{% endif %}
 metadata:
   name: {{ name }}
   namespace: {{ namespace }}
 spec:
   selector:
+{% if 'apps.openshift.io' in api_groups %}
+    app: {{ name }}
+{% else %}
     matchLabels:
       app: {{ name }}
+{% endif %}
```

That is it! This example demonstrates the power and flexibility inherent in
using Ansible to manage applications in Kubernetes. To further demonstrate this,
I want to replace the landing page of the Nginx web server by mounting a
[ConfigMap](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/)
into the Nginx container if found by name in the namespace I deploy the
application.

Set a default name for the ConfigMap to search for in `defaults/main.yml`:

```diff
--- a/defaults/main.yml
+++ b/defaults/main.yml
@@ -14,6 +14,10 @@ image: twalter/openshift-nginx:stable
 # Size of the deployment
 size: 2

+# HTML Index ConfigMap name
+# If this configmap exists in the namespace we will add it to the Deployment(Config)
+html_index_configmap: html-index-configmap
```

Modify the `templates/deployment.yaml.j2` to include a volume mount if the `ConfigMap`
is found in the namespace:

```diff
--- a/templates/deployment.yaml.j2
+++ b/templates/deployment.yaml.j2
@@ -29,3 +29,13 @@ spec:
         image: {{ image }}
         ports:
         - containerPort: 8081
+{% if lookup('k8s', kind='ConfigMap', namespace=namespace, resource_name=html_index_configmap) %}
+        volumeMounts:
+        - name: html
+          mountPath: /usr/share/nginx/html
+          readOnly: true
+      volumes:
+      - name: html
+        configMap:
+          name: {{ html_index_configmap }}
+{% endif %}
```

Create a `ConfigMap` and execute the playbook:

```shell
$ CONFIGMAP=https://raw.githubusercontent.com/djzager/ansible-role-nginx-k8s/adc7d21e3a96c265ed4ad033fa07e4cc651dcc81/files/configmap.yaml
$ kubectl create -n nginx -f $CONFIGMAP

$  ansible-playbook playbook.yml

PLAY [localhost] ***************************************************************

TASK [Gathering Facts] *********************************************************
ok: [localhost]

TASK [ansible-role-nginx-k8s : Get cluster api_groups] *************************
ok: [localhost]

TASK [ansible-role-nginx-k8s : Make deployment state=present] ******************
changed: [localhost]

TASK [ansible-role-nginx-k8s : Make service state=present] *********************
ok: [localhost]

TASK [ansible-role-nginx-k8s : Make route state=present] ***********************
skipping: [localhost]

PLAY RECAP *********************************************************************
localhost                  : ok=4    changed=1    unreachable=0    failed=0
```

Verify the landing page has changed:

```bash
# I modified the Nginx service to be of `type: NodePort`
$ curl $(minikube ip):30973
<!DOCTYPE html>
<html>
<head>
<title>Hello World</title>
<style>
    body {
        width: 35em;
        margin: 0 auto;
        font-family: Tahoma, Verdana, Arial, sans-serif;
    }
</style>
</head>
<body>
<h1>Welcome to Ansible k8s</h1>
<p>
  If you see this page, we were successful in our attempt
  to load (conditionally) from a ConfigMap
</p>

<p>
  Check out the documentation for the
  <a href="https://docs.ansible.com/ansible/latest/modules/k8s_module.html">k8s module</a>.<br/>
</p>

<p><em>Thank you for playing.</em></p>
</body>
</html>
```

That was fun. I was able to combine the `k8s` module and lookup plugins with
Ansible's built-in templating engine to make my application cluster agnostic.

**NOTE**

* The changes required can be found in [this
commit](https://github.com/djzager/ansible-role-nginx-k8s/commit/adc7d21e3a96c265ed4ad033fa07e4cc651dcc81))
on the [ansible-role-nginx-k8s project](https://github.com/djzager/ansible-role-nginx-k8s).
* If I remove the `ConfigMap` and re-execute the playbook the Deployment will
**not** be updated. To get that
behavior I would need to include an `{% else %}`, set `volumeMounts: []` and
`volumes: []`, and use `merge_type: merge` in the task to properly handle
changes between executions.

# Application Configuration

One last thing that I would like to do with my simple Nginx app is to make the
number of Nginx worker processes and worker connections configurable.
I also want to bounce the Nginx `Pods` when the configuration changes.
Set defaults in `defaults/main.yml`:

```diff
--- a/defaults/main.yml
+++ b/defaults/main.yml
@@ -21,3 +21,6 @@ html_index_configmap: html-index-configmap
 # To uninstall from the cluster
 # state: absent
 state: present
+
+nginx_config_worker_processes: 1
+nginx_config_worker_connections: 1024
```

Add a templated `ConfigMap` for our Nginx configuration in
`templates/nginx-config.configmap.yaml.j2`:

```yaml
kind: ConfigMap
apiVersion: v1
metadata:
  name: {{ name }}
  namespace: {{ namespace }}
data:
  nginx.conf: |
    #user  nginx;
    worker_processes  {{ nginx_config_worker_processes }};

    error_log  /var/log/nginx/error.log warn;
    pid        /var/run/nginx.pid;


    events {
        worker_connections  {{ nginx_config_worker_connections }};
    }


    http {
        include       /etc/nginx/mime.types;
        default_type  application/octet-stream;

        log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                          '$status $body_bytes_sent "$http_referer" '
                          '"$http_user_agent" "$http_x_forwarded_for"';

        access_log  /var/log/nginx/access.log  main;

        sendfile        on;
        #tcp_nopush     on;

        keepalive_timeout  65;

        #gzip  on;

        include /etc/nginx/conf.d/*.conf;
    }
```

Update the Deployment template to mount our `ConfigMap`:

```diff
--- a/templates/deployment.yaml.j2
+++ b/templates/deployment.yaml.j2
@@ -29,12 +29,20 @@ spec:
         image: {{ image }}
         ports:
         - containerPort: 8081
-{% if lookup('k8s', kind='ConfigMap', namespace=namespace, resource_name=html_index_configmap) %}
         volumeMounts:
+        - name: config
+          mountPath: /etc/nginx/nginx.conf
+          subPath: nginx.conf
+{% if lookup('k8s', kind='ConfigMap', namespace=namespace, resource_name=html_index_configmap) %}
         - name: html
           mountPath: /usr/share/nginx/html
           readOnly: true
+{% endif %}
       volumes:
+      - name: config
+        configMap:
+          name: {{ name }}
+{% if lookup('k8s', kind='ConfigMap', namespace=namespace, resource_name=html_index_configmap) %}
```

Notice that I use `subPath: nginx.conf`, this is to prevent us from blowing away
the rest of the `/etc/nginx` directory in the running container. Now update
`tasks/main.yml` to handle changes to the `ConfigMap`:

```diff
--- a/tasks/main.yml
+++ b/tasks/main.yml
@@ -4,9 +4,16 @@
   set_fact:
     api_groups: "{{ lookup('k8s', cluster_info='api_groups')}}"

+- name: Make nginx config configmap state={{ state }}
+  k8s:
+    state: "{{ state }}"
+    definition: "{{ lookup('template', 'nginx-config.configmap.yaml.j2') | from_yaml }}"
+  notify: kill nginx pods
+
 - name: Make deployment state={{ state }}
   k8s:
     state: "{{ state }}"
+    merge_type: merge
     definition: "{{ lookup('template', 'deployment.yaml.j2') | from_yaml }}"
```

Now all we need is to handle our `kill nginx pods` notification. The idea is to
simply kill each of the Nginx pods in our deployment, allow them to be
re-created, and the new Nginx pods will pick up the new configuration: Create
`handlers/main.yml`:

```yaml
---

- name: kill nginx pods
  k8s:
    state: absent
    definition:
      apiVersion: v1
      kind: Pod
      metadata:
        name: "{{ item.metadata.name }}"
        namespace: "{{ item.metadata.namespace }}"
  loop: "{{ q('k8s', api_version='v1', kind='Pod', namespace=namespace, label_selector=('app=' + name)) }}"
```

Great! We now expose Nginx configuration values to consumers of our Role and can
handle updates to our configuration after Nginx has already been installed in
the cluster.

**NOTE**

This is not the best way to handle an updated `ConfigMap`. Fortunately, in the next
version of Ansible, the `k8s` module will support the [`append_hash`
parameter](https://docs.ansible.com/ansible/devel/modules/k8s_module.html#parameters)
allowing you to uniquely name your `ConfigMap` based on the definition.
The proper way to handle this would be to create the `ConfigMap` using
`append_hash` to get a unique name for our `ConfigMap`, then the subsequent
update to the `Deployment` would force a rollout of our deployment.

# What's Next?

To recap we:

* Started with a simple stateless application definition comprised of
    Deployment and Service YAML files
* Extended our application to support Routes and DeploymentConfigs using the
    `k8s` lookup plugin to discover available APIs and react accordingly
* Made the name, image, and size of our application configurable
* Added a discovery mechanism to allow the default application landing page to
    be overridden
* Exposed application configuration values, stored them in a `ConfigMap`, and
    loaded them into our application using volume mounts

All of this was to show you the power of Ansible to mange applications in
Kubernetes. Ansible, and the `k8s` module and lookup plugin, give you the
flexibility to start as small as two YAML files and grow to a cluster agnostic
application. Not only that, but you could easily follow the template [Reaching
for the Stars with Ansible Galaxy](https://blog.openshift.com/reaching-for-the-stars-with-ansible-operator/)
to make your application Kubernetes native.

What happens next is totally up to you. Some resources that may be useful:

* [`k8s` module `latest`](https://docs.ansible.com/ansible/latest/modules/k8s_module.html)
* [`k8s` module `devel`](https://docs.ansible.com/ansible/devel/modules/k8s_module.html) if
    the `append_hash` parameter would help you when creating `ConfigMap`s
* [`k8s` lookup plugin](https://docs.ansible.com/ansible/latest/plugins/lookup/k8s.html)
* The source for the Ansible used in this post can be found
    [here](https://github.com/djzager/ansible-role-nginx-k8s)
* [operator-sdk](https://github.com/operator-framework/operator-sdk) if you are
    ready to take your application to the next level
