# typed: strict
# frozen_string_literal: true

module Tapioca
  module Compilers
    # ViewComponent dynamically creates a method for each slot defined in a view component.
    #
    # Currently this only defines slot related methods, but a fuller .rbi file could be generated as is done through
    # bin/tapioca gem for view_component.
    #
    # This omits decorating components that are defined in external gems (Primer and Lookbook)
    #
    # For example, for the following component:
    # ~~~rb
    # class MyComponent < ViewComponent::Base
    #   renders_one :header
    # end
    #
    # ~~~
    #
    # The following RBI file will be generated:
    #
    # ~~~rbi
    # class MyComponent
    #   sig { returns(T.untyped) }
    #   def header; end
    #
    #   sig { returns(T::Boolean) }
    #   def header?; end
    #
    #   sig { params(args: T.nilable(T::Array[T.untyped]), _arg1: T.untyped, block: T.untyped).returns(T.untyped) }
    #   def with_header(*args, **_arg1, &block); end
    # end
    # ~~~

    class ViewComponent < Tapioca::Dsl::Compiler
      extend T::Sig

      ConstantType = type_member { { fixed: T.class_of(::ViewComponent::Base) } }

      WHITELIST = [
        Primer::Alpha::SelectPanel
      ]

      sig { override.returns(T::Enumerable[T.class_of(::ViewComponent::Base)]) }
      def self.gather_constants
        descendants_of(::ViewComponent::Base).select do |const|
          WHITELIST.include?(const)
        end
      end

      sig { override.void }
      def decorate
        return if constant.registered_slots.empty?

        root.create_path(constant) do |klass|
          constant.registered_slots.each do |slot, details|
            if details[:collection]
              klass.create_method("with_#{slot.to_s.singularize}", parameters: [
                create_rest_param("args", type: "T.nilable(T::Array[T.untyped])"),
                create_kw_rest_param("_arg1", type: "T.untyped"),
                create_block_param("block", type: "T.untyped"),
              ])
            else
              klass.create_method("with_#{slot}", parameters: [
                create_rest_param("args", type: "T.nilable(T::Array[T.untyped])"),
                create_kw_rest_param("_arg1", type: "T.untyped"),
                create_block_param("block", type: "T.untyped"),
              ])
            end
            klass.create_method("#{slot}", return_type: "T.untyped")
            klass.create_method("#{slot}?", return_type: "T::Boolean")
          end
        end
      end
    end
  end
end
