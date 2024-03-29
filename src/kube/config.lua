#!/usr/bin/env lua

--[[
Author: Jakob Beckmann <beckmann_jakob@hotmail.fr>
Description:
  Module allowing to interact with the Kubernetes configuration.
]]--

local yaml = require "lyaml"
local fun = require "fun"
local base64 = require "base64"

local KubeConfig = {}

function KubeConfig.get_default_path()
  local home = os.getenv("HOME")
  return home.."/.kube/config"
end

function KubeConfig:new(path)
  path = path or KubeConfig.get_default_path()
  local fh = io.open(path, "r")
  local o = yaml.load(fh:read("a"))
  fh:close()
  self.__index = self
  setmetatable(o, self)
  return o
end

function KubeConfig:context_names()
  return fun.iter(self.contexts)
    :map(function(v) return v.name end)
    :totable()
end

function KubeConfig:cluster_names()
  return fun.iter(self.clusters)
    :map(function(v) return v.name end)
    :totable()
end

function KubeConfig:cluster_name(ctxt)
  for _, context in ipairs(self.contexts) do
    if context.name == ctxt then
      return context.context.cluster
    end
  end
  return nil, "no cluster found for context: "..ctxt
end

function KubeConfig:cluster(name)
  for _, cluster in ipairs(self.clusters) do
    if cluster.name == name then
      return cluster.cluster
    end
  end
  return nil, "no cluster found with name: "..name
end

function KubeConfig:usernames()
  return fun.iter(self.users)
    :map(function(v) return v.name end)
    :totable()
end

function KubeConfig:username(ctxt)
  for _, context in ipairs(self.contexts) do
    if context.name == ctxt then
      return context.context.user
    end
  end
  return nil, "no username found for context: "..ctxt
end

function KubeConfig:user(name)
  for _, user in ipairs(self.users) do
    if user.name == name then
      return user.user
    end
  end
  return nil, "no user found with name: "..name
end




local conf = {}

conf.Config = {}


-- Configuration contructor. Not to be used directly in most cases.
function conf.Config:new(o)
  o = o or {}
  self.__index = self
  setmetatable(o, self)
  return o
end

-- Returns the list of available contexts in the configuration.
function conf.Config:contexts()
  return self.kube_:context_names()
end

-- Returns the currently active cluster in the configuration.
function conf.Config:cluster()
  return assert(self.kube_:cluster_name(self.ctxt_))
end

-- Returns the list of available clusters in the configuration.
function conf.Config:clusters()
  return self.kube_:cluster_names()
end

-- Returns the list of available contexts in the configuration.
function conf.Config:usernames()
  return self.kube_:usernames()
end

-- Returns the user for the current context in the configuration.
function conf.Config:username()
  return assert(self.kube_:username(self.ctxt_))
end

-- Returns the server address currently configured
function conf.Config:server_addr()
  return self.addr_
end

-- TODO(@jakob): better error handling
local function write_b64_file(filepath, data)
  local decoded = base64.decode(data)
  local fh = assert(io.open(filepath, "w"))
  fh:write(decoded)
  fh:close()
end

-- TODO(@jakob): storing these files in /tmp is not secure
-- TODO(@jakob): better error handling
local function init_config(config)
  local user = config.kube_:user(config:username())
  local cluster = config.kube_:cluster(config:cluster())
  config.addr_ = cluster.server
  if user.token then
    config.token_ = user.token
  elseif user["client-certificate"] then
    config.cert_file_ = user["client-certificate"]
    config.key_file_ = user["client-key"]
  elseif user["client-certificate-data"] then
    config.cert_file_ = "/tmp/luakube-cert.pem"
    write_b64_file(config.cert_file_, user["client-certificate-data"])
    os.execute(string.format('chmod 600 "%s"', config.cert_file_))
    config.key_file_ = "/tmp/luakube-key.pem"
    write_b64_file(config.key_file_, user["client-key-data"])
    os.execute(string.format('chmod 600 "%s"', config.key_file_))
  else
    return nil, "only token logins are currently supported"
  end
  return true
end

-- Returns the currently active context in the configuration. Pass an argument to set the current
-- context.
function conf.Config:context(ctxt)
  if ctxt then
    self.ctxt_ = ctxt
    assert(init_config(self))
  end
  return self.ctxt_
end

-- Returns the headers required for authentication from the configuration.
function conf.Config:headers()
  if self.token_ then
    return {
      authorization = "Bearer "..self.token_
    }
  end
  return {}
end

-- Returns the client certificate filepath
function conf.Config:cert()
  return self.cert_file_
end

-- Returns the client key filepath
function conf.Config:key()
  return self.key_file_
end

-- Return a configuration loaded from the kube config at path and set to context ctxt.
function conf.from_kube_config(path, ctxt)
  local kube_config = KubeConfig:new(path)
  ctxt = ctxt or kube_config["current-context"]
  local config = conf.Config:new{
    kube_ = kube_config,
    ctxt_ = ctxt,
  }
  assert(init_config(config))
  return config
end

-- Use the service account mounted in the pod as a configuration to connect.
-- TODO(@jakob): test this function
function conf.in_cluster_config()
  local sa_path = "/var/run/secrets/kubernetes.io/serviceaccount/token"
  local fh = io.open(sa_path, "r")
  local token = fh:read("a")
  fh:close()
  return conf.Config:new{
    token_ = token,
  }
end

-- Use a static bearer token to create a configuration to connect to the cluster. This can be either
-- a static cluster token, or a bootstrap token.
-- TODO(@jakob): test this function
function conf.from_token(token)
  return conf.Config:new{
    token_ = token,
  }
end

return conf
