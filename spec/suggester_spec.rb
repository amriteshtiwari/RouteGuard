# frozen_string_literal: true

require "spec_helper"

RSpec.describe RouteGuard::Suggester do
  def make_route(verb: "GET", path: "/users", controller: "users", action: "index",
                 name: nil, file: "config/routes.rb", line: 5)
    RouteGuard::Models::Route.new(
      verb: verb, path: path, original_path: "#{path}(.:format)",
      controller: controller, action: action, name: name,
      constraints: {}, file: file, line: line, defaults: {}
    )
  end

  def make_issue(rule_name:, route: nil, related_routes: [])
    RouteGuard::Models::Issue.new(
      rule_name: rule_name,
      severity: :warning,
      message: "test message",
      route: route,
      related_routes: related_routes
    )
  end

  # ── shadowed_routes ────────────────────────────────────────────────────────
  describe "shadowed_routes" do
    it "returns a :reorder suggestion" do
      shadowed = make_route(path: "/users/new", action: "new", line: 12)
      shadower = make_route(path: "/users/:id", action: "show", line: 11)
      issue = make_issue(rule_name: :shadowed_routes, route: shadowed, related_routes: [shadower])

      sug = described_class.suggest(issue)

      expect(sug).not_to be_nil
      expect(sug.fix_type).to eq(:reorder)
      expect(sug.description).to include("/users/new")
      expect(sug.description).to include("/users/:id")
      expect(sug.diff_lines.any? { |d| d[:type] == :add }).to be true
      expect(sug.diff_lines.any? { |d| d[:type] == :remove }).to be true
    end

    it "returns nil when route is missing" do
      issue = make_issue(rule_name: :shadowed_routes, route: nil, related_routes: [])
      expect(described_class.suggest(issue)).to be_nil
    end
  end

  # ── duplicate_routes ───────────────────────────────────────────────────────
  describe "duplicate_routes" do
    it "returns a :remove suggestion" do
      original  = make_route(path: "/about", action: "about", line: 3)
      duplicate = make_route(path: "/about", action: "about", line: 47)
      issue = make_issue(rule_name: :duplicate_routes, route: duplicate, related_routes: [original])

      sug = described_class.suggest(issue)

      expect(sug).not_to be_nil
      expect(sug.fix_type).to eq(:remove)
      expect(sug.description).to include("/about")
      expect(sug.diff_lines.any? { |d| d[:type] == :remove }).to be true
    end

    it "returns nil when route is missing" do
      issue = make_issue(rule_name: :duplicate_routes, route: nil)
      expect(described_class.suggest(issue)).to be_nil
    end
  end

  # ── unreachable_routes ────────────────────────────────────────────────────
  describe "unreachable_routes" do
    it "returns a :move_above suggestion" do
      unreachable = make_route(path: "/contact", action: "contact", line: 34)
      catch_all   = make_route(verb: "ANY", path: "/*path", controller: "errors",
                               action: "not_found", line: 33)
      issue = make_issue(rule_name: :unreachable_routes,
                         route: unreachable, related_routes: [catch_all])

      sug = described_class.suggest(issue)

      expect(sug).not_to be_nil
      expect(sug.fix_type).to eq(:move_above)
      expect(sug.description).to include("/contact")
      expect(sug.description).to include("/*path")
    end

    it "returns nil when route is missing" do
      issue = make_issue(rule_name: :unreachable_routes, route: nil)
      expect(described_class.suggest(issue)).to be_nil
    end
  end

  # ── unused_routes ─────────────────────────────────────────────────────────
  describe "unused_routes" do
    it "returns an :add_action suggestion" do
      route = make_route(path: "/*path", verb: "ANY",
                         controller: "application", action: "not_found")
      issue = make_issue(rule_name: :unused_routes, route: route)

      sug = described_class.suggest(issue)

      expect(sug).not_to be_nil
      expect(sug.fix_type).to eq(:add_action)
      expect(sug.description).to include("not_found")
      expect(sug.diff_lines.any? { |d| d[:content].include?("def not_found") }).to be true
    end

    it "returns nil when route is missing" do
      issue = make_issue(rule_name: :unused_routes, route: nil)
      expect(described_class.suggest(issue)).to be_nil
    end
  end

  # ── duplicate_helpers ─────────────────────────────────────────────────────
  describe "duplicate_helpers" do
    it "returns a :rename_helper suggestion" do
      original = make_route(path: "/home", action: "index", name: "home", line: 2)
      conflict = make_route(path: "/welcome", action: "index", name: "home", line: 8)
      issue = make_issue(rule_name: :duplicate_helpers,
                         route: conflict, related_routes: [original])

      sug = described_class.suggest(issue)

      expect(sug).not_to be_nil
      expect(sug.fix_type).to eq(:rename_helper)
      expect(sug.description).to include("as: :home_v2")
    end

    it "returns nil when route is missing" do
      issue = make_issue(rule_name: :duplicate_helpers, route: nil)
      expect(described_class.suggest(issue)).to be_nil
    end
  end

  # ── unknown rule ───────────────────────────────────────────────────────────
  describe "unknown rule" do
    it "returns nil for rules without a fix" do
      issue = make_issue(rule_name: :complexity)
      expect(described_class.suggest(issue)).to be_nil
    end
  end

  # ── Suggestion#diff_to_s ──────────────────────────────────────────────────
  describe RouteGuard::Models::Suggestion do
    it "serializes diff_lines to a string" do
      sug = described_class.new(
        fix_type: :reorder,
        description: "Move X above Y",
        diff_lines: [
          { type: :context, content: "# comment" },
          { type: :remove,  content: "old line" },
          { type: :add,     content: "new line" }
        ]
      )
      str = sug.diff_to_s
      expect(str).to include("  # comment")
      expect(str).to include("- old line")
      expect(str).to include("+ new line")
    end
  end
end
