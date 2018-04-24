module ActiveDataFrame
  class Database

    def self.batching
      !!Thread.current[:active_data_frame_batching]
    end

    def self.batching=(value)
      Thread.current[:active_data_frame_batching] = !!value
    end

    def self.execute(sql)
      if ActiveDataFrame::Database.batching
        Thread.current[:batch] << sql << ?;
      else
        unless sql.empty?
          ActiveRecord::Base.transaction do
            case ActiveRecord::Base.connection_config[:adapter]
            when 'sqlite3'.freeze
              ActiveRecord::Base.connection.raw_connection.execute_batch sql
            when 'mysql2'
              sql.split(';').reject{|x| x.strip.empty?}.each do |stmt|
                ActiveRecord::Base.connection.execute(stmt)
              end
            else
              ActiveRecord::Base.connection.execute(sql)
            end
          end
        end
      end
    end

    def self.flush!
      execute(Thread.current[:batch])
      Thread.current[:batch] = ''
    end

    def self.for_types(block:, df:)
      (@@configs ||= {})[[block, df]] ||= Database.new(block, df)
    end

    attr_reader :block_type, :data_frame_type

    def initialize(block_type, data_frame_type)
      @block_type = block_type
      @data_frame_type = data_frame_type
    end

    def self.batch
      self.batching, prev_batch = true, self.batching
      Thread.current[:batch] ||= ''
      ActiveRecord::Base.transaction do
        yield
      end
    ensure
      self.batching = prev_batch
      flush! unless self.batching
    end
    ##
    # Update block data for all blocks in a single call
    ##
    def bulk_update(existing)
      ActiveDataFrame::DataFrameProxy.suppress_logs do
        case ActiveRecord::Base.connection_config[:adapter]
        when 'postgresql'.freeze
          # Fast bulk update
          updates = ''
          existing.each do |period_index, (values, df_id)|
            updates <<  "(#{df_id}, #{period_index}, #{values.map{|v| v.inspect.gsub('"',"'") }.join(',')}),"
          end
          perform_update(updates)

        when 'mysql2'.freeze
          # Fast bulk update
          updates, on_duplicate = "", ""
          existing.each do |period_index, (values, df_id)|
            updates << "(#{values.map{|v| v.inspect.gsub('"',"'") }.join(',')}, #{df_id}, #{period_index}, '#{data_frame_type.name}'),"
          end
          on_duplicate = block_type::COLUMNS.map do |cname|
            "#{cname}=VALUES(#{cname})"
          end.join(", ")
          stmt = <<-SQL
INSERT INTO #{block_type.table_name} (#{block_type::COLUMNS.join(',')},data_frame_id,period_index,data_frame_type)
VALUES #{updates[0..-2]}
ON DUPLICATE KEY UPDATE #{on_duplicate}
SQL
          ActiveDataFrame::DataFrameProxy.suppress_logs do
            Database.execute(stmt)
          end
        else
          ids = existing.map {|_, (_, id)| id}
          updates = block_type::COLUMNS.map.with_index do |column, column_idx|
            [column, "CASE period_index\n#{existing.map{|period_index, (values, _)| "WHEN #{period_index} then #{values[column_idx]}"}.join("\n")} \nEND\n"]
          end.to_h
          update_statement = updates.map{|cl, up| "#{cl} = #{up}" }.join(', ')
          Database.execute("UPDATE #{block_type.table_name} SET #{update_statement} WHERE
            #{block_type.table_name}.data_frame_id IN (#{ids.join(',')})
            AND #{block_type.table_name}.data_frame_type = '#{data_frame_type.name}'
            AND #{block_type.table_name}.period_index IN (#{existing.keys.join(', ')});
            "
          )
        end
      end
    end

    def bulk_delete(id, indices)
      ActiveDataFrame::DataFrameProxy.suppress_logs do
        block_type.where(data_frame_id: id, period_index: indices).delete_all
      end
    end

    ##
    # Insert block data for all blocks in a single call
    ##
    def bulk_insert(new_blocks, instance)
      ActiveDataFrame::DataFrameProxy.suppress_logs do
        inserts = ''
        new_blocks.each do |period_index, (values)|
          inserts << \
          case ActiveRecord::Base.connection_config[:adapter]
          when 'postgresql', 'mysql2' then "(#{values.map{|v| v.inspect.gsub('"',"'") }.join(',')}, #{instance.id}, #{period_index}, '#{data_frame_type.name}'),"
          else "(#{values.map{|v| v.inspect.gsub('"',"'") }.join(',')}, #{instance.id}, #{period_index}, '#{data_frame_type.name}'),"
          end
        end
        perform_insert(inserts)
      end
    end

    def perform_update(updates)
      ActiveDataFrame::DataFrameProxy.suppress_logs do
        Database.execute(
          <<-SQL
          UPDATE #{block_type.table_name}
            SET #{block_type::COLUMNS.map{|col| "#{col} = t.#{col}" }.join(", ")}
            FROM(
            VALUES #{updates[0..-2]}) as t(data_frame_id, period_index, #{block_type::COLUMNS.join(',')})
            WHERE #{block_type.table_name}.data_frame_id = t.data_frame_id
            AND #{block_type.table_name}.period_index = t.period_index
            AND #{block_type.table_name}.data_frame_type = '#{data_frame_type.name}'
          SQL
        )
        true
      end
    end

    def perform_insert(inserts)
      ActiveDataFrame::DataFrameProxy.suppress_logs do
        sql = "INSERT INTO #{block_type.table_name} (#{block_type::COLUMNS.join(',')}, data_frame_id, period_index, data_frame_type) VALUES #{inserts[0..-2]}"
        Database.execute sql
      end
    end
  end
end