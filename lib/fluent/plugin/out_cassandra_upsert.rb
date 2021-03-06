require 'msgpack'
require 'fluent/output'

module Fluent
  class CassandraUpsertor < BufferedOutput

    Fluent::Plugin.register_output('cassandra_upsert', self)
    include CassandraConnection

    config_param :host, :string, :default => '127.0.0.1'
    config_param :port, :integer, :default => 9042
    
    config_param :username, :string, :default => nil
    config_param :password, :string, :default => nil
      
    config_param :connect_timeout, :integer, :default => 5

    config_param :keyspace, :string
    config_param :tablename, :string

    config_param :case_insert_value, :string
    config_param :case_update_value, :string
    config_param :where_condition_upd, :string, :default => nil
   
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

      # perform validations
      raise ConfigError, "params 'where_condition_upd' is require condition or primarykey for case update" if self.where_condition_upd.nil?
      
      @caseInsertValue = self.case_insert_value
      @caseUpdateValue = self.case_update_value
      @whereCondUpd = self.where_condition_upd
    end # configure

    def format(tag, time, record)
      record.to_msgpack
    end

    def write(chunk)
      chunk.msgpack_each { |record|

        whereCondition = prepareParameter(@whereCondUpd, record)

        cql = "select count(*) from #{self.keyspace}.#{self.tablename}"
        cql += " where " + whereCondition + ";"

        countRow = nil
        begin
          countRow = @session.execute(cql)
        rescue Exception => e
          $log.error "Cannot select Cassandra: #{e.message}\nTrace: #{e.backtrace.to_s}"
          raise e
        end

        countRow = getRowCount(countRow)
        
        if countRow > 0
          @caseUpdateValue = prepareParameter(@caseUpdateValue, record)
          updateCassandra(@caseUpdateValue, whereCondition)
        else
          @caseInsertValue = prepareParameter(@caseInsertValue, record)
          insertCassandra(@caseInsertValue)
        end

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

      begin
        @session.execute(cql)
      rescue Exception => e
        $log.error "Cannot insert record Cassandra: #{e.message}\nTrace: #{e.backtrace.to_s}"

        raise e
      end
    end # insertCassandra

    def updateCassandra(updateVal, whereCondition)

      cql = "update #{self.keyspace}.#{self.tablename} set "
      cql += updateVal + " where " + whereCondition + ";"

      begin
        @session.execute(cql)
      rescue Exception => e
        $log.error "Cannot update record Cassandra: #{e.message}\nTrace: #{e.backtrace.to_s}"

        raise e
      end
    end # updateCassandra

    def getRowCount(countRow)
      rc = 0
      if countRow.length > 0
        countRow.each do |row|
          rc = "#{row['count']}"
        end
        rc = rc.to_i
      end
      rc
    end # getRowCount

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