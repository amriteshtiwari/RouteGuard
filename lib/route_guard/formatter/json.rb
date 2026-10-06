# frozen_string_literal: true

require "json"
require "time"
require_relative "../version"

module RouteGuard
  module Formatter
    class Json
      def format(report, io = $stdout)
        data = {
          metadata: {
            version: RouteGuard::VERSION,
            timestamp: Time.now.utc.iso8601,
            duration: report.duration
          },
          summary: {
            routes_count: report.routes.length,
            errors_count: report.errors.length,
            warnings_count: report.warnings.length,
            health_score: report.complexity_score
          },
          statistics: report.stats || {},
          issues: report.issues.map { |issue| format_issue(issue) }
        }

        io.puts JSON.pretty_generate(data)
      end

      private

      def format_issue(issue)
        {
          rule_name: issue.rule_name.to_s,
          severity: issue.severity.to_s,
          message: issue.message,
          location: {
            file: issue.file,
            line: issue.line,
            formatted: issue.location
          },
          route: issue.route ? format_route(issue.route) : nil,
          related_routes: issue.related_routes.map { |r| format_route(r) },
          suggestion: issue.suggestion ? format_suggestion(issue.suggestion) : nil
        }
      end

      def format_route(route)
        {
          verb: route.verb,
          path: route.path,
          original_path: route.original_path,
          controller: route.controller,
          action: route.action,
          name: route.name,
          constraints: route.constraints.transform_values(&:to_s),
          location: route.location
        }
      end

      def format_suggestion(suggestion)
        {
          fix_type:    suggestion.fix_type.to_s,
          description: suggestion.description,
          diff:        suggestion.diff_to_s
        }
      end
    end
  end
end
