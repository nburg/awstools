require 'erb'
require 'fog'

class Awstool::Instance
  def initialize(options)
    @options = options
    @compute = Fog::Compute.new(
      provider: 'AWS',
      region: @options['region'],
      aws_access_key_id: @options['access_key_id'],
      aws_secret_access_key: @options['access_key']
    )
    @dns = Fog::DNS.new(
      provider: 'AWS',
      aws_access_key_id: @options['access_key_id'],
      aws_secret_access_key: @options['access_key']
    )
  end

  def launch
    b = binding
    userdata = ERB.new(File.read(@options['userdata']), nil, '<>').result(b)
    @instance = @compute.servers.create(
      image_id:  @options['image-id'],
      flavor_id: @options['instance-type'],
      security_group_ids: @options['security-group-ids'],
      subnet_id: @options['subnet-ids'][@options['subnet-id-index']],
      key_name: @options['key-name'],
      tags: @options['tags'],
      user_data: userdata,
      block_device_mapping: map_block_devices
    )
    @instance.wait_for { ready? }
    pp @instance.reload
  end

  def set_dns
    zone = @dns.zones.get(@options['dns-zone-id'])
    if @options['purge_dns']
      record = zone.records.find { |r| r.name == "#{@options['hostname']}." }
      if record
        record.destroy
      end
    end
    record = zone.records.create(
      value: @instance.private_ip_address,
      name: @options['hostname'],
      type: 'A',
      ttl: '300'
    )
  end

  private

  def map_block_devices
    block_device_mapping = [
      {
        'DeviceName' => '/dev/sda1',
        'Ebs.VolumeType' => 'gp2',
        'Ebs.VolumeSize' => @options['rootvol_size'],
        'Ebs.DeleteOnTermination' => 'true'
      }
    ]
    @options['block_devices'].each do |device, opts|
      block_device_mapping << {
        'DeviceName' => "/dev/#{device}",
        'Ebs.VolumeType' => 'gp2',
        'Ebs.VolumeSize' => opts['size'],
        'Ebs.DeleteOnTermination' => 'true'
      }
    end
    block_device_mapping
  end
end
