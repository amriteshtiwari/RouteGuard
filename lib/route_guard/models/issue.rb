# frozen_string_literal: true

module RouteGuard
  module Models
    class Issue
      attr_reader :rule_name, :severity, :message, :route, :related_routes, :file, :line
      attr_accessor :suggestion

      def initialize(rule_name:, severity:, message:, route:, related_routes: [], file: nil, line: nil)
        @rule_name = rule_name.to_sym
        @severity = severity.to_sym # :error, :warning
        @message = message
        @route = route
        @related_routes = Array(related_routes)
        @file = file || route&.file
        @line = line || route&.line
      end

      def location
        if file && line
          relative_file = file.sub(/\A#{Regexp.escape(Dir.pwd)}\//, "")
          "#{relative_file}:#{line}"
        elsif file
          file.sub(/\A#{Regexp.escape(Dir.pwd)}\//, "")
        else
          "unknown location"
        end
      end
    end
  end
end
