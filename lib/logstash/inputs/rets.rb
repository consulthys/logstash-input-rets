# encoding: utf-8
require "logstash/inputs/base"
require "logstash/namespace"
require "socket" # for Socket.gethostname
require "rufus/scheduler"
require "rets"

# This Logstash input plugin allows you to call an MLS RETS server, decode the output of it into event(s), and
# send them on their merry way.
#
# ==== Example
# Sends a list of RETS queries to an MLS RETS server and decodes the body of the response with a codec.
# The config should look like this:
#
# [source,ruby]
# ----------------------------------
# input {
#   rets {
#     url => "http://mls.server.com/Login"
#     username => "retsuser"
#     password => "retspwd"
#     user_agent => "you/1.0"
#     user_agent_password => "uapwd"
#     rets_version => "RETS/1.5"
#     # Supports "cron", "every", "at" and "in" schedules by rufus scheduler
#     schedule => { cron => "* * * * * UTC"}
#     # A hash of request metadata info (timing, response headers, etc.) will be sent here
#     metadata_target => "@rets_metadata"
#     queries => {
#       properties => {
#         resource => "Property"
#         class => "RE_1"
#         query => "(L_Status=|1_0,1_1,1_2)"
#         select => ""
#         limit => 1000
#       }
#     }
#   }
# }
#
# output {
#   stdout {
#     codec => rubydebug
#   }
# }
# ----------------------------------

class MyStatsReporter
  def time(metric_name, &block)
    started = Time.now
    block.call
    puts "#{metric_name} => time: #{Time.now - started}"
  end

  def gauge(metric_name, measurement)
    puts "#{metric_name} => gauge: #{measurement}"
  end

  def count(metric_name, count=1)
    puts "#{metric_name} => count: #{count}"
  end
end

