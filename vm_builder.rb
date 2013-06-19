require 'rubygems'
require 'socket'
require 'timeout'
require 'rest_client'
require 'base64'
require 'json'
require 'net/ssh'
require 'uri'

class VmBuilder

  attr_accessor :fullname

  def initialize args
    raise TypeError unless args.is_a? Hash

    # set some defaults
    @url  = args.delete(:url)  || "http://127.0.0.1:3000"
    @user = args.delete(:user) || 'admin'
    @pass = args.delete(:pass) || 'changeme'

    # Make a class var out of all the remaining args
    args.each { |k,v| instance_variable_set "@#{k}", v }
  end

  def headers(user=@user,pass=@pass)
    { "Content_Type" => 'application/json', "Accept" => 'application/json', "Authorization" => "Basic #{Base64.encode64("#{@user}:#{@pass}")}" }
  end

  def check_connection 
    begin
      response = RestClient.get "#{@url}/status", headers
      if response.code == 200
        puts "Connection to #{@url} ok: Foreman version #{JSON.parse(response.body)['version']}"
      else
        puts "Bad response from #{@url}: #{response.code} : #{response.body}"
        exit 1
      end
      response = RestClient.get "#{@url}/hosts", headers
      if response.code == 200
        puts "Auth Connection to #{@url} ok: #{JSON.parse(response.body).size} hosts found"
      end
    rescue Errno::ECONNREFUSED => e
      puts "Connection refused from: #{@url}"
      exit 2
    rescue RestClient::Request::Unauthorized => e
      puts "Got 401 Unauthorized: check your credentials"
      exit 3
    rescue => e
      puts "Problem testing connection to #{@url}: #{e.message}\n#{e.class}"
      puts e.backtrace
      exit 4
    end
  end

  def check_and_create_host
    begin
      print "Creating host '#{@hostname}'"
      response = RestClient.get "#{@url}/api/hosts", headers.merge({:params => {:search => "name ~ #{@hostname}"}})
      if JSON.parse(response.body).empty?
        raise RestClient::ResourceNotFound
      else
        @fullname = JSON.parse(response.body).first['host']['name']
        response = RestClient.get "#{@url}/api/hosts/#{@fullname}", headers
        if response.code == 200
          if @delete == true then
            print " [exists, deleting]"
            del_res = RestClient.delete "#{@url}/api/hosts/#{@fullname}", headers
            raise unless del_res.code == 200
            raise RestClient::ResourceNotFound # jump to creation
          else
            puts " [exists, skipped]"
          end
        end
      end
    rescue RestClient::ResourceNotFound
      @fullname = create_host['host']['name']
      puts " [done]"
    rescue => e
      puts e.message
    end
  end

  def wait_for_connection
    print "Waiting for host to finish install "
    while get_host_status == 'Pending Installation'
      print '.'
      sleep 60
    end
    puts " [done]"

    print "Waiting for port 22 to open "
    while is_port_open?(ip,22) == false
      sleep 1
      print '.'
    end
    puts " [done]"
  end

  def ip
    return @ip unless @ip.nil?
    res = RestClient.get("#{@url}/api/hosts/#{@fullname}", headers)
    @ip = JSON.parse(res.body)['host']['ip']
    return @ip
  end

  def ssh_setup(commands)
    puts "SSHing to target"
    puts "----------------"
    # TODO: Could move all this to a custom finish-script for the packaging hostgroup
    begin
      Net::SSH.start(ip, 'root', :password => 'test', :paranoid=>false) do |ssh|
        # open a new channel and configure a minimal set of callbacks, then run
        # the event loop until the channel finishes (closes)
        channel = ssh.open_channel do |ch|
          ch.exec commands.join(" && ") do |ch, success|
            raise "could not execute command" unless success

            # "on_data" is called when the process writes something to stdout
            ch.on_data do |c, data|
              $stdout.print data
            end

            # "on_extended_data" is called when the process writes something to stderr
            ch.on_extended_data do |c, type, data|
              $stderr.print data
            end

            ch.on_close { puts "SSH Complete" }
          end
        end

        channel.wait
      end
    rescue => e
      puts "Error with SSH: #{e.message}\n#{e.backtrace}"
    end
  end


  private

  def get_host_status
    response = RestClient.get "#{@url}/api/hosts/#{@fullname}/status", headers
    return JSON.parse(response.body)['status']
  end

  def hostgroup_info
    return @hostgroup_info unless @hostgroup_info.nil?
    response = RestClient.get "#{@url}/api/hostgroups/#{@hostgroup}", headers
    @hostgroup_info = JSON.parse(response.body)['hostgroup']
  end

  def compute_resource_id
    return @compute_resource_id unless @compute_resource_id.nil?
    response = RestClient.get "#{@url}/api/compute_resources/#{@compute_resource}", headers
    @compute_resource_id = JSON.parse(response.body)['compute_resource']['id']
  end

  def architecture_id
    return @architecture_id unless @architecture_id.nil?
    response = RestClient.get "#{@url}/api/architectures/#{@architecture}", headers
    @architecture_id = JSON.parse(response.body)['architecture']['id']
  end

  def operatingsystem_id
    return @operatingsystem_id unless @operatingsystem_id.nil?
    response = RestClient.get "#{@url}/api/operatingsystems", headers
    @operatingsystem_id = JSON.parse(response.body).select { |k| k['operatingsystem']['name'] == @os_name and k['operatingsystem']['major'] == @os_version }.first['operatingsystem']['id']
  end

  def environment_id
    return @environment_id unless @environment_id.nil?
    response = RestClient.get "#{@url}/api/environments/#{@environment}", headers
    @environment_id = JSON.parse(response.body)['environment']['id']
  end

  def create_host
    # Create it
    host_hash = {
      "host" => {
        "name"                => @hostname,
        "hostgroup_id"        => hostgroup_info['id'],
        "compute_resource_id" => compute_resource_id,
        "location_id"         => @location,
        "organization_id"     => @organisation,
        "architecture_id"     => architecture_id,
        "operatingsystem_id"  => operatingsystem_id,
        "environment_id"      => environment_id,
        "build"               => 1,
        "provision_method"    => "image",
        "compute_attributes"  => {
          "flavor_ref"          => "2",
          "image_ref"           => "252861eb-f1a6-4243-9152-9ae58434341b",
          "tenant_id"           => "b7b85528b7c448d9bdec77148c2e8a97",
          "security_groups"     =>"default",
          "network"             =>"public",
        }
      },
      "capabilities"=>"image",
    }

    response = RestClient::Request.execute(:method => :post, :url => "#{@url}/api/hosts", :payload => host_hash, :headers => headers, :timeout => 600)
    return JSON.parse(response.body)
  end

  def is_port_open?(ip, port)
    begin
      Timeout::timeout(1) do
        begin
          s = TCPSocket.new(ip, port)
          s.close
          return true
        rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
          return false
        end
      end
    rescue Timeout::Error
    end

    return false
  end

end

# ---- reference

#@arch=nil
#response = RestClient.get "#{url}/api/architectures", headers
#puts response.body
#puts "---"
#JSON.parse(response.body).each do |arch|
#  @arch=arch['architecture'] if arch['architecture']['name'] == 'i386'
#end

