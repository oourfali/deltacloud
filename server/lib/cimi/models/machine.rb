# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.  The
# ASF licenses this file to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance with the
# License.  You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the
# License for the specific language governing permissions and limitations
# under the License.

class CIMI::Model::Machine < CIMI::Model::Base

  acts_as_root_entity

  text :state
  text :cpu

  text :memory

  href :event_log

  href :disks

  href :volumes

  href :network_interfaces

  array :meters do
    scalar :href
  end

  array :operations do
    scalar :rel, :href
  end

  def self.find(id, context)
    instances = []
    if id == :all
      instances = context.driver.instances(context.credentials)
      instances.map { |instance| from_instance(instance, context) }.compact
    else
      instance = context.driver.instance(context.credentials, :id => id)
      raise CIMI::Model::NotFound unless instance
      from_instance(instance, context)
    end
  end

  def self.create_from_json(body, context)
    json = JSON.parse(body)
    hardware_profile_id = xml['machineTemplate']['machineConfig']["href"].split('/').last
    image_id = xml['machineTemplate']['machineImage']["href"].split('/').last
    instance = context.create_instance(context.credentials, image_id, { :hwp_id => hardware_profile_id })
    from_instance(instance, context)
  end

  def self.create_from_xml(body, context)
    xml = XmlSimple.xml_in(body)
    machine_template = xml['machineTemplate'][0]
    hardware_profile_id = machine_template['machineConfig'][0]["href"].split('/').last
    image_id = machine_template['machineImage'][0]["href"].split('/').last
    additional_params = {}
    additional_params[:name] =xml['name'][0] if xml['name']
    if machine_template.has_key? 'credential'
      additional_params[:keyname] = machine_template['credential'][0]["href"].split('/').last
    end
    instance = context.driver.create_instance(context.credentials, image_id, {
      :hwp_id => hardware_profile_id
    }.merge(additional_params))
    from_instance(instance, context)
  end

  def perform(action, context, &block)
    begin
      if context.driver.send(:"#{action.name}_instance", context.credentials, self.name)
        block.callback :success
      else
        raise "Operation failed to execute on given Machine"
      end
    rescue => e
      block.callback :failure, e.message
    end
  end

  def self.delete!(id, context)
    context.driver.destroy_instance(context.credentials, id)
  end

  def self.create_resource_metadata(context)
    cimi_resource = self.name.split("::").last
    metadata = CIMI::Model::ResourceMetadata.metadata_from_deltacloud_features(cimi_resource, :instances, context)
    unless metadata.includes_attribute?(:name)
      metadata.attributes << {:name=>"name", :required=>"false",
                   :constraints=>"Determined by the cloud provider", :type=>"xs:string"}
    end
    metadata
  end

  def self.attach_volumes(volumes, context)
    volumes.each do |vol|
      context.driver.attach_storage_volume(context.credentials,
      {:id=>vol[:volume].name, :instance_id=>context.params[:id], :device=>vol[:attachment_point]})
    end
    self.find(context.params[:id], context)
  end

  def self.detach_volumes(volumes, context)
    volumes.each do |vol|
      context.driver.detach_storage_volume(context.credentials, {:id=>vol[:volume].name, :instance_id => context.params[:id]})
    end
    self.find(context.params[:id], context)
  end

  private
  def self.from_instance(instance, context)
    cpu =  memory = (instance.instance_profile.id == "opaque")? "n/a" : nil
    self.new(
      :name => instance.id,
      :description => instance.name,
      :created => instance.launch_time,
      :id => context.machine_url(instance.id),
      :state => convert_instance_state(instance.state),
      :cpu => cpu || convert_instance_cpu(instance.instance_profile, context),
      :memory => memory || convert_instance_memory(instance.instance_profile, context),
      :disks => {:href => context.machine_url(instance.id)+"/disks"},
      :network_interfaces => {:href => context.machine_url(instance.id+"/network_interfaces")},
      :operations => convert_instance_actions(instance, context),
      :volumes=>{:href=>context.machine_url(instance.id)+"/volumes"},
      :property => convert_instance_properties(instance, context)
    )
  end

  # FIXME: This will convert 'RUNNING' state to 'STARTED'
  # which is defined in CIMI (p65)
  #
  def self.convert_instance_state(state)
    ('RUNNING' == state) ? 'STARTED' : state
  end

  def self.convert_instance_properties(instance, context)
    properties = {}
    properties["machine_image"] = context.machine_image_url(instance.image_id)
    if instance.respond_to? :keyname
      properties["credential"] = context.credential_url(instance.keyname)
    end
    properties
  end

  def self.convert_instance_cpu(profile, context)
    cpu_override = profile.overrides.find { |p, v| p == :cpu }
    if cpu_override.nil?
      CIMI::Model::MachineConfiguration.find(profile.id, context).cpu
    else
      cpu_override[1]
    end
  end

  def self.convert_instance_memory(profile, context)
    machine_conf = CIMI::Model::MachineConfiguration.find(profile.name, context)
    memory_override = profile.overrides.find { |p, v| p == :memory }
    memory_override.nil? ? machine_conf.memory : context.to_kibibyte(memory_override[1].to_i,"MB")
  end

  def self.convert_instance_addresses(instance)
    (instance.public_addresses + instance.private_addresses).collect do |address|
      {
        :hostname => address.is_hostname? ? address : nil,
        :mac_address => address.is_mac? ? address : nil,
        :state => 'Active',
        :protocol => 'IPv4',
        :address => address.is_ipv4? ? address : nil,
        :allocation => 'Static'
      }
    end
  end

  def self.convert_instance_actions(instance, context)
    instance.actions.collect do |action|
      action = :destroy if action == :delete # In CIMI destroy operation become delete
      action = :restart if action == :reboot  # In CIMI reboot operation become restart
      { :href => context.send(:"#{action}_machine_url", instance.id), :rel => "http://www.dmtf.org/cimi/action/#{action}" }
    end
  end

  def self.convert_storage_volumes(instance, context)
    instance.storage_volumes ||= [] #deal with nilpointers
    instance.storage_volumes.map{|vol| {:href=>context.volume_url(vol.keys.first),
                                       :attachment_point=>vol.values.first} }
  end

end
