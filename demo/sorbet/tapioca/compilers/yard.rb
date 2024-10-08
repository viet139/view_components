# frozen_string_literal: true

require "primer/yard"

require 'strscan'

module Tapioca
  module Compilers
    class Type
      attr_accessor :name

      def initialize(name)
        @name = name
      end
    end

    class CollectionType < Type
      attr_accessor :types

      def initialize(name, types)
        @name = name
        @types = types
      end
    end

    class FixedCollectionType < CollectionType
    end

    class HashCollectionType < Type
      attr_accessor :key_types, :value_types

      def initialize(name, key_types, value_types)
        @name = name
        @key_types = key_types
        @value_types = value_types
      end
    end

    class TypesParser
      TOKENS = {
        collection_start: /</,
        collection_end: />/,
        fixed_collection_start: /\(/,
        fixed_collection_end: /\)/,
        type_name: /#\w+|((::)?\w+)+/,
        type_next: /[,;]/,
        whitespace: /\s+/,
        hash_collection_start: /\{/,
        hash_collection_next: /=>/,
        hash_collection_end: /\}/,
        parse_end: nil
      }

      def self.parse(string)
        new(string).parse
      end

      def initialize(string)
        @scanner = StringScanner.new(string)
      end

      def parse
        types = []
        type = nil
        name = nil

        loop do
          found = false
          TOKENS.each do |token_type, match|
            if (match.nil? && @scanner.eos?) || (match && token = @scanner.scan(match))
              found = true
              case token_type
              when :type_name
                raise SyntaxError, "expecting END, got name '#{token}'" if name
                name = token
              when :type_next
                raise SyntaxError, "expecting name, got '#{token}' at #{@scanner.pos}" if name.nil?
                unless type
                  type = Type.new(name)
                end
                types << type
                type = nil
                name = nil
              when :fixed_collection_start, :collection_start
                name ||= "Array"
                klass = token_type == :collection_start ? CollectionType : FixedCollectionType
                type = klass.new(name, parse)
              when :hash_collection_start
                name ||= "Hash"
                type = HashCollectionType.new(name, parse, parse)
              when :hash_collection_next, :hash_collection_end, :fixed_collection_end, :collection_end, :parse_end
                raise SyntaxError, "expecting name, got '#{token}'" if name.nil?
                unless type
                  type = Type.new(name)
                end
                types << type
                return types
              end
            end
          end
          raise SyntaxError, "invalid character at #{@scanner.peek(1)}" unless found
        end
      end
    end

    class Yard < Tapioca::Dsl::Compiler
      ConstantType = type_member { { fixed: T.class_of(::ViewComponent::Base) } }

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
          add_initialize_to(klass, entry)
        end
      end

      private

      def add_initialize_to(klass, entry)
        parameter_order =
          constant
            .instance_method(:initialize)
            .parameters
            .map(&:last)

        parameter_map =
          constant
            .instance_method(:initialize)
            .parameters
            .each_with_object({}) do |(param_type, name), memo|
              memo[name] = param_type
            end

        parameters = entry.params.each_with_object([]) do |param, memo|
          param_type = parameter_map[param.name.to_sym]

          sorbet_param = case param_type
          when :key
            create_kw_param(param.name, type: convert_types(param.types))
          when :keyrest
            create_kw_rest_param(param.name, type: convert_types(param.types))
          when :block
            # TODO: what?
            create_block_param(param.name, type: convert_types(param.types))
          end

          memo << sorbet_param if sorbet_param
        end

        parameters.sort! do |a, b|
          parameter_order.index(a.param.name.to_sym) <=> parameter_order.index(b.param.name.to_sym)
        end

        klass.create_method("initialize", parameters: parameters, return_type: "void")
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