class LogStash::Inputs::Rets < LogStash::Inputs::Base
  config_name "rets"

  # If undefined, Logstash will complain, even if codec is unused.
  default :codec, "plain"

  # The URL of the MLS RETS server login endpoint
  config :url, :validate => :string, :required => true

  # The username to use for logging in
  config :username, :validate => :string, :required => true

  # The password to use for logging in
  config :password, :validate => :string, :required => true

  # The user agent to use for logging in
  config :user_agent, :validate => :string, :required => true

  # The user agent password to use for logging in
  config :user_agent_password, :validate => :string, :required => false

  # The RETS version to use
  config :rets_version, :validate => :string, :required => true, :default => 'RETS/1.7.2'

  # A Hash of queries
  config :queries, :validate => :hash, :required => true

  # Define the target field for placing the received data. If this setting is omitted, the data will be stored at the root (top level) of the event.
  config :target, :validate => :string, :required => false

  # Schedule of when to periodically poll from the urls
  # Format: A hash with
  #   + key: "cron" | "every" | "in" | "at"
  #   + value: string
  # Examples:
  #   a) { "every" => "1h" }
  #   b) { "cron" => "* * * * * UTC" }
  # See: rufus/scheduler for details about different schedule options and value string format
  config :schedule, :validate => :hash, :required => true

  # If you'd like to work with the request/response metadata.
  # Set this value to the name of the field you'd like to store a nested
  # hash of metadata.
  config :metadata_target, :validate => :string, :default => '@metadata'

  # A flag indicating whether requests stats need to be collected or not
  config :collect_stats, :validate => :boolean, :required => false, :default => false

  public
  Schedule_types = %w(cron every at in)
  def register
    @host = Socket.gethostname.force_encoding(Encoding::UTF_8)

    @logger.info("Registering rets Input", :type => @type, :url => @url, :schedule => @schedule)

    setup_rets_client!
    setup_requests!
  end # def register

  private
  def setup_rets_client!
    @client = Rets::Client.new({
        login_url: @url,
        username: @username,
        password: @password,
        agent: @user_agent,
        ua_password: @user_agent_password,
        version: @rets_version,
        logger: @logger
        #stats_collector: @collect_stats ? MyStatsReporter.new : nil,
        #stats_prefix: 'rets',
        #http_timing_stats_collector: @collect_stats ? MyStatsReporter.new : nil,
        #http_timing_stats_prefix: 'rets'
    })
  end # def setup_rets_client!

  private
  def setup_requests!
    @requests = Hash[@queries.map {|name, raw_spec| [name, setup_request(raw_spec)] }]
  end # def setup_requests!

  private
  def setup_request(raw_spec)
    if raw_spec.is_a?(Hash)
      spec = Hash[raw_spec.clone.map {|k,v| [k.to_sym, v] }] # symbolize keys
    else
      raise LogStash::ConfigurationError, "Invalid request spec: '#{raw_spec}', expected a Hash!"
    end

    spec
  end # def setup_request

  public
  def run(queue)
    setup_schedule(queue)
  end # def run

  private
  def setup_schedule(queue)
    #schedule hash must contain exactly one of the allowed keys
    msg_invalid_schedule = "Invalid config. schedule hash must contain " +
        "exactly one of the following keys - cron, at, every or in"
    raise Logstash::ConfigurationError, msg_invalid_schedule if @schedule.keys.length !=1
    schedule_type = @schedule.keys.first
    schedule_value = @schedule[schedule_type]
    raise LogStash::ConfigurationError, msg_invalid_schedule unless Schedule_types.include?(schedule_type)

    @scheduler = Rufus::Scheduler.new(:max_work_threads => 1)
    #as of v3.0.9, :first_in => :now doesn't work. Use the following workaround instead
    opts = schedule_type == "every" ? { :first_in => 0.01 } : {}
    @scheduler.send(schedule_type, schedule_value, opts) { run_once(queue) }
    @scheduler.join
  end # def setup_schedule

  private
  def run_once(queue)
    @requests.each do |name, request|
      request_rets(queue, name, request)
    end
  end # def run_once

  private
  def request_rets(queue, name, request)
    @logger.debug? && @logger.debug("Querying RETS", :url => @url, :name => name, :request => request)
    started = Time.now

    begin
      @client.login

      results = @client.find :all, {
          search_type: request[:resource],
          class: request[:class],
          query: request[:query],
          select: request[:select],
          limit: request[:limit]
      }
      handle_success(queue, name, request, results, Time.now - started)

    rescue => exc
      @logger.error("Error while querying RETS", :error => exc)
      handle_failure(queue, name, request, exc, Time.now - started)
    end
    @client.logout
  end # def request_rets

  private
  def handle_success(queue, name, request, results, execution_time)
    results.each do |result|
      event = @target ? LogStash::Event.new(@target => result) : LogStash::Event.new(result)
      apply_metadata(event, name, request, results, execution_time)
      decorate(event)
      queue << event
    end
  end # def handle_success

  private
  # Beware, on old versions of manticore some uncommon failures are not handled
  def handle_failure(queue, name, request, exception, execution_time)
    event = LogStash::Event.new
    apply_metadata(event, name, request)

    event.tag("_rets_request_failure")

    # This is also in the metadata, but we send it anyone because we want this
    # persisted by default, whereas metadata isn't. People don't like mysterious errors
    event["rets_request_failure"] = {
        "request" => structure_request(request),
        "name" => name,
        "error" => exception.to_s,
        "backtrace" => exception.backtrace,
        "runtime_seconds" => execution_time
    }

    queue << event
  rescue StandardError, java.lang.Exception => e
    @logger.error? && @logger.error("Cannot send RETS query or send the error as an event!",
                                    :exception => e,
                                    :exception_message => e.message,
                                    :exception_backtrace => e.backtrace,
                                    :url => @url,
                                    :name => name,
                                    :request => request
    )
  end # def handle_failure

  private
  def apply_metadata(event, name, request, results=nil, execution_time=nil)
    return unless @metadata_target
    event[@metadata_target] = event_metadata(name, request, results, execution_time)
  end # def apply_metadata

  private
  def event_metadata(name, request, results=nil, execution_time=nil)
    meta = {
        "host" => @host,
        "query_name" => name,
        "query_spec" => structure_request(request),
        "runtime_seconds" => execution_time
    }

    #if response
    #  meta["code"] = response.code
    #  meta["response_headers"] = response.headers
    #  meta["response_message"] = response.message
    #  meta["times_retried"] = response.times_retried
    #end

    meta
  end # def event_metadata

  private
  # Turn request into a hash for friendlier logging / ES indexing
  def structure_request(request)
    # stringify any keys to normalize
    Hash[request.map {|k,v| [k.to_s,v] }]
  end

  public
  def stop
    @scheduler.stop
    @client.logout
  end # def stop
end # class LogStash::Inputs::Rets
