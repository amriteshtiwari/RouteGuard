# frozen_string_literal: true

require_relative "models/report"
require_relative "rules/duplicate_routes"
require_relative "rules/shadowed_routes"
require_relative "rules/unreachable_routes"
require_relative "rules/duplicate_helpers"
require_relative "rules/duplicate_resources"
require_relative "rules/statistics"
require_relative "rules/complexity"
require_relative "rules/unused_routes"
require_relative "suggester"

module RouteGuard
  class Analyzer
    RULE_MAPPING = {
      duplicate_routes: Rules::DuplicateRoutes,
      shadowed_routes: Rules::ShadowedRoutes,
      unreachable_routes: Rules::UnreachableRoutes,
      duplicate_helpers: Rules::DuplicateHelpers,
      duplicate_resources: Rules::DuplicateResources,
      statistics: Rules::Statistics,
      complexity: Rules::Complexity,
      unused_routes: Rules::UnusedRoutes
    }.freeze

    def self.analyze(routes, enabled_rules, options = {})
      report = Models::Report.new(routes)
      start_time = Time.now

      # 1. Run Statistics first (if enabled)
      if enabled_rules.include?(:statistics)
        stat_rule = Rules::Statistics.new(options)
        stat_rule.analyze(routes, report)
      end

      # 2. Run other lint rules
      issues = []
      lint_rules = %i[duplicate_routes shadowed_routes unreachable_routes duplicate_helpers duplicate_resources unused_routes]
      (lint_rules & enabled_rules).each do |rule_sym|
        rule_class = RULE_MAPPING[rule_sym]
        next unless rule_class

        rule = rule_class.new(options)
        rule_issues = rule.analyze(routes, report)
        issues.concat(rule_issues) if rule_issues.is_a?(Array)
      end

      # Expose intermediate issues on report for Complexity to analyze
      report.issues = issues

      # Update stats with issue metrics
      if report.stats && report.stats.any?
        report.stats[:duplicate_paths] = issues.count { |i| i.rule_name == :duplicate_routes }
        report.stats[:shadowed_routes] = issues.count { |i| i.rule_name == :shadowed_routes }
      end

      # 3. Run Complexity last (if enabled)
      if enabled_rules.include?(:complexity)
        comp_rule = Rules::Complexity.new(options)
        comp_issues = comp_rule.analyze(routes, report)
        issues.concat(comp_issues) if comp_issues.is_a?(Array)
      end

      report.issues = issues

      # Attach auto-fix suggestions to each issue (purely additive)
      issues.each do |issue|
        issue.suggestion = Suggester.suggest(issue)
      end

      report.duration = Time.now - start_time
      report
    end
  end
end
