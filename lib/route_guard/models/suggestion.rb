# frozen_string_literal: true

module RouteGuard
  module Models
    class Suggestion
      attr_reader :fix_type, :description, :diff_lines

      # fix_type: :reorder | :remove | :move_above | :add_action | :rename_helper
      # diff_lines: array of { type: :add | :remove | :context, content: String }
      def initialize(fix_type:, description:, diff_lines: [])
        @fix_type  = fix_type
        @description = description
        @diff_lines  = diff_lines
      end

      # Returns diff as a plain string (used by JSON + CI formatters)
      def diff_to_s
        diff_lines.map do |line|
          prefix = case line[:type]
                   when :add    then "+ "
                   when :remove then "- "
                   else           "  "
                   end
          "#{prefix}#{line[:content]}"
        end.join("\n")
      end
    end
  end
end
