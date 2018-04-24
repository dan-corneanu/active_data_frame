require 'active_data_frame/data_frame_proxy'
require 'active_data_frame/group_proxy'
require 'active_data_frame/table'
require 'active_data_frame/row'
require 'active_data_frame/has_data_frame'
require 'active_data_frame/database'
require 'rmatrix'

module ActiveDataFrame
  CONFIG = OpenStruct.new({
    suppress_logs: true
  })

  module_function
    def config
      yield CONFIG
    end

    def suppress_logs
      CONFIG.suppress_logs
    end
end