# frozen_string_literal: true

module Lepus
  module Saga
    module Sequel
      # Sequel plugin shared by the saga models: UUIDv7 ids generated in Ruby,
      # created_at/updated_at, validations and a JSON column read back as a
      # Hash whether the driver returns a String or an already parsed value.
      module Record
        JSON_COLUMN = [
          ->(value) { JSON.generate(value) },
          ->(value) { value.is_a?(String) ? JSON.parse(value) : value.to_h }
        ].freeze

        def self.apply(model, json_column)
          model.plugin :serialization, JSON_COLUMN, json_column
          model.plugin :timestamps, update_on_create: true
          model.plugin :validation_helpers
        end

        def self.configure(model, _json_column)
          model.raise_on_save_failure = true
        end

        module InstanceMethods
          def before_create
            self.id ||= SecureRandom.uuid_v7
            super
          end
        end
      end
    end
  end
end
