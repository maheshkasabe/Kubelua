#!/usr/bin/env lua

--[[
Author: Jakob Beckmann <beckmann_jakob@hotmail.fr>
Description:
 Test core V1 API methods against the API.
]]--

local utils = require "spec.utils"
local config = require "kube.config"
local api = require "kube.api"

describe("Core V1 #system", function()
  io.write("starting system test:\n")
  local tear
  local name
  setup(function()
    io.write("creating test cluster for core v1 system testing...\n")
    name, tear = utils.create_k3d_cluster(true)
    utils.initialize_deployments()
    utils.sleep(30)
    local conf = config.from_kube_config()
    local client = api.Client:new(conf):batchv1()
    local status = client:jobs("kube-system"):status("helm-install-traefik")
    while not status.succeeded or status.succeeded < 1 do
      io.write("waiting for traffic helm install to complete ...\n")
      utils.sleep(5)
      status = client:jobs("kube-system"):status("helm-install-traefik")
    end
  end)
  teardown(function()
    if tear then
      io.write(string.format("deleting test cluster '%s' for core v1 system testing...\n", name))
      tear()
    end
  end)

  describe("with a local config", function()
    local client
    before_each(function()
      local conf = config.from_kube_config()
      local global_client = api.Client:new(conf)
      client = global_client:corev1()
    end)

    describe("inspecting namespaces", function()
      it("should not be a namespaced client", function()
        assert.has.errors(function()
          client:namespaces("demo")
        end)
      end)

      it("should be able to return all", function()
        local namespaces = client:namespaces():get()
        assert.are.equal(5, #namespaces)
      end)

      it("should be able to return a specific one", function()
        local ns = client:namespaces():get("demo")
        assert.are.equal("demo", ns:name())
        assert.are.same({}, ns:annotations())
      end)

      it("should be able to return the status of a specific one", function()
        local status = client:namespaces():status("demo")
        assert.are.equal("Active", status.phase)
      end)

      it("should be able to patch the status of one", function()
        local patch = {
          status = {
            phase = "Active",
          }
        }
        local ns = client:namespaces():patch_status("demo", patch)
        assert.are.equal("Active", ns.status.phase)
      end)

      it("should be able to return all in list", function()
        local nslist = client:namespaces():list()
        assert.are.equal("NamespaceList", nslist.kind)
        assert.are.equal("v1", nslist.apiVersion)
      end)

      it("should be able to update one", function()
        local ns_client = client:namespaces()
        local ns = ns_client:get("demo")
        local labels = ns:labels()
        assert.is_nil(labels["new-label"])
        labels["new-label"] = "hello-world"
        ns:set_labels(labels)
        ns_client:update(ns)
        utils.sleep(1)
        local updated_ns = ns_client:get("demo")
        assert.are.equal("hello-world", updated_ns:labels()["new-label"])
      end)

      it("should be able to patch one", function()
        local patch = {
          metadata = {
            labels = {
              key1 = "value1",
              key2 = "value2",
            }
          }
        }
        local expected = {
          ["key1"] = "value1",
          ["key2"] = "value2",
          ["kubernetes.io/metadata.name"] = "demo",
          ["new-label"] = "hello-world",
        }
        local ns = client:namespaces():patch("demo", patch)
        assert.are.same(expected, ns:labels())
      end)

      it("should be able to create/delete one", function()
        local namespace = {
          metadata = {
            name = "test",
            labels = {
              test = "jbe",
            },
          }
        }
        local ns_client = client:namespaces()
        local ret = ns_client:create(namespace)
        assert.are.equal("test", ret:name())
        local resp = ns_client:delete(ret:name())
        assert.are.equal("Terminating", resp.status.phase)
      end)
    end)

    describe("inspecting nodes", function()
      it("should not be a namespaced client", function()
        assert.has.errors(function()
          client:nodes("demo")
        end)
      end)

      it("should be able to return all", function()
        local nodes = client:nodes():get()
        assert.are.equal(3, #nodes)
      end)

      it("should be able to return a specific one", function()
        local node_client = client:nodes()
        local node_base = node_client:get({labelSelector = "node-role.kubernetes.io/master=true"})[1]
        local node = node_client:get(node_base:name())
        assert.are.equal(node_base:name(), node:name())
      end)

      it("should be able to return the status of a specific one", function()
        local node_client = client:nodes()
        local node = node_client:get({labelSelector = "node-role.kubernetes.io/master=true"})[1]
        local status = node_client:status(node:name())
        assert.are.equal("amd64", status.nodeInfo.architecture)
      end)

      it("should be able to return all in list", function()
        local nodelist = client:nodes():list()
        assert.are.equal("NodeList", nodelist.kind)
        assert.are.equal("v1", nodelist.apiVersion)
      end)

      it("should be able to update one", function()
        local node_client = client:nodes()
        local node = node_client:get({labelSelector = "node-role.kubernetes.io/master=true"})[1]
        local labels = node:labels()
        assert.is_nil(labels["new-label"])
        labels["new-label"] = "hello-world"
        node:set_labels(labels)
        node_client:update(node)
        utils.sleep(1)
        local updated_node = node_client:get(node:name())
        assert.are.equal("hello-world", updated_node:labels()["new-label"])
      end)
    end)

    describe("inspecting pods", function()
      it("should be able to return all", function()
        local pods = client:pods():get()
        assert.are.equal(12, #pods)
      end)

      it("should be able to return a specific one", function()
        local pod_base = client:pods():get({labelSelector = "k8s-app=kube-dns"})[1]
        local pod = client:pods(pod_base:namespace()):get(pod_base:name())
        assert.is.starting_with(pod:name(), "coredns")
        assert.are.equal("kube-dns", pod_base:labels()["k8s-app"])
      end)

      it("should be able to return the status of a specific one", function()
        local pod = client:pods():get({labelSelector = "k8s-app=kube-dns"})[1]
        local status = client:pods(pod:namespace()):status(pod:name())
        assert.are.equal("Running", status.phase)
      end)

      it("should be able to return all in list", function()
        local podlist = client:pods():list()
        assert.are.equal("PodList", podlist.kind)
        assert.are.equal("v1", podlist.apiVersion)
      end)

      it("should be able to return all in the kube-system namespace", function()
        local pods = client:pods("kube-system"):get()
        assert.are.equal(9, #pods)
      end)

      it("should be able to get logs of a pod", function()
        local pod = client:pods():get({labelSelector = "k8s-app=kube-dns"})[1]
        local logs = client:pods(pod:namespace()):logs(pod:name(), {tailLines = 25})
        assert.is.containing(logs, "plugin/reload: Running configuration MD5")
      end)

      it("should be able to update one", function()
        local pod_client = client:pods("kube-system")
        local pod = pod_client:get({labelSelector = "k8s-app=kube-dns"})[1]
        local labels = pod:labels()
        assert.is_nil(labels["new-label"])
        labels["new-label"] = "hello-world"
        pod:set_labels(labels)
        pod_client:update(pod)
        utils.sleep(1)
        local updated_pod = pod_client:get(pod:name())
        assert.are.equal("hello-world", updated_pod:labels()["new-label"])
      end)

      it("should be able to delete one", function()
        local pod = client:pods():get({labelSelector = "k8s-app=kube-dns"})[1]
        local _ = client:pods(pod:namespace()):delete(pod:name())
      end)

      it("should be able to create one", function()
        local pod_yaml = [[
metadata:
  name: luakube-test-pod
  labels:
    luakube: forever
spec:
  containers:
  - name: nginx
    image: nginx:1.14.2
    ports:
    - containerPort: 80]]
        local resp = client:pods("demo"):create(pod_yaml)
        assert.is.equal("Pending", resp.status.phase)
      end)
    end)

    describe("inspecting services", function()
      it("should be able to return all", function()
        local services = client:services():get()
        assert.are.equal(5, #services)
      end)

      it("should be able to return a specific one", function()
        local svc = client:services("kube-system"):get("kube-dns")
        assert.are.equal("kube-dns", svc:labels()["k8s-app"])
        assert.are.equal("ClusterIP", svc.spec.type)
      end)

      it("should be able to return the status of a specific one", function()
        local status = client:services("kube-system"):status("kube-dns")
        assert.are.same({}, status.loadBalancer)
      end)

      it("should be able to return all in list", function()
        local svclist = client:services():list()
        assert.are.equal("ServiceList", svclist.kind)
        assert.are.equal("v1", svclist.apiVersion)
      end)

      it("should be able to return all in the kube-system namespace", function()
        local svcs = client:services("kube-system"):get()
        assert.are.equal(3, #svcs)
      end)

      it("should be able to update one", function()
        local svc_client = client:services("kube-system")
        local svc = svc_client:get("kube-dns")
        local labels = svc:labels()
        assert.is_nil(labels["new-label"])
        labels["new-label"] = "hello-world"
        svc:set_labels(labels)
        svc_client:update(svc)
        utils.sleep(1)
        local updated_svc = svc_client:get(svc:name())
        assert.are.equal("hello-world", updated_svc:labels()["new-label"])
      end)

      it("should be able to create and delete one", function()
        local svc_obj = {
          metadata = {
            name = "demo-svc-test",
            namespace = "demo",
          },
          spec = {
            type = "ClusterIP",
            ports = {
              {
                port = 443,
                name = "https",
                protocol = "TCP",
              },
            }
          }
        }
        local ret = client:services():create(svc_obj)
        assert.are.equal(svc_obj.metadata.name, ret:name())
        local svc = client:services(svc_obj.metadata.namespace):get(svc_obj.metadata.name)
        assert.are.equal(svc_obj.spec.type, svc.spec.type)
        local status = client:services(svc_obj.metadata.namespace):delete(svc_obj.metadata.name)
        assert.is_not_true(status:is_failure())
      end)
    end)

    describe("inspecting configmaps", function()
      it("should be able to return all", function()
        local cms = client:configmaps():get()
        assert.are.equal(14, #cms)
      end)

      it("should be able to return a specific one", function()
        local cm = client:configmaps("kube-system"):get("coredns")
        assert.is_not_nil(cm.data.Corefile)
      end)

      it("should not have a status", function()
        assert.is_nil(client:configmaps("kube-system").status)
        assert.is_nil(client:configmaps("kube-system").update_status)
      end)

      it("should be able to return all in list", function()
        local cmlist = client:configmaps():list()
        assert.are.equal("ConfigMapList", cmlist.kind)
        assert.are.equal("v1", cmlist.apiVersion)
      end)

      it("should be able to return all in the kube-system namespace", function()
        local cms = client:configmaps("kube-system"):get()
        assert.are.equal(9, #cms)
      end)

      it("should be able to update one", function()
        local cm_client = client:configmaps("kube-system")
        local cm = cm_client:get("coredns")
        assert.is_nil(cm.data.random)
        cm.data.random = "some random data"
        cm_client:update(cm)
        utils.sleep(1)
        local updated_cm = cm_client:get(cm:name())
        assert.are.equal("some random data", updated_cm.data.random)
      end)

      it("should be able to create and delete one", function()
        local cm_obj = {
          metadata = {
            name = "demo-cm-test",
            namespace = "demo",
          },
          data = {
            url = "hello.world",
            username = "whoami",
          }
        }
        local _ = client:configmaps():create(cm_obj)
        local cm = client:configmaps(cm_obj.metadata.namespace):get(cm_obj.metadata.name)
        assert.are.equal(cm_obj.metadata.name, cm:name())
        assert.are.equal(cm_obj.data.url, cm.data.url)
        local status = client:configmaps(cm_obj.metadata.namespace):delete(cm_obj.metadata.name)
        assert.is_not_true(status:is_failure())
      end)
    end)

    describe("inspecting secrets", function()
      it("should be able to return all", function()
        local secrets = client:secrets():get()
        assert.are.equal(47, #secrets)
      end)

      it("should be able to return a specific one", function()
        local sec = client:secrets("kube-system"):get("k3s-serving")
        assert.is_not_nil(sec.data["tls.key"])
        assert.are.equal("kubernetes.io/tls", sec.type)
      end)

      it("should not have a status", function()
        assert.is_nil(client:secrets("kube-system").status)
        assert.is_nil(client:secrets("kube-system").update_status)
      end)

      it("should be able to return all in list", function()
        local seclist = client:secrets():list()
        assert.are.equal("SecretList", seclist.kind)
        assert.are.equal("v1", seclist.apiVersion)
      end)

      it("should be able to return all in the kube-system namespace", function()
        local secs = client:secrets("kube-system"):get()
        assert.are.equal(42, #secs)
      end)

      it("should be able to create, update, and delete one", function()
        local sec_obj = {
          metadata = {
            name = "demo-sec-test",
            namespace = "demo",
          },
          type = "Opaque",
          data = {
            password = "c2VjcmV0"
          }
        }
        local _ = client:secrets():create(sec_obj)
        local sec = client:secrets(sec_obj.metadata.namespace):get(sec_obj.metadata.name)
        assert.are.equal(sec_obj.type, sec.type)
        assert.are.equal(sec_obj.data.password, sec.data.password)
        sec.data.password = "c3VwZXJzZWNyZXQ="
        client:secrets():update(sec)
        utils.sleep(1)
        local updated_sec = client:secrets(sec:namespace()):get(sec:name())
        assert.are.equal("c3VwZXJzZWNyZXQ=", updated_sec.data.password)
        local status = client:secrets(sec_obj.metadata.namespace):delete(sec_obj.metadata.name)
        assert.is_not_true(status:is_failure())
      end)
    end)

    describe("inspecting service accounts", function()
      it("should be able to return all", function()
        local serviceaccounts = client:serviceaccounts():get()
        assert.are.equal(41, #serviceaccounts)
      end)

      it("should be able to return a specific one", function()
        local sa = client:serviceaccounts("demo"):get("admin")
        assert.is_not_nil(sa.secrets)
      end)

      it("should not have a status", function()
        assert.is_nil(client:serviceaccounts("kube-system").status)
        assert.is_nil(client:serviceaccounts("kube-system").update_status)
      end)

      it("should be able to return all in list", function()
        local salist = client:serviceaccounts():list()
        assert.are.equal("ServiceAccountList", salist.kind)
        assert.are.equal("v1", salist.apiVersion)
      end)

      it("should be able to return all in the kube-system namespace", function()
        local secs = client:serviceaccounts("kube-system"):get()
        assert.are.equal(36, #secs)
      end)

      it("should be able to create, update, and delete one", function()
        local sa_obj = {
          metadata = {
            name = "demo-sa-test",
            namespace = "demo",
          },
          automountServiceAccountToken = true
        }
        local _ = client:serviceaccounts():create(sa_obj)
        local sa = client:serviceaccounts(sa_obj.metadata.namespace):get(sa_obj.metadata.name)
        assert.are.equal(sa_obj.automountServiceAccountToken, sa.automountServiceAccountToken)
        sa:set_labels({["test-label"] = "jbe"})
        local status = client:serviceaccounts():update(sa)
        assert.is_not_true(status:is_failure())
        utils.sleep(1)
        local updated_sa = client:serviceaccounts(sa:namespace()):get(sa:name())
        assert.are.equal("jbe", updated_sa:labels()["test-label"])
        status = client:serviceaccounts(sa_obj.metadata.namespace):delete(sa_obj.metadata.name)
        assert.is_not_true(status:is_failure())
      end)
    end)

    describe("inspecting endpoints", function()
      it("should be able to return all", function()
        local endpoints = client:endpoints():get()
        assert.are.equal(6, #endpoints)
      end)

      it("should be able to return a specific one", function()
        local ep = client:endpoints("kube-system"):get("kube-dns")
        assert.are.equal("Endpoints", ep.kind)
      end)

      it("should not have a status", function()
        assert.is_nil(client:endpoints("kube-system").status)
        assert.is_nil(client:endpoints("kube-system").update_status)
      end)

      it("should be able to return all in list", function()
        local eplist = client:endpoints():list()
        assert.are.equal("EndpointsList", eplist.kind)
        assert.are.equal("v1", eplist.apiVersion)
      end)

      it("should be able to return all in the kube-system namespace", function()
        local secs = client:endpoints("kube-system"):get()
        assert.are.equal(4, #secs)
      end)

      it("should be able to create, update, and delete one", function()
        local ep_obj = {
          metadata = {
            name = "demo-ep-test",
            namespace = "demo",
          },
          subsets = {
            {
              addresses = {
                {
                  ip = "10.42.1.254",
                }
              },
              ports = {
                {
                  name = "dns-tcp",
                  port = 53,
                  protocol = "TCP"
                }
              }
            }
          }
        }
        local _ = client:endpoints():create(ep_obj)
        local ep = client:endpoints(ep_obj.metadata.namespace):get(ep_obj.metadata.name)
        assert.are.equal(1, #ep_obj.subsets)
        ep.subsets[1].ports[1].name = "new-name"
        client:endpoints():update(ep)
        utils.sleep(1)
        local updated_ep = client:endpoints(ep:namespace()):get(ep:name())
        assert.are.equal("new-name", updated_ep.subsets[1].ports[1].name)
        local status = client:endpoints(ep_obj.metadata.namespace):delete(ep_obj.metadata.name)
        assert.is_not_true(status:is_failure())
      end)
    end)
  end)
end)
