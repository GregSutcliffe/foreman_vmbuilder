require 'rubygems'
require 'tempfile'
require 'socket'
require 'timeout'
require 'net/ssh'

# set prefix
$hammer = "bundle exec bin/hammer --output csv"

# New hammer awesomeness
class VmBuilder

  attr_accessor :name

  def initialize args
    raise TypeError unless args.is_a? Hash
    #
    # Make a class var out of all the args
    args.each { |k,v| instance_variable_set "@#{k}", v }

    @host     = generate_name(@name)
    @hg_id    = get_id_from_name("hostgroup",@hostgroup)
    @cr_id    = get_id_from_name("compute_resource",@compute_resource)
    @image_id = get_image_uuid(@cr_id,@image)
  end

  def hostname
    @host
  end

  def create_cmd
    cmd  = "#{$hammer}"
    cmd += " host create --name #{@host}"
    cmd += " --hostgroup-id #{@hg_id}"
    cmd += " --compute-resource-id #{@cr_id}"
    cmd += " --compute-attributes 'flavor_ref=1,image_ref=#{@image_id},network=public'"
    cmd += " --parameters 'foreman-repo=#{@deb_repo}'"
    cmd
  end

  def create!
    `#{create_cmd}`
  end

  def delete!
    `#{$hammer} host delete --id #{info[:id]}`
  end

  def test_foreman
    # Assume a puppet run has been done, so we should have one host in Hosts
    file = Tempfile.new('hammer')
    file.write("
:modules:
- hammer_cli_foreman
:foreman:
  :host: 'https://#{info[:ip]}/'
  :username: 'admin'
  :password: 'changeme'
")
    file.close
    puts `bundle exec bin/hammer -c #{file.path} --output csv host list`
    file.unlink    # deletes the temp file
  end 

  def wait_for_ssh!
    print "Waiting for port 22 to open "
    while is_port_open?(info[:ip],22) == false
      sleep 1
      print '.'
    end
    puts " [done]"

    print "Waiting for build state to complete "
    while info(true)[:build] == "true"
      sleep 5
      print '.'
    end
    puts " [done]"
  end

  def ssh commands 
    puts "SSHing to target"
    puts "----------------"
    # TODO: Could move all this to a custom finish-script for the packaging hostgroup
    begin
      Net::SSH.start(info[:ip], 'root', :password => 'test', :paranoid=>false) do |ssh|
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

  def get_id_from_name resource, name
    `#{$hammer} #{resource} list`.split("\n").each do |line|
      return line.split(',').first if line.match(/#{name}/)
    end
    puts "#{resource.capitalize}: '#{name}' not found"
    exit 1
  end

  def get_image_uuid cr_id, name
    `#{$hammer} compute_resource image list --compute-resource-id #{cr_id}`.split("\n").each do |line|
      return line.split(',')[3] if line.match(/#{name}/)
    end
    puts "Image '#{name}' not found"
    exit 2
  end

  def generate_name name
    size = `#{$hammer} host list --search "name ~ #{name}"`.split("\n").size
    # 'size' includes the header, i.e (N results)+1
    size > 1 ? "#{name}#{size}" : "#{name}1"
  end

  def info clear_cache = false
    return @info unless @info.nil? || clear_cache
    @info = {}
    #TODO: fix the domain hardcoding
    data = `#{$hammer} --output base host info --name "#{@host}.elysium.emeraldreverie.org"`.split("\n")
    data.each do |item|
      k,v = item.gsub(/\s/,'').split(':')
      next if k.nil? or v.nil?
      @info[k.downcase.to_sym] = v
    end
    @info
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
