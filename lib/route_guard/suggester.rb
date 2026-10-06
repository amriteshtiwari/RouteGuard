# frozen_string_literal: true

require_relative "models/suggestion"

module RouteGuard
  # Suggester reads an Issue and returns a Suggestion object describing
  # exactly what change to make in routes.rb to fix the problem.
  # It is purely additive — it never modifies any file automatically.
  class Suggester
    # Entry point. Returns a Suggestion or nil if no fix is available.
    def self.suggest(issue)
      new(issue).build
    end

    def initialize(issue)
      @issue = issue
    end

    def build
      case @issue.rule_name
      when :shadowed_routes    then suggest_reorder
      when :duplicate_routes   then suggest_remove
      when :unreachable_routes then suggest_move_above
      when :unused_routes      then suggest_add_action
      when :duplicate_helpers  then suggest_rename_helper
      end
    end

    private

    # ── Fix 1: Shadowed Route ─────────────────────────────────────────────
    # Move the shadowed (literal) route ABOVE the shadowing (dynamic) route.
    def suggest_reorder
      shadowed = @issue.route           # e.g. GET /users/new  (the victim)
      shadower = @issue.related_routes.first  # e.g. GET /users/:id (the cause)
      return nil unless shadowed && shadower

      shadowed_line = route_source(shadowed)
      shadower_line = route_source(shadower)

      diff = [
        { type: :context, content: "# Before (broken order):" },
        { type: :remove,  content: shadower_line },
        { type: :remove,  content: shadowed_line },
        { type: :context, content: "" },
        { type: :context, content: "# After (correct order):" },
        { type: :add,     content: shadowed_line },
        { type: :add,     content: shadower_line }
      ]

      Models::Suggestion.new(
        fix_type:    :reorder,
        description: "Move `#{shadowed.verb} #{shadowed.path}` ABOVE " \
                     "`#{shadower.verb} #{shadower.path}` " \
                     "(#{location_hint(shadower)}) so the literal route matches first.",
        diff_lines:  diff
      )
    end

    # ── Fix 2: Duplicate Route ─────────────────────────────────────────────
    # Remove the duplicate — keep the first definition, delete the second.
    def suggest_remove
      duplicate  = @issue.route                    # the later (dead) duplicate
      original   = @issue.related_routes.first     # the first (active) definition
      return nil unless duplicate

      dup_line = route_source(duplicate)

      diff = [
        { type: :context, content: "# Keep the original (#{location_hint(original)}):" },
        { type: :context, content: route_source(original) },
        { type: :context, content: "" },
        { type: :context, content: "# Remove this duplicate (#{location_hint(duplicate)}):" },
        { type: :remove,  content: dup_line }
      ]

      Models::Suggestion.new(
        fix_type:    :remove,
        description: "Remove the duplicate `#{duplicate.verb} #{duplicate.path}` at " \
                     "#{location_hint(duplicate)}. The active definition is at #{location_hint(original)}.",
        diff_lines:  diff
      )
    end

    # ── Fix 3: Unreachable Route ───────────────────────────────────────────
    # Move the unreachable route to ABOVE the catch-all wildcard.
    def suggest_move_above
      unreachable = @issue.route                  # e.g. GET /contact
      catch_all   = @issue.related_routes.first   # e.g. ANY /*path
      return nil unless unreachable && catch_all

      route_line    = route_source(unreachable)
      catchall_line = route_source(catch_all)

      diff = [
        { type: :context, content: "# Before (broken order):" },
        { type: :remove,  content: catchall_line },
        { type: :remove,  content: route_line },
        { type: :context, content: "" },
        { type: :context, content: "# After (correct order):" },
        { type: :add,     content: route_line },
        { type: :add,     content: catchall_line }
      ]

      Models::Suggestion.new(
        fix_type:    :move_above,
        description: "Move `#{unreachable.verb} #{unreachable.path}` to BEFORE " \
                     "the catch-all `#{catch_all.path}` at #{location_hint(catch_all)}.",
        diff_lines:  diff
      )
    end

    # ── Fix 4: Unused Route (missing controller/action) ────────────────────
    # Suggest adding the action to the controller OR removing the route.
    def suggest_add_action
      route = @issue.route
      return nil unless route

      controller_file = controller_path(route.controller)
      action          = route.action || "???"

      diff = [
        { type: :context, content: "# Option A — Add the missing action to #{controller_file}:" },
        { type: :add,     content: "def #{action}" },
        { type: :add,     content: "  # TODO: implement this action" },
        { type: :add,     content: "end" },
        { type: :context, content: "" },
        { type: :context, content: "# Option B — Remove the route from routes.rb:" },
        { type: :remove,  content: route_source(route) }
      ]

      Models::Suggestion.new(
        fix_type:    :add_action,
        description: "Either add `def #{action}` to `#{controller_file}`, " \
                     "or remove the route `#{route.verb} #{route.path}` from routes.rb.",
        diff_lines:  diff
      )
    end

    # ── Fix 5: Duplicate Named Helper ──────────────────────────────────────
    # Suggest adding `as:` to one of the routes to give it a unique helper name.
    def suggest_rename_helper
      conflict = @issue.route
      original = @issue.related_routes.first
      return nil unless conflict

      helper_name   = conflict.name.to_s
      new_name      = "#{helper_name}_v2"
      conflict_line = route_source(conflict)
      renamed_line  = conflict_line.sub(/\z/, ", as: :#{new_name}")

      diff = [
        { type: :context, content: "# Keep original helper at #{location_hint(original)}:" },
        { type: :context, content: route_source(original) },
        { type: :context, content: "" },
        { type: :context, content: "# Rename the conflicting helper (#{location_hint(conflict)}):" },
        { type: :remove,  content: conflict_line },
        { type: :add,     content: renamed_line }
      ]

      Models::Suggestion.new(
        fix_type:    :rename_helper,
        description: "Add `as: :#{new_name}` to `#{conflict.verb} #{conflict.path}` at " \
                     "#{location_hint(conflict)} to avoid overriding the `#{helper_name}_path` helper.",
        diff_lines:  diff
      )
    end

    # ── Helpers ────────────────────────────────────────────────────────────

    # Reconstruct a readable route line from a Route model.
    def route_source(route)
      return "" unless route

      verb = route.verb.downcase
      verb = "match" if verb == "any"

      controller = route.controller || "???"
      action     = route.action     || "???"

      base = "#{verb} \"#{route.path}\", to: \"#{controller}##{action}\""
      base += ", via: :all" if route.verb == "ANY"
      base
    end

    # Returns a short location string like "config/routes.rb:11"
    def location_hint(route)
      return "unknown location" unless route
      route.location.to_s.empty? ? "unknown location" : route.location
    end

    # Converts a controller name like "admin/users" → "app/controllers/admin/users_controller.rb"
    def controller_path(name)
      return "application_controller.rb" unless name
      "app/controllers/#{name}_controller.rb"
    end
  end
end
