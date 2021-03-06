require 'msgpack'
require 'fluent/output'

module Fluent
  class CassandraInsertor < BufferedOutput

    Fluent::Plugin.register_output('cassandra_insert', self)
    include CassandraConnection

    config_param :host, :string, :default => '127.0.0.1'
    config_param :port, :integer, :default => 9042
    
    config_param :username, :string, :default => nil
    config_param :password, :string, :default => nil
    
    config_param :connect_timeout, :integer, :default => 5

    config_param :keyspace, :string
    config_param :tablename, :string

    config_param :insert_value, :string
    def start
      super
      @session ||= get_session(self.host, self.port, self.keyspace, self.connect_timeout, self.username, self.password)
    end # start

    def shutdown
      super
      @session.close if @session
    end # shutdown

    def configure(conf)
      super

      @insertValue = self.insert_value
    end # configure

    def format(tag, time, record)
      record.to_msgpack
    end

    def write(chunk)
      chunk.msgpack_each { |record|
        @insertValue = prepareParameter(@insertValue, record)
        insertCassandra(@insertValue)
      }
    end # write

    private

    def insertCassandra(insertVal)
      colIns = []
      valIns = []
      tmpStr = nil

      insertVal.split(",").each do |str|
        tmpStr = str.split("=")
        colIns.push(tmpStr[0])
        valIns.push(tmpStr[1])
      end

      cql = "INSERT INTO #{self.keyspace}.#{self.tablename} (#{colIns.join(',')}) VALUES (#{valIns.join(',')});"

      print cql

      begin
        @session.execute(cql)
      rescue Exception => e
        $log.error "Cannot insert record Cassandra: #{e.message}\nTrace: #{e.backtrace.to_s}"

        raise e
      end
    end # insertCassandra

    def prepareParameter(strOri,record)
      tmpCondVal = {}
      tmpStr = nil
      count = 0

      strOri.split(":").each do |str|
        if count > 0
          tmpStr = str.gsub(/(;.*)/, '')
          tmpCondVal[tmpStr] = record[tmpStr]
        end
        count += 1
      end

      tmpCondVal.each do |k,v|
        strOri= strOri.gsub(k,v)
      end

      strOri = strOri.gsub(':','')
      strOri = strOri.gsub(';','')

      strOri
    end # prepareParameter

  end
end