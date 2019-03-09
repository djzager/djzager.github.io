---
title: "Tool Time: Ansible and Your Kubernetes Toolbox"
description: |
  Deploying and managing applications is easy with Ansible and the k8s module.
tags: ["Ansible", "k8s", "OpenShift", "Kubernetes"]
cover: https://example.com/img/1/image.jpg
date: 2019-03-06T17:23:58Z
draft: true
---

[Ansible](https://www.ansible.com/) is a powerful tool, not only for automating
applications and IT infrastructure, but also for interacting with Kubernetes
via the [`k8s` module](https://docs.ansible.com/ansible/latest/modules/k8s_module.html).
In [Reaching for the Stars with
Ansible Galaxy](https://blog.openshift.com/reaching-for-the-stars-with-ansible-operator/)
I created an Ansible Role, published it to [Ansible
Galaxy](https://galaxy.ansible.com), and leveraged the [Ansible
Operator](https://github.com/operator-framework/operator-sdk) to develop an
application that extended the Kubernetes API. Here, I will show you how to use the `k8s`
module and the [`k8s` lookup plugin](https://docs.ansible.com/ansible/latest/plugins/lookup/k8s.html)
to manage an application in Kubernetes.

# Introduction

Before we jump in, a little background, Kubernetes objects are predominantly
described in YAML files like this one defining a Deployment:

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

We add this to the [cluster's _desired state_](https://kubernetes.io/docs/concepts/#overview)
with `kubectl create -f application/deployment.yaml`. When we want to provide
a way to communicate with my deployment we define a Service:

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

At this point we have the pieces defining a simple application that
we could install with `kubectl create -f application/*.yaml` and uninstall with
`kubectl delete -f application/*.yaml`. Our first step will be to create this
install/uninstall experience using Ansible and the `k8s` module.

**Pre-Requisites**

If you want to follow along you will need:

1. `ansible >= 2.6`- See the [installation guide](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) if you do not already have Ansible installed.
1. `openshift >= 0.8` - The installation instructions can be found [here](https://github.com/openshift/openshift-restclient-python#installation).
1. Minikube - Instructions for running Kubernetes locally can be found [here](https://kubernetes.io/docs/setup/minikube/).

**Note**

The source can be found on GitHub at
[djzager/ansible-role-nginx-k8s](https://github.com/djzager/ansible-role-nginx-k8s)
or on Ansible Galaxy at [djzager/nginx_k8s](https://galaxy.ansible.com/djzager/nginx_k8s).

# Starting Slow with YAML

While it may be easiest at the start to simply write a Playbook, developing a
Role gives maximum reusability. Create the project using `ansible-galaxy`:

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

Place the Deployment and Service YAML files in, you guessed it, the `files/`
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

We will need a Playbook in order to test our work. Create a `playbook.yml`
outside the Role directory:

```yaml
- hosts: localhost
  roles:
    - name: ansible-role-nginx-k8s
```

The structure should look something like:

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

Now we are ready to run this playbook (if you haven't started Minikube, now
would be a good time to start it). By default our Role will target the `nginx`
namespace. Create the namespace (or target one that exists with `-e
namespace=default`), run the playbook, and verify:

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

With a little effort we were able to put our simple Nginx application in an
Ansible Role that we can publish to Ansible Galaxy, share with our friends, and
include in more complex Kubernetes deployments. But what if we want to deploy
our application in OpenShift and use
[Routes](https://docs.openshift.com/container-platform/3.11/architecture/networking/routes.html)
to expose our service to external clients? Next, we will explore how to use
conditionals in Ansible to make our application adapt to available APIs.

# Conditionals

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

In the same way that the `k8s` module lets you manage Kubernetes objects, the
`k8s` lookup plugin lets you query the Kubernetes API. Using the `cluster_info`
parameter lets us get information directly from the cluster. Modify
`tasks/main.yml` such that the first task is the API lookup:

```yaml

- name: Get cluster api_groups
  set_fact:
    api_groups: "{{ lookup('k8s', cluster_info='api_groups')}}"
```

Route objects are in the `route.openshift.io` API group. We can conditionally
manage the Route based on the existince (or non-existence) of this API in our
cluster. Add the Route task to `tasks/main.yml`:

```yaml
- name: Make route state={{ state }}
  k8s:
    state: "{{ state }}"
    namespace: "{{ namespace }}"
    definition: "{{ lookup('file', 'route.yaml') | from_yaml }}"
  when: ('route.openshift.io' in api_groups) | bool
```

Re-executing our `playbook.yml` against our Kubernetes cluster, our Route task
is skipped:

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



Simple enough, we now have an application that can ask the API server for the
API groups and make use of them if they are available. Uninstalling our Nginx
application is as easy as `ansible-playbook playbook.yml -e state=absent`.
Wouldn't it be great if we could name our objects something other than
`example-nginx` and set the number of replicas in our Deployment? Next, we'll
use Jinja2 templating provided by Ansible to make our app more grown-up.

**NOTE**

If you are following along with an OpenShift Cluster you may notice the Nginx
pods crash because they don't take kindly to being run as a non-root user. More
information on that can be found [in this post](https://torstenwalter.de/openshift/nginx/2017/08/04/nginx-on-openshift.html)
and the author provides an image `twalter/openshift-nginx:stable` that we can
use.

# Templating with Jinja2

I want to make the name, image, and size of my Nginx deployment configurable to anyone
using my Role. The first step is to update our `defaults/main.yml`:

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

Then, move the Deployment, Service, and Route specs to the `templates/` making
sure to template out the names and labels as well as the Nginx image used in the
Deployment and the replica count. The Deployment template now looks like:

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

For those following along, you can see all of the changes in [this
commit](https://github.com/djzager/ansible-role-nginx-k8s/commit/ee0b006433615d42dfe6be4cab533af1e88f6ff6).
Now run the `playbook.yml` again and verify everything was properly deployed:

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

This is great. We can configure the name, image, and size of our Nginx app and
we have the added ability to deploy multiple instances of our application in the
same names (giving each one their own name). I may not have a specifc need for a
[DeploymentConfig](https://docs.openshift.com/container-platform/3.9/dev_guide/deployments/how_deployments_work.html)
in OpenShift, but I would like to use it if a user deploys my application in
OpenShift. Next we will combine the lookup plugin with our Deployment template
to create a `DeploymentConfig` if the API is available.

# Lookups + Templates Allow us to Configure Deployment

So we want a `DeploymentConfig` when our application is deployed in OpenShift.
Just update `templates/deployment.yaml.j2`:

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

That is it! Kind of boring though so let's kick it up a notch. Have you ever
seen the default landing page of an Nginx web server? I want to modify this
page by loading it from a `ConfigMap` if I find it by name in the namespace I
deploy my application (changes are in [this
commit](https://github.com/djzager/ansible-role-nginx-k8s/commit/adc7d21e3a96c265ed4ad033fa07e4cc651dcc81)).

Start by setting a default in `defaults/main.yml`:

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

Modify the `templates/deployment.yaml.j2` to include a volume mount if we find
the `ConfigMap` in the namespace:

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

Create a `ConfigMap`, execute the playbook, and verify our work:

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

# In order for this to work you will first need to modify
# the Nginx service to be of `type: NodePort`
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

That was fun. We took an additional step to make our application cluster
agnostic and used the `k8s` lookup plugin to conditionally mount a `ConfigMap`
by name if it exists in the namespace we are deployed into.

**NOTE**

If you play around with this some by removing the `ConfigMap` and re-running the
playbook you will notice that the Deployment is **not** updated. To get that
behavior I would need to include an `{% else %}`, set `volumeMounts: []` and
`volumes: []`, and use `merge_type: merge` in the task to create the Deployment.

# Configure Nginx: Now we are High Speed, Low Drag

One last thing that I would like to do with my simple Nginx app is to make the
number of Nginx worker processes and worker connections configurable. This is
not __necessary__ in our case, but it wouldn't be tool time if we didn't go over
the top. I also want to bounce the Nginx `Pods` when the configuration changes.
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

Now all we need is to handle our `kill nginx pods` notification. Create
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

This will delete all of the Nginx pods, letting Kubernetes redeploy, and the new
running Nginx pods will pick up the new configuration.

# The End


