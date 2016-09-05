# Logstash Plugin

This is a plugin for [Logstash](https://github.com/elastic/logstash).

It is fully free and fully open source. The license is Apache 2.0, meaning you are pretty much free to use it however you want in whatever way.

## Documentation

The RETS input plugin can be configured very simply. Each `rets` input will allow you to send as many queries as desired
against a single [MLS RETS server](www.reso.org/specifications).

The retrieved fields will be stored at the event root level by default (unless the `target` field is configured).

```
input {
  rets {
    url => "http://mls.server.com/Login"
    username => "retsuser"
    password => "retspwd"
    user_agent => "you/1.0"
    user_agent_password => "uapwd"
    rets_version => "RETS/1.5"
    # Supports "cron", "every", "at" and "in" schedules by rufus scheduler
    schedule => { cron => "* * * * * UTC"}
    # The target field in which the RETS fields will be stored
    #target => "rets_fields"
    # A hash of request metadata info (timing, response headers, etc.) will be sent here
    metadata_target => "@rets_metadata"
    queries => {
      properties => {
        resource => "Property"
        class => "RE_1"
        query => "(L_Status=|1_0,1_1,1_2)"
        select => ""
        limit => 1000
      }
      active_agents => {
        resource => "Agent"
        class => "Agent"
        query => "(U_user_is_active=1)"
        select => ""
        limit => 1000
      }
    }
  }
}
output {
  stdout {
    codec => rubydebug
  }
}
```

This plugin must also be scheduled to run periodically according to a specific
schedule. This scheduling syntax is powered by [rufus-scheduler](https://github.com/jmettraux/rufus-scheduler).
The syntax is cron-like with some extensions specific to Rufus (e.g. timezone support ).

Examples:

```
* 5 * 1-3 *               | will execute every minute of 5am every day of January through March.
0 * * * *                 | will execute on the 0th minute of every hour every day.
0 6 * * * America/Chicago | will execute at 6:00am (UTC/GMT -5) every day.
```

Further documentation describing this syntax can be found https://github.com/jmettraux/rufus-schedulerparsing-cronlines-and-time-strings[here].

A sample

```
{
                        "L_ListingID" => "12345678",
                            "L_Class" => "1",
                            "L_Type_" => "7",
                             "L_Area" => "12",
                      "L_SystemPrice" => "165000",
                      "L_AskingPrice" => "165000",
                    "L_AddressNumber" => "1234",
              "L_AddressSearchNumber" => "1234",
                 "L_AddressDirection" => "",
                    "L_AddressStreet" => "Main Street",
                                  ... => ...
                       "L_IdxInclude" => "0",
                    "L_LastDocUpdate" => "",
                           "@version" => "1",
                         "@timestamp" => "2016-09-05T09:13:03.545Z",
                     "@rets_metadata" => {
                               "host" => "iMac.local",
                    "runtime_seconds" => 3.504
                         "query_name" => "properties",
                         "query_spec" => {
                           "resource" => "Property",
                              "class" => "RE_1",
                              "query" => "(L_Status=|1_0)",
                              "limit" => 10
                         }
                    }
}
```

## Need Help?

Need help? Try #logstash on freenode IRC or the https://discuss.elastic.co/c/logstash discussion forum.

## Developing

### 1. Plugin Developement and Testing

#### Code
- To get started, you'll need JRuby with the Bundler gem installed.

- Create a new plugin or clone and existing from the GitHub [logstash-plugins](https://github.com/logstash-plugins) organization. We also provide [example plugins](https://github.com/logstash-plugins?query=example).

- Install dependencies
```sh
bundle install
```

#### Test

- Update your dependencies

```sh
bundle install
```

- Run tests

```sh
bundle exec rspec
```

### 2. Running your unpublished Plugin in Logstash

#### 2.1 Run in a local Logstash clone

- Edit Logstash `Gemfile` and add the local plugin path, for example:
```ruby
gem "logstash-filter-awesome", :path => "/your/local/logstash-filter-awesome"
```
- Install plugin
```sh
bin/logstash-plugin install --no-verify
```
- Run Logstash with your plugin
```sh
bin/logstash -e 'filter {awesome {}}'
```
At this point any modifications to the plugin code will be applied to this local Logstash setup. After modifying the plugin, simply rerun Logstash.

#### 2.2 Run in an installed Logstash

You can use the same **2.1** method to run your plugin in an installed Logstash by editing its `Gemfile` and pointing the `:path` to your local plugin development directory or you can build the gem and install it using:

- Build your plugin gem
```sh
gem build logstash-filter-awesome.gemspec
```
- Install the plugin from the Logstash home
```sh
bin/logstash-plugin install /your/local/plugin/logstash-filter-awesome.gem
```
- Start Logstash and proceed to test the plugin

## Contributing

All contributions are welcome: ideas, patches, documentation, bug reports, complaints, and even something you drew up on a napkin.

Programming is not a required skill. Whatever you've seen about open source and maintainers or community members  saying "send patches or die" - you will not see that here.

It is more important to the community that you are able to contribute.

For more information about contributing, see the [CONTRIBUTING](https://github.com/elastic/logstash/blob/master/CONTRIBUTING.md) file.
