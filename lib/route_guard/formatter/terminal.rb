# frozen_string_literal: true

require "rainbow"
require_relative "../configuration"

module RouteGuard
  module Formatter
    class Terminal
      attr_reader :verbose

      def initialize(verbose: false)
        @verbose = verbose
      end

      def format(report, io = $stdout)
        io.puts Rainbow("─" * 50).faint
        io.puts Rainbow("RouteGuard").bold.cyan
        io.puts "Analyzing Rails Routes..."
        io.puts "#{report.routes.length} routes loaded"
        io.puts "Running #{Configuration::ALL_RULES.length} inspections..."
        io.puts

        Configuration::ALL_RULES.each do |rule|
          issues_for_rule = report.issues.select { |i| i.rule_name == rule }
          if rule == :statistics || rule == :complexity
            io.puts "  #{Rainbow("✓").green} #{rule_display_name(rule)}"
          elsif issues_for_rule.any? { |i| i.severity == :error }
            io.puts "  #{Rainbow("✗").red} #{rule_display_name(rule)}"
          elsif issues_for_rule.any? { |i| i.severity == :warning }
            io.puts "  #{Rainbow("⚠").yellow} #{rule_display_name(rule)}"
          else
            io.puts "  #{Rainbow("✓").green} #{rule_display_name(rule)}"
          end
        end

        io.puts Rainbow("─" * 50).faint

        if report.issues.any?
          io.puts Rainbow("Issues Found").bold.yellow
          io.puts

          report.issues.each do |issue|
            severity_color = issue.severity == :error ? :red : :yellow
            severity_prefix = issue.severity == :error ? "✗ Error" : "⚠ Warning"

            io.puts Rainbow("#{severity_prefix} [#{rule_display_name(issue.rule_name)}]:").bold.send(severity_color)
            io.puts "  #{issue.message}"
            if issue.route
              io.puts "  Route: #{Rainbow(issue.route.to_s).bold}"
            end

            if issue.file && issue.line
              io.puts "  Location: #{Rainbow(issue.location).underline}"
            end

            if issue.related_routes.any?
              io.puts "  Related Route(s):"
              issue.related_routes.each do |rel|
                io.puts "    - #{Rainbow(rel.to_s).bold} at #{Rainbow(rel.location).underline}"
              end
            end

            # ── Auto-Fix Suggestion ────────────────────────────────────────
            if issue.suggestion
              sug = issue.suggestion
              io.puts "  #{Rainbow("💡 Suggested Fix:").cyan.bold} #{sug.description}"
              io.puts "  #{Rainbow("─" * 48).faint}"
              sug.diff_lines.each do |dl|
                case dl[:type]
                when :add
                  io.puts "  #{Rainbow("+ #{dl[:content]}").green}"
                when :remove
                  io.puts "  #{Rainbow("- #{dl[:content]}").red}"
                else
                  io.puts "  #{Rainbow("  #{dl[:content]}").faint}"
                end
              end
              io.puts "  #{Rainbow("─" * 48).faint}"
            end

            io.puts
          end
          io.puts Rainbow("─" * 50).faint
        else
          io.puts Rainbow("✓ No issues found! Your routes look excellent.").green.bold
          io.puts
        end

        # Summary
        io.puts Rainbow("Summary").bold.cyan
        io.puts "  %-15s %d" % ["Routes", report.routes.length]
        io.puts "  %-15s %d" % ["Errors", report.errors.length]
        io.puts "  %-15s %d" % ["Warnings", report.warnings.length]

        health_color = if report.complexity_score >= 90
                         :green
                       elsif report.complexity_score >= 70
                         :yellow
                       else
                         :red
                       end
        io.puts "  %-15s %s" % ["Health", Rainbow("#{report.complexity_score} / 100").bold.send(health_color)]
        io.puts "  %-15s %.3f seconds" % ["Duration", report.duration]
        io.puts Rainbow("─" * 50).faint
      end

      private

      def rule_display_name(rule)
        rule.to_s.split("_").map(&:capitalize).join(" ")
      end
    end
  end
end
