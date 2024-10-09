# frozen_string_literal: true

require "primer/yard"
require_relative "./yard/types_parser"

module Tapioca
  module Compilers
    class Yard < Tapioca::Dsl::Compiler
      ConstantType = type_member { { fixed: T.class_of(::ViewComponent::Base) } }

      # only add types for these components (for now)
      WHITELIST = [
        Primer::Alpha::SelectPanel
      ]

      def self.gather_constants
        descendants_of(::ViewComponent::Base).select do |const|
          registry.find(const) && WHITELIST.include?(const)
        end
      end

      def self.registry
        # update this by running rake docs:build_yard_registry
        @registry ||= Primer::Yard::Registry.make
      end

      def decorate
        entry = self.class.registry.find(constant)

        root.create_path(constant) do |klass|
          [*constant.public_instance_methods(false), :initialize].each do |method_name|
            add_method_to(klass, entry, method_name)
          end
        end
      end

      private

      def param_type_from_name(param_name)
        if param_name.start_with?("**")
          :keyrest
        elsif param_name.start_with?("&")
          :block
        elsif param_name.end_with?(":")
          :key
        else
          # i.e. positional
          :req
        end
      end

      def sanitize_param_name(param_name)
        param_name
          .delete_suffix(":")
          .delete_prefix("&")
          .delete_prefix("**")
      end

      def add_method_to(klass, entry, method_name)
        yard_method = entry.find_method(method_name)
        return unless yard_method

        yard_return_types = yard_method.tags(:return) || []
        yard_params = (yard_method.tags(:param) || []).each_with_object({}) do |param_tag, memo|
          memo[param_tag.name] = param_tag
        end

        parameters = yard_method.parameters.each_with_object([]) do |(param_name, default_value), memo|
          sanitized_param_name = sanitize_param_name(param_name)
          yard_param = yard_params[sanitized_param_name]

          sorbet_param =
            case param_type_from_name(param_name)
            when :req
              if default_value
                create_opt_param(sanitized_param_name, type: convert_types(yard_param.types), default: default_value)
              else
                create_param(sanitized_param_name, type: convert_types(yard_param.types))
              end
            when :key
              if default_value
                create_kw_opt_param(sanitized_param_name, type: convert_types(yard_param.types), default: default_value)
              else
                create_kw_param(sanitized_param_name, type: convert_types(yard_param.types))
              end
            when :keyrest
              create_kw_rest_param(sanitized_param_name, type: convert_types(yard_param.types))
            when :block
              # TODO: what?
              create_block_param(sanitized_param_name, type: convert_types(yard_param.types))
            end

          memo << sorbet_param if sorbet_param
        end

        return_type = if yard_return_types.empty?
          "void"
        else
          convert_types(yard_return_types.first.types)
        end

        klass.create_method(
          method_name,
          parameters: parameters,
          return_type: return_type
        )
      end

      def convert_types(type_strs)
        converted_types = type_strs.flat_map do |type_str|
          TypesParser.parse(type_str).map do |t|
            convert_type_node(t)
          end
        end

        if converted_types.size > 1
          if converted_types.delete("NilClass")
            "T.nilable(#{converted_types.join(", ")})"
          else
            "T.any(#{converted_types.join(", ")})"
          end
        else
          converted_types.join(", ")
        end
      end

      def convert_type_node(node)
        case node
        when CollectionType
          children = node.types.each_with_object([]) do |child, memo|
            memo = convert_type_node(child) unless child.name == "NilClass"
          end

          "#{convert_type_name(node.name)}[#{children.join(", ")}]"
        when Type
          convert_type_name(node.name)
        end
      end

      def convert_type_name(name)
        case name
        when "Array"
          "T::Array"
        when "Hash"
          "T::Hash"
        when "Boolean"
          "T::Boolean"
        when "nil"
          "NilClass"
        else
          name
        end
      end
    end
  end
end
